-- Task Sphere Supabase Schema & Realtime Setup
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. WORKSPACES TABLE
CREATE TABLE IF NOT EXISTS public.workspaces (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    admin_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    auto_archive_days INT NOT NULL DEFAULT 14,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

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
    drive_attachment_urls TEXT[] DEFAULT '{}',
    is_archived BOOLEAN NOT NULL DEFAULT false,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. SUBTASKS TABLE (CHECKLIST)
CREATE TABLE IF NOT EXISTS public.subtasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT false,
    order_index INT NOT NULL DEFAULT 0
);

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

-- Allow members to view workspaces they belong to
CREATE POLICY "Users can view workspaces they belong to"
    ON public.workspaces FOR SELECT
    USING (
        auth.uid() = admin_id OR 
        EXISTS (
            SELECT 1 FROM public.workspace_members 
            WHERE workspace_id = workspaces.id AND (user_id = auth.uid() OR email = auth.email())
        )
    );

CREATE POLICY "Admins can update workspace settings"
    ON public.workspaces FOR UPDATE
    USING (auth.uid() = admin_id);

CREATE POLICY "Authenticated users can create workspaces"
    ON public.workspaces FOR INSERT
    WITH CHECK (auth.uid() = admin_id);

-- Tasks Policies
CREATE POLICY "Workspace members can view tasks"
    ON public.tasks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.workspace_members 
            WHERE workspace_id = tasks.workspace_id AND (user_id = auth.uid() OR email = auth.email())
        )
    );

CREATE POLICY "Workspace members can insert/update tasks"
    ON public.tasks FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.workspace_members
            WHERE workspace_id = tasks.workspace_id AND (user_id = auth.uid() OR email = auth.email())
        )
    );

-- Lane Policies
CREATE POLICY "Workspace members can view lanes"
    ON public.workspace_lanes FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.workspace_members
            WHERE workspace_id = workspace_lanes.workspace_id AND (user_id = auth.uid() OR email = auth.email())
        )
    );

CREATE POLICY "Workspace admins can modify lanes"
    ON public.workspace_lanes FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.workspace_members
            WHERE workspace_id = workspace_lanes.workspace_id AND user_id = auth.uid() AND role = 'admin'
        )
    );

-- Member Policies
CREATE POLICY "Workspace members can view members"
    ON public.workspace_members FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.workspace_members self
            WHERE self.workspace_id = workspace_members.workspace_id AND (self.user_id = auth.uid() OR self.email = auth.email())
        )
    );

CREATE POLICY "Workspace admins can modify members"
    ON public.workspace_members FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.workspace_members adm
            WHERE adm.workspace_id = workspace_members.workspace_id AND adm.user_id = auth.uid() AND adm.role = 'admin'
        )
    );

-- Subtask Policies
CREATE POLICY "Workspace members can view subtasks"
    ON public.subtasks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.tasks t
            JOIN public.workspace_members wm ON wm.workspace_id = t.workspace_id
            WHERE t.id = subtasks.task_id AND (wm.user_id = auth.uid() OR wm.email = auth.email())
        )
    );

CREATE POLICY "Workspace members can modify subtasks"
    ON public.subtasks FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.tasks t
            JOIN public.workspace_members wm ON wm.workspace_id = t.workspace_id
            WHERE t.id = subtasks.task_id AND (wm.user_id = auth.uid() OR wm.email = auth.email())
        )
    );

-- Activity Log Policies
CREATE POLICY "Workspace members can view activity logs"
    ON public.activity_logs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.workspace_members
            WHERE workspace_id = activity_logs.workspace_id AND (user_id = auth.uid() OR email = auth.email())
        )
    );

CREATE POLICY "Workspace members can insert activity logs"
    ON public.activity_logs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.workspace_members
            WHERE workspace_id = activity_logs.workspace_id AND (user_id = auth.uid() OR email = auth.email())
        )
    );

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
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'workspace_members') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.workspace_members;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'workspaces') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.workspaces;
    END IF;
END $$;
