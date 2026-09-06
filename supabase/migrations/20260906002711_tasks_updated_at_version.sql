-- updated_at becomes a server-authoritative edit version so concurrent
-- ticket edits can be rejected instead of silently overwritten. The client
-- saves carry the version the edit was based on and the repository applies
-- them with `WHERE updated_at = <version>`; this trigger bumps the column
-- on every write, so a stale save matches nothing and is reported as a
-- conflict. (Previously updated_at only had an INSERT default and was
-- never changed on UPDATE.)

CREATE OR REPLACE FUNCTION public.set_tasks_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_tasks_updated ON public.tasks;
CREATE TRIGGER on_tasks_updated
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.set_tasks_updated_at();
