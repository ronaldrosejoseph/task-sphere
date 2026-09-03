-- Per-workspace auto-expiry lane selection.
--
-- Every workspace carries an explicit selection (an empty array = auto-expiry
-- disabled until an admin picks lanes in Settings). New workspaces get the
-- Done / Wont Do lanes they were just seeded with as their default; there is
-- no runtime title fallback for existing rows.
ALTER TABLE public.workspaces
    ADD COLUMN IF NOT EXISTS auto_expiry_lane_ids TEXT[] NOT NULL DEFAULT '{}';

-- New workspaces default their auto-expiry selection to the Done / Wont Do
-- lanes created below. The column already exists (see above), so CREATE OR
-- REPLACE re-runs are safe.
CREATE OR REPLACE FUNCTION public.seed_default_workspace_lanes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.workspace_lanes (workspace_id, title, color_hex, order_index, is_default)
    VALUES
        (NEW.id, 'To Do', '#3B82F6', 0, true),
        (NEW.id, 'In Progress', '#F59E0B', 1, true),
        (NEW.id, 'Partially Done', '#8B5CF6', 2, true),
        (NEW.id, 'Done', '#10B981', 3, true),
        (NEW.id, 'Wont Do', '#EF4444', 4, true);

    UPDATE public.workspaces
    SET auto_expiry_lane_ids = ARRAY(
        SELECT id FROM public.workspace_lanes
        WHERE workspace_id = NEW.id AND lower(title) IN ('done', 'wont do')
    )
    WHERE id = NEW.id;

    -- Also add admin as member
    INSERT INTO public.workspace_members (workspace_id, user_id, email, role)
    SELECT NEW.id, NEW.admin_id, email, 'admin'
    FROM auth.users WHERE id = NEW.admin_id
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
