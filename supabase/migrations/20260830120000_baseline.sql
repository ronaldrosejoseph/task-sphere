-- Baseline migration: the complete Task Sphere schema (folded from the
-- former supabase/schema.sql). It is idempotent so it can also be applied
-- over the existing production database. New schema changes go in NEW
-- timestamped migration files — never edit this one.
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. WORKSPACES TABLE
CREATE TABLE IF NOT EXISTS public.workspaces (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    admin_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    auto_archive_days INT NOT NULL DEFAULT 14,
    show_archived_tasks BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migration for databases created before this column existed.
ALTER TABLE public.workspaces
    ADD COLUMN IF NOT EXISTS show_archived_tasks BOOLEAN NOT NULL DEFAULT false;

-- 2. WORKSPACE MEMBERS TABLE
CREATE TABLE IF NOT EXISTS public.workspace_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'member')),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(workspace_id, email)
);

-- 3. WORKSPACE LANES (KANBAN COLUMNS)
CREATE TABLE IF NOT EXISTS public.workspace_lanes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    color_hex TEXT NOT NULL DEFAULT '#6366F1',
    order_index INT NOT NULL DEFAULT 0,
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Databases created before this column existed need it added in place.
ALTER TABLE public.workspace_lanes
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- 4. TASKS TABLE
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    lane_id UUID NOT NULL REFERENCES public.workspace_lanes(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    assignee_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    assignee_email TEXT,
    assignee_name TEXT,
    priority TEXT NOT NULL CHECK (priority IN ('urgent', 'high', 'medium', 'low')) DEFAULT 'medium',
    due_date TIMESTAMPTZ,
    estimated_hours DOUBLE PRECISION DEFAULT 0.0,
    logged_seconds INT DEFAULT 0,
    attachment_paths TEXT[] DEFAULT '{}',
    is_archived BOOLEAN NOT NULL DEFAULT false,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Databases created before attachment storage existed (they use
-- drive_attachment_urls) need the column added in place.
ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS attachment_paths TEXT[] DEFAULT '{}';

-- 5. SUBTASKS TABLE (CHECKLIST)
CREATE TABLE IF NOT EXISTS public.subtasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT false,
    order_index INT NOT NULL DEFAULT 0
);

