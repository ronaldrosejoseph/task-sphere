-- Per-workspace auto-expiry lane selection.
--
-- NULL keeps the legacy behavior (Done / Wont Do lanes derived by title);
-- an explicit list (possibly empty = disabled) means the admin configured
-- the selection in Settings. Never auto-set on lane rename: legacy
-- workspaces keep the title fallback until an admin saves the selection.
ALTER TABLE public.workspaces
    ADD COLUMN IF NOT EXISTS auto_expiry_lane_ids TEXT[] DEFAULT NULL;
