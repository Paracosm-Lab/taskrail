# Create a Queue

A queue is a reusable AI workflow. It defines the stages work moves through, which adapter runs each stage, what artifacts are expected, and which predicates decide whether work advances.

## Minimal Queue

Create `config/queues/example_review.yml`:

```yaml
name: Example Review
category: Development
slug: example_review
stages:
  - intake
  - analyze
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
stage_configs:
  intake:
    adapter_type: fake
    completion_criteria: [report_present]
    agent_prompt: Capture the request and produce an intake report.
  analyze:
    adapter_type: fake
    completion_criteria: [report_present]
    agent_prompt: Analyze the request and produce reviewable findings.
  human_review:
    adapter_type: fake
    completion_criteria: [review_verdict]
    agent_prompt: Wait for human review.
  done:
    adapter_type: fake
    completion_criteria: [report_present]
    agent_prompt: Terminal stage.
```

## Seed the Queue

```bash
bin/rails db:seed
bin/taskrail queues
bin/taskrail stages example_review
```

## Submit Work

```bash
bin/taskrail submit --queue example_review --title "Review auth flow" --spec ./README.md
```

## Run the Engine

```bash
bin/rails runner '10.times { Engine::Runner.new.call }'
```

## Inspect

```bash
bin/taskrail list --queue example_review
bin/taskrail status WORK_ITEM_ID --traces
```

## Customize

Change the queue by editing:

- `stages`: ordered lifecycle.
- `adapter_type`: fake, shell, Codex, Claude, Docker Compose, or another adapter.
- `completion_criteria`: predicates required to advance.
- `agent_prompt`: prompt text or `file://` prompt path.
- `max_retries`: stage retry budget.
- `timeout_seconds`: stage timeout.
- `escalation_target`: blocked work handoff.

## Design Rule

Keep the workflow outside the agent. The queue should define what done means before any agent runs.
