# Task Sphere

Flutter Kanban task-management app (Android / iOS / macOS / Web) with Supabase
(database, auth, realtime, storage) and Cloudflare Pages hosting. **Public**
repo: `github.com/ronaldrosejoseph/task-sphere`, branch `main` = production.
Everything committed here is world-visible — never add credentials, secrets,
project identifiers, or personal machine details.

## Development workflow (follow every change)

1. **One GitHub issue per change** (project board "Task Sphere", project 3 —
   private). Add the issue to the board and track its status:
   - `gh project item-add 3 --owner ronaldrosejoseph --url <issue-url>`
   - `gh project item-edit 3 --owner ronaldrosejoseph --url <issue-url>`
     with the status field/option ids for "Done" from the maintainer's local
     notes (not in this public file)
2. **Branch per ticket, merge via PR** — never push to `main` directly:
   - `git checkout -b <short-ticket-name>`
   - commit with `Closes #N` in the message
   - push, open a PR, merge to `main`
3. **Before every commit**: `flutter analyze` (must be clean) and the full
   `flutter test` suite (must pass). Write tests alongside the code.
4. **Commit messages**: change summary + `Closes #N` only. NEVER add a
   `Co-Authored-By: Claude ...` trailer.

## Environment

- The Flutter SDK is NOT on PATH; invoke it via its full path (kept in the
  maintainer's local tooling notes, not in this public file).
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
  derives it from the `SUPABASE_URL` secret at deploy time so nothing
  identifying the project lives in the repo (it stays safe to make
  public). For local CLI work, run `supabase link --project-ref <ref>`
  yourself — it writes the ref into `config.toml` on your machine, and you
  can revert that file before committing.
- The old `supabase/schema.sql` was folded into the baseline migration
  (`20260830120000_baseline.sql`) and must not be recreated as a source of
  truth.

## Deploy pipeline
 
Everything deploys automatically on merge to `main`:
 
- **Production Deployment**: `.github/workflows/production.yml` — coordinated pipeline with concurrency locking:
  1. Runs database migrations (`supabase db push`) with dynamic IPv4/IPv6 JIT allowlisting and cleanup.
  2. Builds and deploys the web bundle to Cloudflare Pages (`wrangler pages deploy`) only after migrations succeed.
- **CI**: `.github/workflows/ci.yml` — analyze + tests on pushes to `main` and
  every PR.

Required repository secrets (Settings → Secrets and variables → Actions):
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_URL`
(connection string with password). No project ID is stored anywhere in the
repo; the only IPs ever allowlisted are the runner's own, briefly, per
deploy.

## App architecture notes

- Riverpod 3 notifiers; repositories (`lib/core/repositories/`) abstract
  persistence. The demo/offline sandbox (user id `demo-user-123`, driven by
  `isDemoUserProvider`) uses in-memory repositories and blocks
  creations/invites; real sign-ins use Supabase.
- Permissions: app-side `isAdmin` matches by member user id OR email; the
  database mirrors this with `is_workspace_admin`/`is_workspace_member`
  SECURITY DEFINER functions and RLS. Members can edit title/description only
  on tickets they created (`created_by`); only admins delete tickets. The
  signup allowlist's `is_site_admin` flag is the only role allowed to create
  or delete workspaces, and the database blocks removing the site admin from
  a workspace's member list (`protect_site_admin_membership` trigger).
- Removing a member reaches their device through `member_kicks` notification
  rows written by a trigger: the membership DELETE itself is invisible to the
  removed user under RLS, so realtime alone can never deliver it.
- Ticket edits use optimistic concurrency: rows carry a server-stamped
  `updated_at` version (`set_tasks_updated_at` trigger), and a save that lost
  the race is discarded and surfaced as a conflict notice instead of silently
  overwriting another device's change.
- Tests live in `test/`, mirroring `lib/` — provider tests use fake
  repositories; view tests use widget tests.

## Demo mode

Built with `--dart-define=DEMO_MODE=true` for the web deploy; without
Supabase credentials the app falls back to offline/demo mode automatically.
