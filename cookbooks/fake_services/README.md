# Cookbook Fake Services

Shared fake services live here and are mounted by `cookbooks/docker-compose.yml` into Ruby containers.

Each Compose service runs the same deterministic script with a different `FAKE_SERVICE_NAME` and `FAKE_SERVICE_PORT`.
