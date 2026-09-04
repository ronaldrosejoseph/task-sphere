-- The name columns on task_comments and activity_logs snapshot the actor's
-- display label at write time (member alias -> account name), not the raw
-- auth user name, so they are renamed to display_name to match the member
-- concept and what the app actually stores.
--
-- The value remains a write-time snapshot on purpose: members.display_name is
-- live configuration, and renaming a member must not rewrite comment/log
-- history (the snapshot also survives member removal). No data is moved; the
-- existing values stay in place under the new name.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'task_comments'
          AND column_name = 'user_name'
    ) THEN
        ALTER TABLE public.task_comments
            RENAME COLUMN user_name TO display_name;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'activity_logs'
          AND column_name = 'user_name'
    ) THEN
        ALTER TABLE public.activity_logs
            RENAME COLUMN user_name TO display_name;
    END IF;
END $$;
