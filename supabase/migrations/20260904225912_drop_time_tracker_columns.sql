-- Time Tracker removal: the stopwatch feature is gone from the app and
-- nothing else reads these columns (the UI never offered an estimate
-- input, and no card/analytics/notification surfaces consume either), so
-- they are dropped. The app no longer sends them, and the SELECT used by
-- the task repository tolerates absent keys.

ALTER TABLE public.tasks
    DROP COLUMN IF EXISTS estimated_hours,
    DROP COLUMN IF EXISTS logged_seconds;
