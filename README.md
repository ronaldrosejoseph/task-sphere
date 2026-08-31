# Task Sphere 🚀
> **Cross-Platform Serverless Kanban Task Management App** built with **Flutter** and **Supabase** (database, auth, realtime, storage).

Task Sphere is a modern, high-performance task management application for mobile (Android & iOS), desktop (macOS), and Web. It features role-based workspace management, custom drag-and-drop Kanban lanes, auto-expiry task archiving, local due-date notifications, and secure file attachments via Supabase Storage with **zero local server required**.

---

## 🌟 Key Features

- 📌 **Customizable Kanban Board**: Default lanes (`To Do`, `In Progress`, `Partially Done`, `Done`, `Wont Do`) + Admin custom lane creator, color customizer, and column reordering.
- 🗄️ **Smart Auto-Expiry & Archiving**: Automatically hide old completed tasks from active view after a configurable duration (7, 14, 30 days or Never) with a dedicated search/restore Archive view.
- 👥 **Workspaces & Role-Based Access (RBAC)**: Create multi-user workspaces with **Admin** (lane control, task assignment, member management) and **Member** permissions.
- 📊 **Analytics Dashboard**: Interactive visual charts (`fl_chart`) tracking velocity, lane distribution, member workload, and logged work hours.
- 📁 **Serverless Supabase Storage Attachments**: Private, RLS-protected bucket with signed URLs - files are shared with the workspace, not a single user.
- 🔔 **Local Notifications**: Scheduled due date reminders (mobile & desktop).
- 🌙 **Modern Glassmorphic UI**: Sleek dark/light modes, micro-animations (`flutter_animate`), responsive desktop sidebar & mobile navigation bar.

---

## 🛠️ Step-by-Step Backend Setup

### 1. Supabase Project Setup (Database, Auth, Storage & Realtime)

