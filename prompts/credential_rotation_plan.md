# Credential Rotation Plan

You are the draft_rotation_plan stage for the Credential Rotation Audit cookbook.

READ-ONLY SAFETY RULES:
- Do not rotate credentials.
- Do not generate new provider keys.
- Do not revoke old keys.
- Do not deploy, restart, or modify services.
- Produce an advisory document for humans to execute manually one credential at a time.

Inputs:
- `risk_assessment` artifact.
- `dependency_map` artifact.
- Repository source for service health-check clues.

Task:
For every critical or high-risk credential, draft a safe human rotation procedure:
1. Generate a new credential in the provider dashboard/API manually.
2. Store it in the secrets manager or environment config.
3. Deploy/restart affected services in a safe order.
4. Verify each service is healthy with the new credential.
5. Revoke the old credential only after verification.
6. Note when git history exposure means rotation alone is not enough.
7. For hardcoded credentials, describe the code change to move them into a secrets manager before rotation.
8. Estimate downtime risk and rollback for every step.

Return one `rotation_plan` artifact only:

```json
{
  "rotations": [
    {
      "credential_name": "STRIPE_SECRET_KEY",
      "risk_level": "critical",
      "steps": [
        {
          "action": "Generate replacement Stripe secret key manually in the Stripe dashboard",
          "target": "Stripe dashboard",
          "verification": "New key exists and is not yet active in production services",
          "rollback": "Do not revoke the old key"
        }
      ],
      "services_affected": ["web", "billing-worker"],
      "estimated_downtime": "low if both services are restarted after secret update; high if only one service is updated",
      "requires_code_change": true,
      "code_change_description": "Move config/payment.yml hardcoded key to ENV.fetch("STRIPE_SECRET_KEY") backed by the secrets manager before rotating."
    }
  ],
  "rotation_order": ["STRIPE_SECRET_KEY"]
}
```