-- 5b. TASK COMMENTS TABLE
CREATE TABLE IF NOT EXISTS public.task_comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    user_name TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Workspace members can view comments" ON public.task_comments;
CREATE POLICY "Workspace members can view comments"
    ON public.task_comments FOR SELECT
    USING (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Workspace members can insert comments" ON public.task_comments;
CREATE POLICY "Workspace members can insert comments"
    ON public.task_comments FOR INSERT
    WITH CHECK (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Users can delete their own comments" ON public.task_comments;
CREATE POLICY "Users can delete their own comments"
    ON public.task_comments FOR DELETE
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can delete any comment" ON public.task_comments;
CREATE POLICY "Admins can delete any comment"
    ON public.task_comments FOR DELETE
    USING (public.is_workspace_admin(workspace_id));

-- 6. ACTIVITY LOGS TABLE
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
    user_name TEXT NOT NULL,
    action TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- AUTOMATIC DEFAULT LANES SEEDING TRIGGER
CREATE OR REPLACE FUNCTION seed_default_workspace_lanes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.workspace_lanes (workspace_id, title, color_hex, order_index, is_default)
    VALUES 
        (NEW.id, 'To Do', '#3B82F6', 0, true),
        (NEW.id, 'In Progress', '#F59E0B', 1, true),
        (NEW.id, 'Partially Done', '#8B5CF6', 2, true),
        (NEW.id, 'Done', '#10B981', 3, true),
        (NEW.id, 'Wont Do', '#EF4444', 4, true);

    -- Also add admin as member
    INSERT INTO public.workspace_members (workspace_id, user_id, email, role)
    SELECT NEW.id, NEW.admin_id, email, 'admin'
    FROM auth.users WHERE id = NEW.admin_id
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_workspace_created ON public.workspaces;
CREATE TRIGGER on_workspace_created
    AFTER INSERT ON public.workspaces
    FOR EACH ROW
    EXECUTE FUNCTION seed_default_workspace_lanes();

-- ROW LEVEL SECURITY (RLS) POLICIES
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_lanes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subtasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER helpers used by the policies below. They read
-- workspace_members with the function owner's privileges, which bypasses RLS,
-- so policies never recurse into the members table (Postgres error 42P17).
CREATE OR REPLACE FUNCTION public.is_workspace_member(ws_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.workspace_members
        WHERE workspace_id = ws_id
          AND (user_id = auth.uid() OR email = auth.email())
    );
$$;

CREATE OR REPLACE FUNCTION public.is_workspace_admin(ws_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.workspace_members
        WHERE workspace_id = ws_id
          AND role = 'admin'
          AND (user_id = auth.uid() OR email = auth.email())
    );
$$;

-- Link invited members to auth.users so user_id is populated even though
-- invites are recorded by email. Invites sent before the user's first
-- sign-in are backfilled by on_auth_user_created.
CREATE OR REPLACE FUNCTION public.fill_member_user_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        SELECT id INTO NEW.user_id
        FROM auth.users
        WHERE email = NEW.email;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_member_inserted ON public.workspace_members;
CREATE TRIGGER on_member_inserted
    BEFORE INSERT ON public.workspace_members
    FOR EACH ROW
    EXECUTE FUNCTION public.fill_member_user_id();

CREATE OR REPLACE FUNCTION public.backfill_member_user_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.workspace_members
    SET user_id = NEW.id
    WHERE email = NEW.email
      AND user_id IS NULL;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.backfill_member_user_id();

-- Link any members invited before their first sign-in (idempotent).
UPDATE public.workspace_members m
SET user_id = u.id
FROM auth.users u
WHERE m.email = u.email AND m.user_id IS NULL;

CREATE OR REPLACE FUNCTION public.is_any_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.workspace_members
        WHERE user_id = auth.uid() AND role = 'admin'
    );
$$;

-- Allow members to view workspaces they belong to
DROP POLICY IF EXISTS "Users can view workspaces they belong to" ON public.workspaces;
CREATE POLICY "Users can view workspaces they belong to"
    ON public.workspaces FOR SELECT
    USING (auth.uid() = admin_id OR public.is_workspace_member(id));

DROP POLICY IF EXISTS "Admins can update workspace settings" ON public.workspaces;
CREATE POLICY "Admins can update workspace settings"
    ON public.workspaces FOR UPDATE
    USING (auth.uid() = admin_id OR public.is_workspace_admin(id));

DROP POLICY IF EXISTS "Authenticated users can create workspaces" ON public.workspaces;
CREATE POLICY "Authenticated users can create workspaces"
    ON public.workspaces FOR INSERT
    WITH CHECK (auth.uid() = admin_id);

DROP POLICY IF EXISTS "Admins can delete workspaces" ON public.workspaces;
CREATE POLICY "Admins can delete workspaces"
    ON public.workspaces FOR DELETE
    USING (auth.uid() = admin_id OR public.is_workspace_admin(id));

-- Tasks Policies
DROP POLICY IF EXISTS "Workspace members can view tasks" ON public.tasks;
CREATE POLICY "Workspace members can view tasks"
    ON public.tasks FOR SELECT
    USING (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Workspace members can insert/update tasks" ON public.tasks;
CREATE POLICY "Workspace members can insert/update tasks"
    ON public.tasks FOR ALL
    USING (public.is_workspace_member(workspace_id))
    WITH CHECK (public.is_workspace_member(workspace_id));

-- Lane Policies
DROP POLICY IF EXISTS "Workspace members can view lanes" ON public.workspace_lanes;
CREATE POLICY "Workspace members can view lanes"
    ON public.workspace_lanes FOR SELECT
    USING (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Workspace admins can modify lanes" ON public.workspace_lanes;
CREATE POLICY "Workspace admins can modify lanes"
    ON public.workspace_lanes FOR ALL
    USING (public.is_workspace_admin(workspace_id))
    WITH CHECK (public.is_workspace_admin(workspace_id));

-- Member Policies (must not query workspace_members directly or they recurse)
DROP POLICY IF EXISTS "Workspace members can view members" ON public.workspace_members;
CREATE POLICY "Workspace members can view members"
    ON public.workspace_members FOR SELECT
    USING (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Workspace admins can modify members" ON public.workspace_members;
CREATE POLICY "Workspace admins can modify members"
    ON public.workspace_members FOR ALL
    USING (public.is_workspace_admin(workspace_id))
    WITH CHECK (public.is_workspace_admin(workspace_id));

-- Subtask Policies
DROP POLICY IF EXISTS "Workspace members can view subtasks" ON public.subtasks;
CREATE POLICY "Workspace members can view subtasks"
    ON public.subtasks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.tasks t
            WHERE t.id = subtasks.task_id
              AND public.is_workspace_member(t.workspace_id)
        )
    );

DROP POLICY IF EXISTS "Workspace members can modify subtasks" ON public.subtasks;
CREATE POLICY "Workspace members can modify subtasks"
    ON public.subtasks FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.tasks t
            WHERE t.id = subtasks.task_id
              AND public.is_workspace_member(t.workspace_id)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.tasks t
            WHERE t.id = subtasks.task_id
              AND public.is_workspace_member(t.workspace_id)
        )
    );

