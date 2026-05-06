# Cookbook Queues

Place cookbook queue YAML examples here as `queues/<slug>.yml` unless a cookbook-specific plan needs the queue seeded from `config/queues/`.

Queue YAML should reference shared fake infrastructure with Rails-root-relative paths such as `cookbooks/docker-compose.yml` and should avoid custom `working_directory` values unless required.
