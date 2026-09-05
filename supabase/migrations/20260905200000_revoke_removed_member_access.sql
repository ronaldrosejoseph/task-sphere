-- Removing a member from a workspace must revoke their sign-in access the
-- same way deleting a workspace does: once they belong to no workspace, the
-- allowlist entry goes away and the next sign-in is blocked. Without this, a
-- removed member with no other workspace could keep signing in and linger in
-- a no-access state. Fires for app-side removals and for cascade deletes of
-- a whole workspace (where revoke_deleted_workspace_members already ran —
-- the delete is a no-op there).

CREATE OR REPLACE FUNCTION public.revoke_removed_member_access()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only revoke when the member has no OTHER workspace membership left
    -- (case-insensitive email match); the site admin is never revoked.
    DELETE FROM public.allowed_signup_emails a
    WHERE lower(a.email) = lower(OLD.email)
      AND a.is_site_admin = false
      AND NOT EXISTS (
          SELECT 1 FROM public.workspace_members m2
          WHERE lower(m2.email) = lower(OLD.email)
            AND m2.workspace_id <> OLD.workspace_id
      );
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_member_removed_revoke_access ON public.workspace_members;
CREATE TRIGGER on_member_removed_revoke_access
    AFTER DELETE ON public.workspace_members
    FOR EACH ROW
    EXECUTE FUNCTION public.revoke_removed_member_access();
