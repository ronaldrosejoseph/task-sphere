-- The auto-expiry clock must start when a task ENTERED its current lane,
-- not at creation: an old ticket moved into an auto-expiry lane (Done /
-- Wont Do by default, admin-configurable) should age out only after
-- sitting there for auto_archive_days, not instantly.
-- The client stamps lane_entered_at optimistically on lane changes; this
-- trigger makes the server authoritative for any write that changes
-- lane_id. Rows saved before this migration have no stamp and fall back
-- to created_at in the client until they next change lanes.
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS lane_entered_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.set_tasks_lane_entered_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.lane_id IS DISTINCT FROM OLD.lane_id THEN
        NEW.lane_entered_at := now();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_tasks_lane_entered ON public.tasks;
CREATE TRIGGER on_tasks_lane_entered
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.set_tasks_lane_entered_at();
