# Spec: Devise authentication (2026-05-15-7)

## Use case

TaskRail's browser UI exposes operational workflow data and state-changing actions. Before production exposure, human-facing web routes need real user authentication instead of relying on network placement or obscurity.

## Scope

In scope:
- Add Devise-backed user authentication
- Protect all web UI routes
- Protect admin routes with authenticated user plus admin authorization
- Keep machine API authentication separate from browser sessions
- Seed or document first-admin bootstrap

Out of scope:
- Multi-tenant organizations
- Fine-grained RBAC beyond admin/non-admin
- OAuth/SAML/SSO

## Requirements

### 1) Install Devise and create users

**Problem:** `Web::BaseController` does not require authentication, so `/`, `/queues`, `/work_items/:id`, and browser actions are public if the app is reachable.

**Fix:**
- Add Devise.
- Create a `User` model with at least:
  - `email`
  - encrypted password
  - `admin` boolean, default `false`, null false
  - timestamps
- Enforce unique, normalized email addresses.
- Add Devise routes.

**Test:**
- User can sign in with valid credentials.
- Invalid credentials do not sign in.
- Email uniqueness is enforced case-insensitively.

### 2) Require authentication for web UI

**Problem:** The current web controllers inherit from `ActionController::Base` and do not call `authenticate_user!`.

**Fix:**
- Add `before_action :authenticate_user!` to `Web::BaseController`.
- Verify all web UI controllers inherit from `Web::BaseController`.
- Redirect unauthenticated browser requests to the Devise sign-in page.

**Test:**
- `GET /` without a session redirects to sign-in.
- `GET /work_items/:id` without a session redirects to sign-in.
- Authenticated users can view queues and work item detail pages.
- Authenticated users can create, retry, and cancel work items through the web UI.

### 3) Protect admin routes with admin authorization

**Problem:** Admin routes currently use bearer-token auth only. Once browser authentication exists, admin endpoints need an authenticated-user path that does not weaken API service-token behavior.

**Fix:**
- Keep API controllers on bearer-token auth.
- For `/admin/*`, require an authenticated Devise user.
- Require `current_user.admin?`.
- Return a clear forbidden response for non-admin users.
- Preserve token-based admin support only if explicitly needed for automation, and cover it with tests.

**Test:**
- Unauthenticated request to `/admin/*` is rejected.
- Authenticated non-admin user gets `403`.
- Authenticated admin user succeeds.
- Existing API bearer-token behavior remains covered separately.

### 4) Bootstrap first admin safely

**Problem:** Adding auth without a bootstrap path can lock out a fresh installation.

**Fix:**
- Provide a documented, explicit bootstrap path such as:
  - `bin/rails taskrail:create_admin EMAIL=... PASSWORD=...`
  - or seed-only creation gated by required environment variables.
- Do not create default credentials.
- Do not log passwords.

**Test:**
- Bootstrap task creates an admin user when required env vars are present.
- Bootstrap task fails clearly when required env vars are missing.
- Running the task twice does not create duplicate users.

## Acceptance criteria

- [ ] Devise is installed and configured for `User`
- [ ] Web UI routes require login
- [ ] Admin routes require an admin user
- [ ] Machine API auth remains independent from browser sessions
- [ ] Fresh-install admin bootstrap is documented and tested
- [ ] Request/system specs cover unauthenticated, non-admin, and admin flows
