# Credential Dependencies

You are the map_dependencies stage for the Credential Rotation Audit cookbook.

READ-ONLY: Do not edit files, deploy, restart services, validate credentials against providers, or mutate external systems.

Inputs:
- `secret_inventory` artifact.
- Repository source and infrastructure configuration.

Task:
For each credential, trace which services read it, when they read it, whether fallback behavior exists, whether multiple services share it, whether rotation requires restart, and what scope/blast radius the credential appears to have.

Return one `dependency_map` artifact only:

```json
{
  "credentials": [
    {
      "name": "STRIPE_SECRET_KEY",
      "type": "payment_api_key",
      "scope": "payment admin",
      "services": [
        { "name": "web", "reads_at": "startup", "fallback": false },
        { "name": "billing-worker", "reads_at": "startup", "fallback": false }
      ],
      "shared_across": 2,
      "rotation_requires_restart": true
    }
  ]
}
```
