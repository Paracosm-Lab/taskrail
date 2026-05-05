# StupidClaw Cookbooks

Cookbooks are executable examples for StupidClaw queues. Shared infrastructure lives here so each cookbook can focus on its queue, prompts, predicates, and fixture app instead of rebuilding fake services.

## Layout

- `docker-compose.yml` provides shared fake services.
- `queues/` contains cookbook queue YAML examples.
- `prompts/<cookbook_slug>/` contains prompt files referenced by queue YAML with `file://cookbooks/prompts/<cookbook_slug>/<stage>.md`.
- `fixtures/apps/<cookbook_slug>/` contains small target apps or source trees.
- `runbooks/<cookbook_slug>/` contains fake runbooks used by operations/chaos/readiness examples.
- `fake_services/` contains the reusable local fake service script.

## Running shared fake services

```bash
docker compose -f cookbooks/docker-compose.yml up --build
```

Reset a fake service between scenarios:

```bash
curl -s -X POST http://localhost:4010/reset
```

## Portability rules

- Do not commit absolute checkout paths.
- Use Rails-root-relative `file://cookbooks/prompts/...` prompt references.
- Prefer adapter defaults for `working_directory`; StupidClaw's Docker Compose adapter defaults to `Rails.root.to_s`.
- Cookbook queue YAML may reference `cookbooks/docker-compose.yml` as a Rails-root-relative compose file.
