-- Workspace creation and deletion become site-admin-only operations.
--
-- Before: can_create_workspace() returned true for any allowlisted user who
-- was not a plain member — which includes every workspace admin — and the
-- workspaces DELETE policy allowed the creator or any workspace admin.
-- After: only the account flagged is_site_admin in allowed_signup_emails may
-- create a new workspace or delete one. Workspace admins keep everything
-- else (settings, members, lanes, invites). Idempotent.

-- Helper used by policies/triggers (authenticated EXECUTE like the other
-- RLS policy helpers; anon never queries protected tables).
CREATE OR REPLACE FUNCTION public.is_site_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.allowed_signup_emails
        WHERE lower(email) = lower(auth.email()) AND is_site_admin
    );
$$;

REVOKE EXECUTE ON FUNCTION public.is_site_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_site_admin() TO authenticated;

-- Workspace creation: site admin only (keeps restrict_workspace_creation,
-- the BEFORE INSERT trigger, as the enforcement point).
CREATE OR REPLACE FUNCTION public.can_create_workspace()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT public.is_site_admin();
$$;

-- Workspace deletion: site admin only. The database cascade deletes the
-- members/lanes/tasks; the existing triggers handle member kicks, allowlist
-- revocation, and site-admin membership protection (their cascade
-- exemptions apply because the parent row is gone first).
DROP POLICY IF EXISTS "Admins can delete workspaces" ON public.workspaces;
CREATE POLICY "Only the site admin can delete workspaces"
    ON public.workspaces FOR DELETE
    USING (public.is_site_admin());
