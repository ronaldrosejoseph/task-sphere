# Task Sphere

Flutter Kanban task-management app (Android / iOS / macOS / Web) with Supabase
(database, auth, realtime, storage) and Cloudflare Pages hosting. Private repo:
`github.com/ronaldrosejoseph/task-sphere`, branch `main` = production.

## Development workflow (follow every change)

1. **One GitHub issue per change** (project board "Task Sphere", project 3).
   Add the issue to the board and track its status:
   - `gh project item-add 3 --owner ronaldrosejoseph --url <issue-url>`
   - `gh project item-edit 3 --owner ronaldrosejoseph --url <issue-url> --field-id PVTSSF_lAHOAe2eAM4BhxDHzhgrlzc --single-select-option-id 98236657` (Done)
2. **Branch per ticket, merge via PR** — never push to `main` directly:
   - `git checkout -b <short-ticket-name>`
   - commit with `Closes #N` in the message
   - push, open a PR, merge to `main`
3. **Before every commit**: `flutter analyze` (must be clean) and the full
   `flutter test` suite (must pass). Write tests alongside the code.
4. **Commit messages**: change summary + `Closes #N` only. NEVER add a
   `Co-Authored-By: Claude ...` trailer.

## Environment

- Flutter SDK: `/Users/ronaldjoseph/dev/flutter/bin/flutter` (NOT on PATH).
- Git pushes use HTTPS with gh's credential helper — **no SSH key is
  configured**; do not switch the remote to SSH. Run `gh auth setup-git` if
  pushes start failing.
- GitHub account: `ronaldrosejoseph`.

## Schema changes (critical)

The database schema lives in `supabase/migrations/<timestamp>_<name>.sql` —
timestamped migration files applied **in order** by `supabase db push`.

- **Never edit an applied migration.** Create a new file for every schema
  change: `cp supabase/migrations/$(date -u +%Y%m%d%H%M%S)_describe_change.sql`
  and write only the diff. Make statements idempotent
  (`CREATE ... IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`,
  `DROP ... IF EXISTS`) so re-runs are safe.
- Merging to `main` **auto-applies pending migrations** to the production
  database via `.github/workflows/production.yml` (`supabase db push`). No
  manual SQL-editor hand-offs.
- Test locally first when possible: `supabase start` (local stack) →
  `supabase migration up` → verify → `supabase stop`.
- The project ref is a **secret, never committed**: the migration workflow
  injects it at deploy time via `supabase link --project-ref
  $SUPABASE_PROJECT_ID` (secret), which writes it into `supabase/config.toml`
  on the CI runner only. For local CLI work, run `supabase link
  --project-ref <ref>` yourself — it writes the ref into `config.toml` on
  your machine, and you can revert that file before committing.
- The old `supabase/schema.sql` was folded into the baseline migration
  (`20260830120000_baseline.sql`) and must not be recreated as a source of
  truth.

## Deploy pipeline

Everything deploys automatically on merge to `main`:

- **Web**: `.github/workflows/deploy.yml` — `flutter build web --release` with
  `--dart-define=DEMO_MODE=true --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`, then `wrangler pages deploy` to Cloudflare Pages.
- **Database**: `.github/workflows/production.yml` — `supabase link` +
  `supabase db push` against the production project.
- **CI**: `.github/workflows/ci.yml` — analyze + tests on pushes to `main` and
  every PR.

Required repository secrets (Settings → Secrets and variables → Actions):
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`,
`SUPABASE_PROJECT_ID`.

## App architecture notes

- Riverpod 3 notifiers; repositories (`lib/core/repositories/`) abstract
  persistence. The demo/offline sandbox (user id `demo-user-123`, driven by
  `isDemoUserProvider`) uses in-memory repositories and blocks
  creations/invites; real sign-ins use Supabase.
- Permissions: app-side `isAdmin` matches by member user id OR email; the
  database mirrors this with `is_workspace_admin`/`is_workspace_member`
  SECURITY DEFINER functions and RLS. Members can edit title/description only
  on tickets they created (`created_by`); only admins delete tickets.
- Tests live in `test/`, mirroring `lib/` — provider tests use fake
  repositories; view tests use widget tests.

## Demo mode

Built with `--dart-define=DEMO_MODE=true` for the web deploy; without
Supabase credentials the app falls back to offline/demo mode automatically.
