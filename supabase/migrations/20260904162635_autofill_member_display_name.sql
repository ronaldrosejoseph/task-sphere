-- Member rows are created at invite time, before the invited user has an
-- auth account, so display_name is unknown until the user's first sign-in.
-- The two existing member-linking triggers now also copy the auth profile
-- name (Google OAuth supplies it in raw_user_meta_data) into display_name,
-- only where it is still NULL so an admin-set name is never overwritten.
--
-- Existing members are intentionally not backfilled (issue #115): their
-- display_name stays NULL and they keep the email-prefix fallback until an
-- admin sets a name.

CREATE OR REPLACE FUNCTION public.fill_member_user_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    found_name TEXT;
BEGIN
    IF NEW.user_id IS NULL THEN
        SELECT id INTO NEW.user_id
        FROM auth.users
        WHERE email = NEW.email;
    END IF;

    IF NEW.display_name IS NULL THEN
        SELECT NULLIF(btrim(COALESCE(
                   raw_user_meta_data->>'name',
                   raw_user_meta_data->>'full_name',
                   '')), '')
        INTO found_name
        FROM auth.users
        WHERE email = NEW.email;
        IF found_name IS NOT NULL THEN
            NEW.display_name := found_name;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.backfill_member_user_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.workspace_members m
    SET user_id = NEW.id,
        display_name = COALESCE(
            m.display_name,
            NULLIF(btrim(COALESCE(
                NEW.raw_user_meta_data->>'name',
                NEW.raw_user_meta_data->>'full_name',
                '')), '')
        )
    WHERE m.email = NEW.email
      AND m.user_id IS NULL;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_member_inserted ON public.workspace_members;
CREATE TRIGGER on_member_inserted
    BEFORE INSERT ON public.workspace_members
    FOR EACH ROW
    EXECUTE FUNCTION public.fill_member_user_id();

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.backfill_member_user_id();
