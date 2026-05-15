# Comparison

Why use Taskrail instead of GitHub Actions, Temporal, Airflow, BullMQ, Celery, or scripts?

Short answer:

> Generic runners execute tasks. Taskrail defines the operating model around AI work.

## The Missing Layer

The ecosystem already has:

- prompts
- models
- agents
- tools
- CI jobs
- background jobs
- durable workflow engines

What is missing is the operating queue around AI work.

That queue answers:

- What stage is this in?
- Which agent, model, or tool ran?
- What did it cost?
- What artifacts were produced?
- Which predicate allowed advancement?
- Where did it retry?
- When does a human review it?
- Can this workflow run again across another repo or team?

## GitHub Actions

GitHub Actions is good for CI/CD jobs tied to repositories, commits, pull requests, and deploy events.

Taskrail is different because AI work needs stage-level artifacts, model/tool adapters, cost visibility, review predicates, retries, and reusable queue state that is not necessarily tied to a commit event.

## Temporal

Temporal is good for durable distributed workflows.

Taskrail is different because it packages an AI-agent operating model: stages, adapters, prompts, model routing, artifacts, cost traces, review gates, and cookbook workflows.

Taskrail could use Temporal-like infrastructure underneath, but the product abstraction is the AI workflow queue.

## Airflow

Airflow is good for scheduled DAGs and data pipelines.

Taskrail is different because AI engineering workflows are often interactive, review-driven, artifact-driven, and repo/service-aware.

## BullMQ / Celery

BullMQ and Celery are good for background jobs.

Taskrail is different because it treats the queue as the product surface for AI work, not just a transport for jobs.

## Scripts

Scripts are good for fast one-off automation.

Taskrail is different because scripts do not naturally become observable, reusable, reviewable workflows with stage transitions, retries, artifacts, model flexibility, and human gates.

## Complementary, Not Replacement

Taskrail does not need to replace these systems.

A Taskrail stage can call shell commands, CI, existing workers, or agents through adapters. The value is the queue state around the work: what stage ran, what it cost, what it produced, and why it advanced or stopped.
