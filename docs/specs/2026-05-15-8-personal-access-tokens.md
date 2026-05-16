# Spec: Personal access tokens (2026-05-15-8)

## Use case

Humans and automation need API access without sharing one global `TASKRAIL_SERVICE_TOKEN`. TaskRail should support revocable, auditable personal access tokens tied to authenticated users.

## Scope

In scope:
- User-owned personal access tokens (PATs)
- Token creation, listing, revocation, and last-used tracking
- Bearer-token API authentication using PATs
- Token hashing at rest
- Minimal scopes needed for current API/admin split

Out of scope:
- OAuth applications
- Expiring refresh-token flows
- Organization-level token policies

## Requirements

### 1) Add a personal access token model

**Problem:** API auth currently depends on a single environment token. That is hard to rotate per user, cannot be audited per actor, and is easy to misconfigure.

**Fix:**
- Add `PersonalAccessToken` owned by `User`.
- Store only a secure digest of the token.
- Suggested fields:
  - `user_id`
  - `name`
  - `token_digest`
  - `token_prefix`
  - `scopes`, array or JSONB
  - `last_used_at`
  - `revoked_at`
  - `expires_at`
  - timestamps
- Enforce unique token digest.

**Test:**
- Creating a PAT stores a digest, not the raw token.
- Generated token is shown once.
- Revoked tokens cannot authenticate.
- Expired tokens cannot authenticate.

### 2) Add PAT management UI

**Problem:** Users need a way to create and revoke tokens after signing in.

**Fix:**
- Add an authenticated settings page for PATs.
- Users can:
  - list their active tokens by name, prefix, scopes, created date, last-used date
  - create a new token
  - revoke an existing token
- Never show the full token after creation.

**Test:**
- Authenticated user can create a PAT.
- Authenticated user can revoke their own PAT.
- Users cannot see or revoke another user's PAT.
- Full token is only present in the creation response/page.

### 3) Authenticate API requests with PATs

**Problem:** API controllers only validate `TASKRAIL_SERVICE_TOKEN`; this does not map requests to users.

**Fix:**
- Update API authentication to accept:
  - valid PAT bearer tokens
  - optionally, legacy `TASKRAIL_SERVICE_TOKEN` during migration
- Set `current_api_user` or equivalent when a PAT is used.
- Update `last_used_at` without causing excessive writes; throttle updates to a short interval such as 5 minutes.

**Test:**
- `Authorization: Bearer <valid_pat>` succeeds on API endpoints.
- Missing or invalid bearer token returns `401`.
- `last_used_at` updates after successful use.
- Revoked/expired token returns `401`.

### 4) Add scopes

**Problem:** A token should not automatically grant every action if future API surfaces expand.

**Fix:**
- Add initial scopes:
  - `read`
  - `write`
  - `admin`
- Enforce:
  - read endpoints require `read`
  - create/retry/cancel/answer require `write`
  - admin endpoints require `admin` and an admin user

**Test:**
- Read token cannot create/retry/cancel work items.
- Write token can create/retry/cancel work items.
- Non-admin user cannot create an admin-scoped token.
- Admin-scoped token can access admin API only when owned by an admin user.

## Acceptance criteria

- [ ] PATs are user-owned and hashed at rest
- [ ] PATs can be created, listed, and revoked in the web UI
- [ ] API bearer-token auth accepts valid PATs
- [ ] Invalid, revoked, and expired PATs are rejected
- [ ] Scopes are enforced for read/write/admin behavior
- [ ] Legacy service-token behavior is either migrated or explicitly documented
