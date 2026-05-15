# Cookbook Prompts

Place prompt files under `prompts/<cookbook_slug>/<stage>.md`.

Queue YAML should reference prompts with Rails-root-relative `file://cookbooks/prompts/<cookbook_slug>/<stage>.md` values so seeding can resolve prompt contents portably.
