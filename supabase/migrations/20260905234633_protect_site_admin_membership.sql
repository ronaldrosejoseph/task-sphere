-- A workspace admin must never be able to remove the site admin from a
-- workspace (their row is the app owner's access). The RLS delete policy
-- cannot express this without recursive policies, so a BEFORE DELETE
-- trigger raises instead — loud failure, not a silent no-op.
--
-- Exemptions:
--   - The site admin acting on their own row (not offered by the app).
--   - Cascade deletes when a workspace itself is deleted: the parent
--     workspace row is already gone by the time members cascade, so the
--     EXISTS check fails and deletion proceeds (workspace deletion already
--     handles every member equally). Direct SQL-editor deletes run with no
--     request claims and are blocked; clear the flag first if cleanup of
--     the row is ever needed.

CREATE OR REPLACE FUNCTION public.protect_site_admin_membership()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.workspaces WHERE id = OLD.workspace_id
    ) AND EXISTS (
        SELECT 1 FROM public.allowed_signup_emails
        WHERE lower(email) = lower(OLD.email) AND is_site_admin
    ) AND lower(auth.email()) IS DISTINCT FROM lower(OLD.email) THEN
        RAISE EXCEPTION 'The site admin cannot be removed from a workspace.';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_member_removed_protect_site_admin ON public.workspace_members;
CREATE TRIGGER on_member_removed_protect_site_admin
    BEFORE DELETE ON public.workspace_members
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_site_admin_membership();
