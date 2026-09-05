-- The database advisor still flags the member_kicks SELECT policy even with
-- auth.*() wrapped in scalar subqueries, so take the claim lookups out of the
-- policy expression altogether: a SECURITY DEFINER helper (same pattern as
-- is_workspace_member / is_workspace_admin, which never trigger the warning)
-- reads auth.uid()/auth.email() internally. The helper reads no tables, so
-- SECURITY DEFINER cannot leak anything here.

CREATE OR REPLACE FUNCTION public.is_kick_recipient(kick_user_id UUID, kick_email TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT kick_user_id = auth.uid() OR lower(kick_email) = lower(auth.email());
$$;

DROP POLICY IF EXISTS "Removed members can read their own kicks" ON public.member_kicks;
CREATE POLICY "Removed members can read their own kicks"
    ON public.member_kicks FOR SELECT
    USING (public.is_kick_recipient(user_id, email));
