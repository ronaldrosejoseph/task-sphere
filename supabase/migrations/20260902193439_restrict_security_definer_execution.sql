-- Supabase Security Advisor cleanup: SECURITY DEFINER functions should only
-- be executable where the app actually needs them.
--
-- Postgres grants EXECUTE to PUBLIC on new functions by default, so every
-- SECURITY DEFINER function was callable as anon/authenticated via
-- /rest/v1/rpc/... The fix revokes EXECUTE from PUBLIC and re-grants it per
-- function category:
--   - Trigger-only functions need no EXECUTE at all: triggers invoke them
--     with the function owner's privileges regardless of grants.
--   - RLS policy helpers and the two app RPCs must stay executable by
--     authenticated (policies evaluate them on every table query, and the
--     app calls them after sign-in); anon never queries protected tables.
-- All statements are idempotent.

-- 0011: the one SECURITY DEFINER function created without an explicit
-- search_path (role-mutable search paths can redirect to attacker schemas).
ALTER FUNCTION public.seed_default_workspace_lanes() SET search_path = public;

-- 1. RLS POLICY HELPERS -- authenticated keeps EXECUTE (RLS policies on
-- tasks/lanes/members/comments/subtasks/workspaces/allowlist call them),
-- anon does not query any of those tables.
REVOKE EXECUTE ON FUNCTION public.is_workspace_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.is_workspace_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_workspace_admin(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.is_any_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_any_admin() TO authenticated;

-- 2. APP RPCS (sign-in gate, workspace creation gate) -- authenticated only.
REVOKE EXECUTE ON FUNCTION public.can_access_app() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_access_app() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.can_create_workspace() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_create_workspace() TO authenticated;

-- 3. TRIGGER-ONLY FUNCTIONS -- no client caller needs EXECUTE. Triggers fire
-- them as the owner (SECURITY DEFINER) independent of these grants.
REVOKE EXECUTE ON FUNCTION public.seed_default_workspace_lanes()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.fill_member_user_id()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.backfill_member_user_id()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.restrict_signup()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.protect_site_admin_flag()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.restrict_workspace_creation()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.revoke_deleted_workspace_members()
    FROM PUBLIC, anon, authenticated, service_role;

-- rls_auto_enable() exists only in the production database (created manually
-- in the SQL editor; not part of migration history) and has no callers.
-- Guarded so fresh databases, which never had it, apply cleanly.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname = 'rls_auto_enable') THEN
        REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()
            FROM PUBLIC, anon, authenticated, service_role;
    END IF;
END $$;
