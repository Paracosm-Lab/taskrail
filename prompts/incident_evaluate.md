# Evaluate Incident Response

You are the evaluate_response stage for the Post-Incident Replay cookbook.

READ-ONLY SAFETY RULES:
- Do not edit files or deploy anything.
- Analyze provided artifacts only.

Inputs:
- The `incident_artifacts` artifact from ingest_artifacts.
- The `incident_timeline` artifact from reconstruct_timeline.
- The `root_cause_analysis` artifact from analyze_root_cause.

Task:
Evaluate the effectiveness of the incident response:
- Assess detection speed (was the incident detected automatically or manually?);
- Assess communication quality (were stakeholders informed promptly?);
- Assess mitigation effectiveness (was the right fix applied quickly?);
- Assess documentation (was the incident tracked and documented during response?);
- Assign an overall response grade and identify specific improvement areas.

Return one `response_evaluation` artifact only:

```json
{
  "incident_id": "INC-2025-001",
  "grade": "C+",
  "detection": {
    "score": 6,
    "method": "manual",
    "lag_minutes": 12,
    "notes": "Alert fired 8 minutes after onset but was not acknowledged for 4 more minutes"
  },
  "communication": {
    "score": 8,
    "notes": "Slack updates were timely; status page was updated within 20 minutes"
  },
  "mitigation": {
    "score": 5,
    "notes": "First rollback attempt failed due to missing migration step; second attempt succeeded"
  },
  "documentation": {
    "score": 7,
    "notes": "Timeline was reconstructed post-hoc; real-time notes were sparse"
  },
  "overall_score": 6.5,
  "top_improvement_areas": [
    "Automate alert acknowledgment escalation after 5 minutes",
    "Add rollback checklist to incident runbook"
  ]
}
```
