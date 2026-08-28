# Task Sphere 🚀
> **Cross-Platform Serverless Kanban Task Management App** built with **Flutter**, **Supabase**, and **Google Drive API**.

Task Sphere is a modern, high-performance task management application for mobile (Android & iOS), desktop (macOS), and Web. It features role-based workspace management, custom drag-and-drop Kanban lanes, auto-expiry task archiving, local due-date notifications, and direct file attachment syncing via Google Drive with **zero local server required**.

---

## 🌟 Key Features

- 📌 **Customizable Kanban Board**: Default lanes (`To Do`, `In Progress`, `Partially Done`, `Done`, `Wont Do`) + Admin custom lane creator, color customizer, and column reordering.
- 🗄️ **Smart Auto-Expiry & Archiving**: Automatically hide old completed tasks from active view after a configurable duration (7, 14, 30 days or Never) with a dedicated search/restore Archive view.
- 👥 **Workspaces & Role-Based Access (RBAC)**: Create multi-user workspaces with **Admin** (lane control, task assignment, member management) and **Member** permissions.
- 📊 **Analytics Dashboard**: Interactive visual charts (`fl_chart`) tracking velocity, lane distribution, member workload, and logged work hours.
- 📁 **Serverless Google Drive Attachments**: Attach files, images, and documents directly to your Google Drive folder without intermediate backend servers.
- 🔔 **Local Notifications**: Scheduled due date reminders and task assignment alerts.
- 🌙 **Modern Glassmorphic UI**: Sleek dark/light modes, micro-animations (`flutter_animate`), responsive desktop sidebar & mobile navigation bar.

---

## 🛠️ Step-by-Step Backend Setup

### 1. Supabase Project Setup (Database & Real-time)

1. Go to [Supabase](https://supabase.com) and create a free account.
2. Click **New Project** and name your project `task-sphere`.
3. Go to the **SQL Editor** tab in your Supabase Dashboard.
4. Open the provided [`supabase/schema.sql`](supabase/schema.sql) file in this codebase, paste it into the Supabase SQL editor, and click **RUN**.
   - This creates all necessary tables (`workspaces`, `workspace_lanes`, `workspace_members`, `tasks`, `subtasks`, `activity_logs`).
   - Configures Row Level Security (RLS) policies for workspace privacy.
   - Sets up default lane initialization triggers and enables Realtime WebSockets on `workspaces`, `workspace_lanes`, `workspace_members`, `tasks`, `subtasks`, and `activity_logs`.
   - The script is idempotent - it is safe to re-run after pulling newer versions.
5. Enable the **Google provider** (required for sign-in on every platform):
   - Go to **Authentication -> Providers -> Google**.
   - Toggle **Enable Sign in with Google**.
   - Paste the **Client ID** and **Client Secret** from the Google OAuth Web client you will create in the next section, then **Save**.
6. Go to **Project Settings -> API** in Supabase and copy your:
   - `Project URL` (e.g., `https://xyzcompany.supabase.co`)
   - `anon public key` (e.g., `eyJhbGciOi...`)

---

### 2. Google OAuth 2.0 & Google Drive API Setup

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project named `Task Sphere`.
3. Enable the **Google Drive API**:
   - Go to **APIs & Services -> Library**.
   - Search for **Google Drive API** and click **Enable**.
4. Configure the **OAuth Consent Screen**:
   - Go to **APIs & Services -> OAuth consent screen**.
   - Select **User Type: External** and click **Create**.
   - Add app name: `Task Sphere`.
   - Add scope: `.../auth/drive.file` (View and manage Google Drive files created by this app).
5. Create **OAuth 2.0 Credentials**:
   - Go to **APIs & Services -> Credentials -> Create Credentials -> OAuth client ID**.
   - **Web Client**: Set Authorized JavaScript origins to `http://localhost:3000` or your production domain. Copy its **Client ID** and **Client Secret** - these go into the Supabase Google provider configured in the previous section.
   - **Android Client**: Add your package name (`com.tasksphere.app`) and SHA-1 certificate fingerprint.
   - **iOS Client**: Add Bundle ID (`com.tasksphere.app`).
   - **macOS Client**: Add Bundle ID (`com.tasksphere.app`).
   - The sign-in request automatically includes the `email`, `profile`, and `openid` scopes - no extra consent-screen setup is needed for those.

---

## 🚀 Running the App

### Environment Configuration
Provide your Supabase URL & Anon Key when launching or building the app:

```bash
# Web
flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY

# macOS Desktop
flutter run -d macos --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY

# Android / iOS
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

> **Demo / Local Offline Mode**: If no Supabase credentials are input, Task Sphere automatically falls back to local in-memory/mock storage so you can immediately evaluate the app offline!

---

## 🌐 Deploying the Web App (Cloudflare Pages)

The web build is a fully static Flutter bundle - no server required. A GitHub Actions workflow (`.github/workflows/deploy.yml`) builds and deploys it to Cloudflare Pages on every push to `main`.

### One-time setup

1. **Add GitHub Actions secrets** (Repo → Settings → Secrets and variables → Actions):
   - `SUPABASE_URL` - your Supabase project URL
   - `SUPABASE_ANON_KEY` - your Supabase anon public key
   - `CLOUDFLARE_API_TOKEN` - Cloudflare API token with "Cloudflare Pages — Edit" permission (Cloudflare Dashboard → My Profile → API Tokens)
   - `CLOUDFLARE_ACCOUNT_ID` - shown on the right side of the Cloudflare Dashboard home page
2. **Push to `main`** - the workflow runs tests, builds the bundle, and creates a Pages project named `task-sphere` on first deploy.
3. Your app is live at **`https://task-sphere.pages.dev`** (attach a custom domain under Cloudflare Pages → Custom domains if you own one).

### Required cloud configuration for web sign-in & attachments

- **Supabase Auth**: set the **Site URL** to your deployed URL (`https://task-sphere.pages.dev`) under Supabase → Authentication → URL Configuration, so the Google OAuth redirect flow returns to your app.
- **Google Cloud Console**: add a **Web** OAuth client ID with the deployed URL in *Authorized JavaScript origins* for Drive attachment uploads.

### Manual deploy (optional)

```bash
flutter build web --release --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
npx wrangler pages deploy build/web --project-name task-sphere
```

> **Note**: local due-date notifications are not available in browsers; the app degrades gracefully on web.

---

## 🧪 Development & CI

```bash
flutter pub get
flutter analyze          # zero issues enforced by CI
flutter test             # 89 unit + widget tests
```

- **CI** (`.github/workflows/ci.yml`) runs `flutter analyze` and `flutter test` on every push and pull request.
- **Deploy** (`.github/workflows/deploy.yml`) additionally builds the web bundle and ships it to Cloudflare Pages on every push to `main`.
- **Testing conventions**: model tests live in `test/models/`, provider/state tests in `test/providers/` (with fake repositories for the Supabase layer), and widget tests in `test/views/`.

---

## 🏗️ Project Architecture

```
lib/
├── main.dart                  # App initialization, Supabase setup & Theme provider
├── core/
│   ├── theme/                 # Modern theme design system, glassmorphism card styles
│   ├── repositories/          # Supabase + in-memory persistence for workspaces, tasks, logs
│   └── services/              # Supabase, Google Drive & Local Notification services
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
└── views/                     # Kanban rendering, filters, drag & drop
```

---

## 📄 License
MIT License. Built with ❤️ using Flutter & Supabase.
