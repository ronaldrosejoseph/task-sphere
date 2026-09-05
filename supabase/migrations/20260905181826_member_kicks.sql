-- Member removals must reach the removed member's devices in realtime, but
-- the removal itself deletes the only row that granted them access. Realtime
-- applies RLS when delivering DELETE events, and is_workspace_member() is a
-- live lookup that fails the moment the membership row is gone, so the
-- workspace/membership channels never deliver the removal to the removed
-- user.
--
-- Fix: an AFTER DELETE trigger on workspace_members writes a per-user
-- notification row into member_kicks. The table's SELECT policy is
-- column-based (user_id / email of the affected member), so it keeps passing
-- after the removal, and the row is delivered as an INSERT the member's
-- device subscribes to. The trigger also fires for cascade deletes (a whole
-- workspace being deleted), giving that flow a second, reliable signal.

CREATE TABLE IF NOT EXISTS public.member_kicks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    user_id UUID,
    email TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.member_kicks ENABLE ROW LEVEL SECURITY;

-- Only the removed member can read their own kick. Column comparison only:
-- no membership lookup, so the policy never breaks when access is revoked.
DROP POLICY IF EXISTS "Removed members can read their own kicks" ON public.member_kicks;
CREATE POLICY "Removed members can read their own kicks"
    ON public.member_kicks FOR SELECT
    USING (user_id = auth.uid() OR lower(email) = lower(auth.email()));

-- SECURITY DEFINER so the INSERT runs with the function owner's privileges
-- (clients have no INSERT policy and must not be able to forge kicks).
CREATE OR REPLACE FUNCTION public.notify_member_removal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.member_kicks (workspace_id, user_id, email)
    VALUES (OLD.workspace_id, OLD.user_id, lower(OLD.email));
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_member_removed_notify ON public.workspace_members;
CREATE TRIGGER on_member_removed_notify
    AFTER DELETE ON public.workspace_members
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_member_removal();

-- New table needs to be in the realtime publication or no postgres_changes
-- events are emitted for it.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'member_kicks'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.member_kicks;
    END IF;
END;
$$;
