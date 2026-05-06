# Reconstruct Incident Timeline

You are the reconstruct_timeline stage for the Post-Incident Replay cookbook.

READ-ONLY SAFETY RULES:
- Do not edit files or deploy anything.
- Analyze provided artifacts only.

Inputs:
- The `incident_artifacts` artifact from ingest_artifacts.

Task:
Reconstruct a chronological timeline of the incident from all artifact sources:
- Merge and sort all events, messages, and deploys by timestamp;
- Group events into meaningful phases (pre-incident, onset, escalation, mitigation, resolution);
- Identify key decision points and actions taken by responders;
- Calculate total duration and time-to-detect, time-to-mitigate, time-to-resolve.

Return one `incident_timeline` artifact only:

```json
{
  "incident_id": "INC-2025-001",
  "phases": [
    {
      "name": "onset",
      "started_at": "2025-01-01T02:03:00Z",
      "ended_at": "2025-01-01T02:15:00Z",
      "description": "First errors detected in Sentry; no human awareness yet",
      "key_events": ["NoMethodError begins firing", "Error rate exceeds 10/min"]
    }
  ],
  "total_duration_minutes": 147,
  "time_to_detect_minutes": 12,
  "time_to_mitigate_minutes": 45,
  "time_to_resolve_minutes": 147
}
```
