-- Security Advisor cleanup: protect_site_admin_membership() is a
-- trigger-only SECURITY DEFINER function (BEFORE DELETE on workspace_members,
-- created in 20260905234633_protect_site_admin_membership.sql). It was added
-- after 20260905215000_restrict_new_security_definer_functions.sql, so it
-- defaulted back to PUBLIC EXECUTE and surfaced as an anon-callable RPC.
-- Same convention as the earlier cleanups:
--   - Trigger-only functions need no EXECUTE at all: triggers invoke them
--     with the function owner's privileges regardless of grants.
-- Idempotent.
REVOKE EXECUTE ON FUNCTION public.protect_site_admin_membership()
    FROM PUBLIC, anon, authenticated, service_role;