-- Activity Log Policies
DROP POLICY IF EXISTS "Workspace members can view activity logs" ON public.activity_logs;
CREATE POLICY "Workspace members can view activity logs"
    ON public.activity_logs FOR SELECT
    USING (public.is_workspace_member(workspace_id));

DROP POLICY IF EXISTS "Workspace members can insert activity logs" ON public.activity_logs;
CREATE POLICY "Workspace members can insert activity logs"
    ON public.activity_logs FOR INSERT
    WITH CHECK (public.is_workspace_member(workspace_id));

-- TASK ATTACHMENT STORAGE
-- Private bucket for task attachments. Files live at
-- {workspace_id}/{task_id}/{timestamp}_{filename} and access is governed by
-- the storage.objects policies below.
INSERT INTO storage.buckets (id, name, public)
VALUES ('task-attachments', 'task-attachments', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Workspace members can upload attachments" ON storage.objects;
CREATE POLICY "Workspace members can upload attachments"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'task-attachments'
        AND public.is_workspace_member((storage.foldername(name))[1]::uuid)
    );

DROP POLICY IF EXISTS "Workspace members can read attachments" ON storage.objects;
CREATE POLICY "Workspace members can read attachments"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'task-attachments'
        AND public.is_workspace_member((storage.foldername(name))[1]::uuid)
    );

DROP POLICY IF EXISTS "Workspace members can delete attachments" ON storage.objects;
CREATE POLICY "Workspace members can delete attachments"
    ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'task-attachments'
        AND public.is_workspace_member((storage.foldername(name))[1]::uuid)
    );

-- SIGN-UP RESTRICTION
-- New users (including Google OAuth sign-ins) are rejected unless their
-- email is allowlisted. Admins manage the list from the SQL editor:
--   INSERT INTO public.allowed_signup_emails (email) VALUES ('you@example.com');
CREATE TABLE IF NOT EXISTS public.allowed_signup_emails (
    email TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.allowed_signup_emails ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can manage the signup allowlist" ON public.allowed_signup_emails;
CREATE POLICY "Admins can manage the signup allowlist"
    ON public.allowed_signup_emails FOR ALL
    USING (public.is_any_admin())
    WITH CHECK (public.is_any_admin());

CREATE OR REPLACE FUNCTION public.restrict_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.email IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.allowed_signup_emails WHERE lower(email) = lower(NEW.email)
    ) THEN
        RAISE EXCEPTION 'Sign-up is restricted. Ask a workspace admin to add your email to the allowlist.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    BEFORE INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.restrict_signup();

-- ENABLE SUPABASE REALTIME (idempotent so the script can be re-run)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'tasks') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'workspace_lanes') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.workspace_lanes;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'activity_logs') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.activity_logs;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'subtasks') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.subtasks;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'task_comments') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.task_comments;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'workspace_members') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.workspace_members;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'workspaces') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.workspaces;
    END IF;
END $$;
