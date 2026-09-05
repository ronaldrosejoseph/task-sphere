-- Security Advisor cleanup for SECURITY DEFINER functions created after
-- 20260902193439_restrict_security_definer_execution.sql (that migration
-- covered everything that existed then; new functions default back to
-- PUBLIC EXECUTE). Same convention as the original cleanup:
--   - Trigger-only functions need no EXECUTE at all: triggers invoke them
--     with the function owner's privileges regardless of grants.
--   - The member_kicks RLS policy helper must stay executable by
--     authenticated (policies evaluate it on every member_kicks query);
--     anon never queries protected tables.
-- All statements are idempotent.

-- 1. TRIGGER-ONLY FUNCTIONS -- no client caller needs EXECUTE.
REVOKE EXECUTE ON FUNCTION public.notify_member_removal()
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.revoke_removed_member_access()
    FROM PUBLIC, anon, authenticated, service_role;

-- 2. RLS POLICY HELPER (member_kicks) -- authenticated keeps EXECUTE.
REVOKE EXECUTE ON FUNCTION public.is_kick_recipient(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_kick_recipient(uuid, text) TO authenticated;
