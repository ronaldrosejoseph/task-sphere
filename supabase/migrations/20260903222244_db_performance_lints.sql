-- Supabase Database Linter cleanup (issue #113). All changes are
-- behavior-preserving; they only remove redundant per-policy work and add
-- indexes the linter flagged:
--   1. multiple_permissive_policies: no action on a table should be granted
--      by more than one permissive policy (each one runs for every query).
--   2. auth_rls_initplan: wrap auth.uid() in a scalar subquery so Postgres
--      evaluates it once per query instead of once per scanned row.
--   3. unindexed_foreign_keys: index every FK column so cascaded deletes and
--      membership/activity lookups do not seq scan.

-- 1. DUPLICATE PERMISSIVE POLICIES
-- tasks / subtasks: the FOR ALL "modify" policy grants SELECT with the same
-- member check as the standalone view policy, so the view policies are
-- redundant and are dropped (permissive policies OR together, so members
-- keep SELECT through the FOR ALL policy).
DROP POLICY IF EXISTS "Workspace members can view tasks" ON public.tasks;
DROP POLICY IF EXISTS "Workspace members can view subtasks" ON public.subtasks;

-- workspace_lanes / workspace_members: the view policy (any member) grants
-- SELECT more broadly than the FOR ALL modify policy (admins only), so the
-- view policies stay and the modify policies are narrowed to
-- INSERT/UPDATE/DELETE. Admins keep every command (the workspace admin is
-- always a member row, so lane/member SELECT still applies); members keep
-- SELECT.
DROP POLICY IF EXISTS "Workspace admins can modify lanes" ON public.workspace_lanes;
CREATE POLICY "Workspace admins can insert lanes"
    ON public.workspace_lanes FOR INSERT
    WITH CHECK (public.is_workspace_admin(workspace_id));
CREATE POLICY "Workspace admins can update lanes"
    ON public.workspace_lanes FOR UPDATE
    USING (public.is_workspace_admin(workspace_id))
    WITH CHECK (public.is_workspace_admin(workspace_id));
CREATE POLICY "Workspace admins can delete lanes"
    ON public.workspace_lanes FOR DELETE
    USING (public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS "Workspace admins can modify members" ON public.workspace_members;
CREATE POLICY "Workspace admins can insert members"
    ON public.workspace_members FOR INSERT
    WITH CHECK (public.is_workspace_admin(workspace_id));
CREATE POLICY "Workspace admins can update members"
    ON public.workspace_members FOR UPDATE
    USING (public.is_workspace_admin(workspace_id))
    WITH CHECK (public.is_workspace_admin(workspace_id));
CREATE POLICY "Workspace admins can delete members"
    ON public.workspace_members FOR DELETE
    USING (public.is_workspace_admin(workspace_id));

-- 2. AUTH RLS INITPLAN + task_comments DELETE MERGE
-- The two DELETE policies are merged into one OR'd policy, and every direct
-- auth.uid() call in a policy expression is wrapped so it is evaluated once
-- per query.
DROP POLICY IF EXISTS "Users can delete their own comments" ON public.task_comments;
DROP POLICY IF EXISTS "Admins can delete any comment" ON public.task_comments;
CREATE POLICY "Users can delete their own comments; admins any"
    ON public.task_comments FOR DELETE
    USING ((user_id = (select auth.uid())) OR public.is_workspace_admin(workspace_id));

DROP POLICY IF EXISTS "Users can view workspaces they belong to" ON public.workspaces;
CREATE POLICY "Users can view workspaces they belong to"
    ON public.workspaces FOR SELECT
    USING (((select auth.uid()) = admin_id) OR public.is_workspace_member(id));

DROP POLICY IF EXISTS "Admins can update workspace settings" ON public.workspaces;
CREATE POLICY "Admins can update workspace settings"
    ON public.workspaces FOR UPDATE
    USING (((select auth.uid()) = admin_id) OR public.is_workspace_admin(id));

DROP POLICY IF EXISTS "Authenticated users can create workspaces" ON public.workspaces;
CREATE POLICY "Authenticated users can create workspaces"
    ON public.workspaces FOR INSERT
    WITH CHECK ((select auth.uid()) = admin_id);

DROP POLICY IF EXISTS "Admins can delete workspaces" ON public.workspaces;
CREATE POLICY "Admins can delete workspaces"
    ON public.workspaces FOR DELETE
    USING (((select auth.uid()) = admin_id) OR public.is_workspace_admin(id));

-- 3. UNINDEXED FOREIGN KEYS
-- Each FK column gets a plain index; ordering follows delete/join frequency
-- (activity log and comments grow without bound and are the first hit on
-- task deletes).
CREATE INDEX IF NOT EXISTS ix_activity_logs_workspace_id
    ON public.activity_logs (workspace_id);
CREATE INDEX IF NOT EXISTS ix_activity_logs_task_id
    ON public.activity_logs (task_id);
CREATE INDEX IF NOT EXISTS ix_task_comments_workspace_id
    ON public.task_comments (workspace_id);
CREATE INDEX IF NOT EXISTS ix_task_comments_task_id
    ON public.task_comments (task_id);
CREATE INDEX IF NOT EXISTS ix_task_comments_user_id
    ON public.task_comments (user_id);
CREATE INDEX IF NOT EXISTS ix_subtasks_task_id
    ON public.subtasks (task_id);
CREATE INDEX IF NOT EXISTS ix_tasks_workspace_id
    ON public.tasks (workspace_id);
CREATE INDEX IF NOT EXISTS ix_tasks_lane_id
    ON public.tasks (lane_id);
CREATE INDEX IF NOT EXISTS ix_tasks_assignee_id
    ON public.tasks (assignee_id);
CREATE INDEX IF NOT EXISTS ix_tasks_created_by
    ON public.tasks (created_by);
CREATE INDEX IF NOT EXISTS ix_workspace_lanes_workspace_id
    ON public.workspace_lanes (workspace_id);
CREATE INDEX IF NOT EXISTS ix_workspace_members_user_id
    ON public.workspace_members (user_id);
CREATE INDEX IF NOT EXISTS ix_workspaces_admin_id
    ON public.workspaces (admin_id);
