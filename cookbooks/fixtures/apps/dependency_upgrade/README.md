# Dependency Upgrade Fixture App

This tiny fixture simulates a Rails-ish application with stale Ruby and Node dependencies.
It is intentionally static and safe for Docker/local cookbook tests: the audit script prints deterministic JSON and does not run networked package manager commands.