1. Go to [Supabase](https://supabase.com) and create a free account.
2. Click **New Project** and name your project `task-sphere`.
3. Apply the schema. The database schema is managed as **migrations** in
   [`supabase/migrations/`](supabase/migrations/). Two options:
   - **Recommended (automatic):** the GitHub Actions workflow
     `.github/workflows/production.yml` runs `supabase db push` on every merge
     to `main`, so new migrations deploy themselves. Configure the
     [Supabase "Deploy to production"](https://supabase.com/docs/guides/deployment/database-push)
     integration with `main` as the production branch, then follow the
     **"Automatic database deployments — one-time setup"** steps below.
   - **One-off setup:** open the **SQL Editor** and run the baseline
     migration `supabase/migrations/20260830120000_baseline.sql` (idempotent,
     safe to re-run).
   - This creates all necessary tables (`workspaces`, `workspace_lanes`, `workspace_members`, `tasks`, `subtasks`, `task_comments`, `activity_logs`, `allowed_signup_emails`).
   - Configures Row Level Security (RLS) policies for workspace privacy.
   - Creates the private `task-attachments` storage bucket with member-scoped upload/read/delete policies.
   - Sets up default lane initialization triggers and enables Realtime WebSockets on the workspace tables.
   - **Restricts sign-ups to an email allowlist** (see Security below). The baseline is idempotent - it is safe to re-run.
5. **Allowlist your own email** (before signing up!) and make it the **site
   admin** — the one account that is never revoked when a workspace is
   deleted and can always create workspaces — in the SQL editor (run once,
   after the migrations have been applied):
   ```sql
   INSERT INTO public.allowed_signup_emails (email, is_site_admin)
   VALUES ('you@example.com', true)
   ON CONFLICT (email) DO UPDATE SET is_site_admin = true;
   ```
   The flag can only be changed from the SQL editor (the app blocks it), and
   deleting a workspace never removes the site admin from the allowlist.
6. Enable the **Google provider** (required for sign-in on every platform):
   - Go to **Authentication -> Providers -> Google**.
   - Toggle **Enable Sign in with Google**.
   - Paste the **Client ID** and **Client Secret** from the Google OAuth Web client you will create in the next section, then **Save**.
7. Go to **Project Settings -> API** in Supabase and copy your:
   - `Project URL` (e.g., `https://xyzcompany.supabase.co`)
   - `anon public key` (e.g., `eyJhbGciOi...`)

### Automatic database deployments — one-time setup (recommended)

Every time you merge code into `main`, GitHub automatically applies any database
changes (migrations) to your Supabase project — you never need to paste SQL
again. This needs **two secrets** set once (about 5 minutes). If you skip this,
database changes must be applied by hand in the SQL editor instead.

How it works: your project's network restriction stays **on**. The deploy
workflow temporarily adds the GitHub runner's own IP to the allowlist via the
Supabase Management API, applies the migrations over a direct connection, and
then removes the IP again — even if the migrations fail.

**Step 1 — Create a Supabase access token**

1. In the Supabase dashboard, click your **account avatar** (top-left corner) → **Account settings**.
2. Click **Access Tokens** → **Generate new token**.
3. Name it `GitHub Actions` and click **Generate**.
4. **Copy the token right away** (it starts with `sbp_...`) — it is only shown once. If you lose it, generate a new one.

**Step 2 — Add the secrets to GitHub**

1. Go to your repository: `https://github.com/ronaldrosejoseph/task-sphere` → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
2. Add these two secrets:

| Secret name | Value to enter |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | the token from Step 1 (starts with `sbp_...`) |
| `SUPABASE_DB_URL` | your database connection string (below) |

To get the connection string — **How to get the Free IPv4 Connection String
in the Supabase Dashboard**:

1. Open your supabase project.
2. Click **Connect** in the header.
3. Click **Direct Connection Strings** tab.
4. Scroll down to the **Connection string** and copy it. It looks like this:
   ```
   postgresql://postgres.<project-ref>:[YOUR-PASSWORD]@aws-0-<region>.pooler.supabase.com:5432/postgres
   ```
5. Replace `[YOUR-PASSWORD]` with your real database password (the one from
   project creation — forgotten it? **Project Settings → Database → Reset
   database password**). If the password contains special characters (`@`, `:`,
   `/`, `#`, `?`), they must be URL-encoded (e.g. `@` becomes `%40`); the
   easiest path is a password with only letters and numbers.

Your project ID is **not** needed as a secret — the deploy derives it
automatically from the `SUPABASE_URL` secret you already have, so nothing
identifying your project is ever stored in the repo.

**Step 3 — Make sure only one database-deploy workflow exists**

If you configured Supabase's "Deploy to production" integration from the dashboard, it may have added its own workflow file to the repo. Pull the latest code and check the `.github/workflows/` folder:

- Keep `.github/workflows/production.yml` (the one this README documents).
- If you also see a file named `production.yaml` (note the `.yaml` ending), delete it and commit the deletion, so the database is never deployed twice.

**Done!** The next time you merge to `main`, the repo's **Actions** tab will show a job named **Deploy Migrations to Production** — it turns green when your database changes have been applied.

**Troubleshooting**

1. The **Temporarily authorize the runner's IP** step fails with `error code: 1010` → Cloudflare blocked the HTTP client (this used to happen with Python's `urllib`; the workflow now uses `curl`, which is not blocked). If it recurs, the `SUPABASE_ACCESS_TOKEN` or `SUPABASE_URL` secret may be misconfigured. Verify the token from your machine (replace `<TOKEN>` and `<YOUR-REF>`; the ref is the code before `.supabase.co` in your Project URL):
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer <TOKEN>" https://api.supabase.com/v1/projects/<YOUR-REF>/network-restrictions
   ```
   - `200` → the token is fine; re-run the workflow.
   - `401`/`403` → the token value is wrong or belongs to another account. Generate a fresh token (account avatar → **Account settings** → **Access Tokens**) and update the `SUPABASE_ACCESS_TOKEN` secret.
2. If the authorize step succeeded but the connection still failed, simply **re-run the workflow** — the next runner gets a fresh IP and a fresh authorization.
3. The last step, **Remove the runner's IP access**, always runs; if it ever fails, the runner's IP stays on the allowlist — remove it manually under Supabase → **Project Settings** → **Database** → **Network Restrictions**.

---

### 2. Google OAuth Sign-In Setup (no Drive, no verification needed)

Only basic sign-in scopes (`email`, `profile`, `openid`) are used - no sensitive scopes, so **Google app verification is not required** and users never see an "unverified app" warning.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project named `Task Sphere`.
3. Configure the **OAuth Consent Screen**:
   - Go to **APIs & Services -> OAuth consent screen**.
   - Select **User Type: External** and click **Create**.
   - Add app name: `Task Sphere`.
   - The email/profile/openid scopes are requested automatically by the sign-in flow.
4. Create **OAuth 2.0 Credentials**:
   - Go to **APIs & Services -> Credentials -> Create Credentials -> OAuth client ID**.
   - **Web Client**: copy its **Client ID** and **Client Secret** into the Supabase Google provider (previous section). Then, under **Authorized redirect URIs**, add the Supabase OAuth callback URL — `https://<your-project-ref>.supabase.co/auth/v1/callback` (no trailing slash, `<your-project-ref>` from Project Settings → API → Project URL). Without this, web sign-in fails with `Error 400: redirect_uri_mismatch`. Authorized JavaScript origins can stay empty.
   - **Android Client**: Add your package name (`com.tasksphere.app.task_sphere`) and the SHA-1 fingerprint of the keystore that signs the app — find it with `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` (the debug keystore signs the current builds).
   - **iOS Client**: Add Bundle ID (`com.tasksphere.app.taskSphere`).
   - **macOS Client**: Add Bundle ID (`com.tasksphere.app.taskSphere`).

---

## 🚀 Running the App

### Environment Configuration
Provide your Supabase URL & Anon Key when launching or building the app:

```bash
# Web
flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY

# macOS Desktop
flutter run -d macos --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY

# Android / iOS (mobile sign-in also needs the Google client IDs from the
# OAuth clients created in the Google OAuth Sign-In Setup section below)
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GOOGLE_CLIENT_ID=YOUR_ANDROID_OR_IOS_CLIENT_ID \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

> **Google client IDs for mobile builds**: `GOOGLE_CLIENT_ID` is the platform
> OAuth client ID (the Android or iOS client you created) and
> `GOOGLE_SERVER_CLIENT_ID` is the **Web** OAuth client ID. Without them,
> tapping "Sign in with Google" on a phone fails (the app shows an error
> instead of signing in). Building an APK:
> `flutter build apk --release --dart-define=...` with the same four defines.

> **Demo / Local Offline Mode**: If no Supabase credentials are input, Task Sphere automatically falls back to local in-memory/mock storage so you can immediately evaluate the app offline! (Attachments are disabled in offline mode.)

---

## 🌐 Deploying the Web App (Cloudflare Pages)

The web build is a fully static Flutter bundle - no server required. A coordinated GitHub Actions workflow (`.github/workflows/production.yml`) applies any pending database migrations first and then builds and deploys the web app to Cloudflare Pages on every push to `main`.

### One-time setup

1. **Create a Cloudflare account** at [dash.cloudflare.com](https://dash.cloudflare.com) (free plan is fine) and verify your email.
2. **Create an API token**: Dashboard → avatar → **My Profile** → **API Tokens** → **Create Token** → **Create Custom Token**. Name it `task-sphere-pages` and add the permission **Account → Cloudflare Pages → Edit**. Finish and **copy the token immediately** — it is only shown once.
3. **Find your Account ID**: Cloudflare Dashboard home page → **right sidebar** → **Account ID** (a 32-character hex string).
4. **Add GitHub Actions secrets** (Repo → Settings → Secrets and variables → Actions):
   - `SUPABASE_URL` - your Supabase project URL (Supabase → Project Settings → API)
   - `SUPABASE_ANON_KEY` - your Supabase **anon** public key (never the `service_role` key) from the same page
   - `CLOUDFLARE_API_TOKEN` - the API token from step 2
   - `CLOUDFLARE_ACCOUNT_ID` - the Account ID from step 3
5. **Push to `main`** (or run the **Deploy Web** workflow manually from the Actions tab) - the workflow runs tests, builds the bundle, creates the Pages project named `task-sphere` if it does not exist, and deploys to it.
6. Your app is live at **`https://task-sphere.pages.dev`** (attach a custom domain under Cloudflare Pages → Custom domains if you own one).

### Required cloud configuration for web sign-in

- **Supabase Auth**: set the **Site URL** to your deployed URL (`https://task-sphere.pages.dev`) under Supabase → Authentication → URL Configuration, so the Google OAuth redirect flow returns to your app. Also add `https://task-sphere.pages.dev/**` to **Redirect URLs**.
- **Google Cloud console**: the Supabase OAuth callback URL must be registered as an **Authorized redirect URI** on the Web OAuth client (see the Google OAuth Sign-In Setup section above) or web sign-in fails with `Error 400: redirect_uri_mismatch`.

### Manual deploy (optional)

```bash
flutter build web --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
npx wrangler pages deploy build/web --project-name task-sphere
```

> **Note**: local due-date notifications are not available in browsers; the app degrades gracefully on web.

---

## 🔐 Security

### How the app is protected

- **Row Level Security everywhere**: every table (workspaces, lanes, members, tasks, subtasks, activity logs) has RLS policies scoped to workspace membership - a signed-in user can only read/write data in workspaces they belong to. Lane/member modifications require the admin role.
- **Private attachment bucket**: files live in a private `task-attachments` bucket; storage RLS policies let only workspace members upload, read (via short-lived signed URLs), and delete files. File paths are scoped `{workspace_id}/{task_id}/{file}`.
- **Sign-up allowlist**: new sign-ins (including Google OAuth) are rejected by a database trigger unless the email is in `allowed_signup_emails`. Inviting a member from the app adds their email to the allowlist automatically; admins can also manage the list from the SQL editor:
  ```sql
  INSERT INTO public.allowed_signup_emails (email) VALUES ('new.member@example.com');
  ```
  Note: the allowlist only gates the *first* sign-in. Removing an email later does not revoke an existing account - remove the member from the workspace instead. Any workspace admin can allowlist emails, so grant the admin role carefully.
- **Workspace deletion revokes members**: deleting a workspace removes its members from the allowlist (unless they are the site admin or still belong to another workspace), and the app blocks their sign-in with an access message. The site admin can always create workspaces; plain (non-admin) members can never create new workspaces.
- **Web sign-in** uses Supabase's PKCE OAuth redirect; mobile uses the Google idToken flow. Sessions are Supabase JWTs validated server-side.

### Rules to keep it secure

1. **Never put the `service_role` key in the app.** It bypasses RLS entirely. The app uses the `anon` key only - it is public by design, and RLS is the security boundary.
2. **Enable CAPTCHA** (recommended): Supabase → Authentication → Providers → add Turnstile or hCaptcha keys to protect the auth endpoint from bots.
3. **Optional: Cloudflare Access** - put the whole Pages site behind a Zero Trust email allowlist so only your team can load the page at all (free for up to 50 users).
4. The schema script is idempotent; re-run it after upgrading to pick up new policies.

---

## 🧪 Development & CI

```bash
flutter pub get
flutter analyze          # zero issues enforced by CI
flutter test             # 91 unit + widget tests
```

- **CI** (`.github/workflows/ci.yml`) runs `flutter analyze` and `flutter test` on every push and pull request.
- **Deploy** (`.github/workflows/production.yml`) runs migrations against Supabase and deploys the web app to Cloudflare Pages on every push to `main`.
- **Testing conventions**: model tests live in `test/models/`, provider/state tests in `test/providers/` (with fake repositories for the Supabase layer), and widget tests in `test/views/`.

---

## 🏗️ Project Architecture

```
lib/
├── main.dart                  # App initialization, Supabase setup & Theme provider
├── core/
│   ├── theme/                 # Modern theme design system, glassmorphism card styles
│   ├── repositories/          # Supabase + in-memory persistence for workspaces, tasks, logs
│   └── services/              # Supabase, Storage, Google Auth & Local Notification services
├── models/                    # Workspace, Lane, Task, Subtask, Activity Log models
├── providers/                 # Riverpod Auth, Workspace, Task, and Theme state management
└── views/
    ├── auth/                  # Google OAuth & Sign-in screen
    ├── navigation/            # Main scaffold with responsive Sidebar / Bottom Bar
    ├── kanban/                # Dynamic drag-and-drop Kanban Board & Lane Manager
    ├── list_calendar/         # List, Calendar & Archive views
    ├── analytics/             # Velocity, workload & time breakdown charts
    ├── task_detail/           # Task editor modal, attachments, subtasks, stopwatch
    ├── workspace/             # Workspace switcher & member role management
    └── settings/              # Auto-expiry threshold & notification preferences

test/
├── models/                    # JSON roundtrips, parsing, ordering helpers
├── providers/                 # Notifier behavior incl. fake-repository persistence tests
└── views/                     # Kanban rendering, filters, drag & drop, lane management
```

---

## 📄 License
MIT License. Built with ❤️ using Flutter & Supabase.
