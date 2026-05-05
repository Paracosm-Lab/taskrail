# Cookbook 04: Feature Development

## Purpose

Demonstrates the original StupidClaw MVP development queue: cheap intake, frontier decomposition, async Codex implementation, shell validation, frontier review, and terminal completion.

## Queue

`development-codex`

```text
intake -> decompose -> build -> test -> review -> done
```

## Fixture Request

Use `test/fixtures/apps/feature_development` as the sample repository slice. The request is to make `CalendarExport#to_ics` emit a valid `VEVENT` with `DTSTART` and `SUMMARY`.

## Run

```bash
stupidclaw submit --queue development-codex --spec test/fixtures/apps/feature_development/README.md --title "Add iCalendar VEVENT export"
stupidclaw status SC-104 --traces
stupidclaw list --queue development-codex --stage build
stupidclaw answer SC-104 "Use UTC timestamps in basic iCalendar format"
stupidclaw retry SC-104
stupidclaw costs --work-item SC-104
```

## Expected Engine Loop

1. `intake` validates and classifies the request.
2. `decompose` emits child work items with acceptance criteria.
3. Child items start at `build` and Codex runs asynchronously.
4. `CheckAsyncClaimsJob` polls Codex and stores branch artifacts.
5. `test` runs shell validation and emits test/lint/coverage artifacts.
6. Failed validation regresses to `build` with feedback.
7. `review` approves or requests changes.
8. The parent advances after all children are `done`.

## Safety

- No stage may deploy or merge.
- Test stage may not edit files.
- Queue config and prompts are repo-relative.
- Blocking questions are answered through `stupidclaw answer`.
