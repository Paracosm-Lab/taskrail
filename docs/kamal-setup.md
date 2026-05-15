# Kamal Setup (Garageband)

This repo already includes Kamal. Use this checklist to configure and deploy safely.

## 1) Export required environment variables

```bash
export KAMAL_WEB_HOST="<garageband-server-ip-or-dns>"
export KAMAL_APP_HOST="<public-hostname-for-taskrail>"
export KAMAL_SSH_USER="<ssh-user-on-garageband>"

export KAMAL_REGISTRY_SERVER="192.168.1.76:5000"
export KAMAL_REGISTRY_USERNAME="taskrail"
export KAMAL_REGISTRY_PASSWORD="<registry-password>"

# Optional override for image name
export KAMAL_IMAGE="192.168.1.76:5000/taskrail"
```

## 2) Ensure secrets are available

Kamal reads secret references from `.kamal/secrets`:
- `KAMAL_REGISTRY_PASSWORD`
- `RAILS_MASTER_KEY`

If `config/master.key` is not present on your deploy machine, export:

```bash
export RAILS_MASTER_KEY="<rails-master-key>"
```

## 3) Run preflight

```bash
bin/kamal-setup
```

This validates env vars, SSH connectivity, Docker availability on garageband, and Kamal config rendering.

## 4) First deploy

```bash
bin/kamal setup
bin/kamal deploy
```

## 5) Verify

```bash
BASE_URL="https://${KAMAL_APP_HOST}" bin/monitor-prod
```

If deploy fails health checks, Kamal keeps old containers in place. Use:

```bash
bin/kamal rollback
```
