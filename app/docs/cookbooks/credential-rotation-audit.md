# Credential Rotation Audit

The `credential_rotation` cookbook is a read-only advisory queue for finding credentials, mapping dependencies, scoring rotation risk, and drafting human-executed rotation plans.

It never rotates, revokes, deploys, restarts, or contacts credential providers automatically. The `human_review` stage is the handoff point for humans to execute one credential at a time with health checks and rollback ready.
