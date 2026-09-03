ALTER TABLE public.workspace_members
    ADD COLUMN IF NOT EXISTS display_name TEXT;
