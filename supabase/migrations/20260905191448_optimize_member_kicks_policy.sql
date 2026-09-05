-- Supabase flags RLS policies that call auth.<function>() directly: the
-- claim lookups (current_setting()) get re-evaluated for every row the
-- policy checks. Wrapping the calls in scalar subqueries lets the planner
-- evaluate them once per query. No behavior change.

DROP POLICY IF EXISTS "Removed members can read their own kicks" ON public.member_kicks;
CREATE POLICY "Removed members can read their own kicks"
    ON public.member_kicks FOR SELECT
    USING (
        user_id = (select auth.uid())
        OR lower(email) = (select lower(auth.email()))
    );
