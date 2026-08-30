-- Workspace deletion must revoke member access, and plain members must not
-- create new workspaces.
--
-- 1. allowed_signup_emails gains an is_site_admin flag. The site admin is the
--    account used to set the app up; it is never revoked by workspace
--    deletion. The flag is set once from the SQL editor (auth.uid() is NULL
--    there) and protected from client-side changes by a trigger.
-- 2. can_access_app() / can_create_workspace() are the client-facing RPCs the
--    app consults to gate sign-in and workspace creation.
-- 3. A BEFORE INSERT trigger blocks workspace creation for revoked users and
--    plain members even when a client bypasses the app.
-- 4. A BEFORE DELETE trigger removes the deleted workspace's members from the
--    allowlist unless they are the site admin or still part of another
--    workspace.

-- 1. SITE ADMIN FLAG
ALTER TABLE public.allowed_signup_emails
    ADD COLUMN IF NOT EXISTS is_site_admin BOOLEAN NOT NULL DEFAULT false;

-- Only the database owner (SQL editor) may change the flag; workspace admins
-- can otherwise edit allowlist rows through the "Admins can manage the signup
-- allowlist" RLS policy and could self-promote.
CREATE OR REPLACE FUNCTION public.protect_site_admin_flag()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NEW.is_site_admin IS DISTINCT FROM OLD.is_site_admin THEN
        RAISE EXCEPTION 'The site admin flag can only be changed by the database owner.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_allowlist_site_admin_guard ON public.allowed_signup_emails;
CREATE TRIGGER on_allowlist_site_admin_guard
    BEFORE UPDATE ON public.allowed_signup_emails
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_site_admin_flag();

-- 2. ACCESS RPCs
-- A user may enter the app when they are the site admin, still allowlisted,
-- or a member of at least one workspace.
CREATE OR REPLACE FUNCTION public.can_access_app()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.allowed_signup_emails
        WHERE lower(email) = lower(auth.email()) AND is_site_admin
    )
    OR EXISTS (
        SELECT 1 FROM public.allowed_signup_emails
        WHERE lower(email) = lower(auth.email())
    )
    OR EXISTS (
        SELECT 1 FROM public.workspace_members
        WHERE user_id = auth.uid() OR lower(email) = lower(auth.email())
    );
$$;

-- A user may create a workspace when they are the site admin, or when they
-- are still allowlisted and not a plain member of any workspace (admins of
-- existing workspaces may create more; revoked members may not).
CREATE OR REPLACE FUNCTION public.can_create_workspace()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.allowed_signup_emails
        WHERE lower(email) = lower(auth.email()) AND is_site_admin
    )
    OR (
        EXISTS (
            SELECT 1 FROM public.allowed_signup_emails
            WHERE lower(email) = lower(auth.email())
        )
        AND NOT EXISTS (
            SELECT 1 FROM public.workspace_members
            WHERE user_id = auth.uid() AND role = 'member'
        )
    );
$$;

-- 3. WORKSPACE CREATION RESTRICTION
CREATE OR REPLACE FUNCTION public.restrict_workspace_creation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.can_create_workspace() THEN
        RAISE EXCEPTION 'Only admins can create new workspaces. Contact an admin for access.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_workspace_created_restrict ON public.workspaces;
CREATE TRIGGER on_workspace_created_restrict
    BEFORE INSERT ON public.workspaces
    FOR EACH ROW
    EXECUTE FUNCTION public.restrict_workspace_creation();

-- 4. ALLOWLIST CLEANUP ON WORKSPACE DELETION
-- Runs BEFORE the delete so workspace_members rows still exist; the site
-- admin and members of other workspaces keep their allowlist entry.
CREATE OR REPLACE FUNCTION public.revoke_deleted_workspace_members()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.allowed_signup_emails a
    USING public.workspace_members m
    WHERE m.workspace_id = OLD.id
      AND lower(a.email) = lower(m.email)
      AND a.is_site_admin = false
      AND NOT EXISTS (
          SELECT 1 FROM public.workspace_members m2
          WHERE lower(m2.email) = lower(a.email)
            AND m2.workspace_id <> OLD.id
      );
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS on_workspace_deleted_revoke ON public.workspaces;
CREATE TRIGGER on_workspace_deleted_revoke
    BEFORE DELETE ON public.workspaces
    FOR EACH ROW
    EXECUTE FUNCTION public.revoke_deleted_workspace_members();
