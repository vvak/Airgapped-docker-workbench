# CLI-Only Air-Gapped CI/CD Platform

A minimal, zero-UI CI/CD workbench that fits in a single Alpine container.
No inner Docker daemon. No web interfaces. No YAML pipelines. Just shell.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Alpine container                                   │
│                                                     │
│  sshd (port 2222)          ← git push / git clone  │
│  │                                                  │
│  └─ post-receive hook                               │
│       └─ writes .job file → /var/spool/ci/pending/  │
│                                                     │
│  CI dispatcher (bash loop)                          │
│       └─ ci-run → clones repo, runs .ci/pipeline.sh │
│                                                     │
│  fcron                                              │
│       ├─ telegraf --once  (every 60s → flat file)   │
│       └─ logrotate        (daily)                   │
│                                                     │
│  /data/images/   ← skopeo OCI image store           │
│  /var/log/ci/    ← per-job log files                │
│  /data/metrics/  ← telegraf flat-file metrics       │
└─────────────────────────────────────────────────────┘
```

## Project Structure

```
.
├── Dockerfile
├── configs/
│   ├── sshd_config
│   ├── telegraf.conf
│   ├── logrotate.conf
│   └── git-shell-commands/
│       └── no-interactive-login
├── scripts/
│   ├── entrypoint.sh
│   ├── ci-run              # execute a queued job
│   ├── ci-status           # tabular job results
│   ├── ci-logs             # view/tail a job log
│   ├── ci-queue            # inspect pending/running
│   ├── img-seed            # pull images into OCI store
│   ├── img-load            # load OCI image → Docker daemon
│   ├── img-list            # list seeded images
│   ├── metrics-report      # system + CI metrics summary
│   ├── new-repo            # create a bare repo + hook
│   └── hooks/
│       └── post-receive    # enqueues a CI job on push
└── docs/
    └── example-pipeline.sh
```

## Build

```bash
docker build -t cicd-cli:latest .
```

## Run

```bash
docker run -d \
  --name cicd-cli \
  -p 2222:2222 \
  -v cicd-repos:/home/git/repos \
  -v cicd-images:/data/images \
  -v cicd-metrics:/data/metrics \
  -v cicd-logs:/var/log/ci \
  cicd-cli:latest
```

> No `--privileged` needed unless your pipelines themselves run Docker.

## First-Time Setup

### 1. Add your SSH public key

```bash
docker exec cicd-cli bash -c \
  "echo 'ssh-ed25519 AAAA... you@host' >> /home/git/.ssh/authorized_keys"
```

### 2. Create a repository

```bash
docker exec cicd-cli new-repo myapp
```

### 3. Add the remote and push

```bash
git remote add origin ssh://git@localhost:2222/home/git/repos/myapp.git
git push origin main
```

### 4. Watch the job run

```bash
docker exec -it cicd-cli ci-queue           # see pending jobs
docker exec -it cicd-cli ci-status          # see results table
docker exec -it cicd-cli ci-logs <job-id>   # view full log
docker exec -it cicd-cli ci-logs <job-id> --follow
```

## Pipeline Script

Add `.ci/pipeline.sh` (or `ci.sh`) to your repo. It is a plain bash script:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Building $CI_COMMIT_SHA on $CI_COMMIT_REF"

# Load a pre-seeded image if you need Docker
img-load node:20-alpine

npm ci
npm test
npm run build
```

Available env vars inside pipelines:

| Variable | Value |
|---|---|
| `CI` | `true` |
| `CI_JOB_ID` | unique job ID |
| `CI_COMMIT_SHA` | full commit hash |
| `CI_COMMIT_REF` | e.g. `refs/heads/main` |
| `CI_REPO` | path to the bare repo |
| `CI_IMAGES_DIR` | `/data/images` |

## OCI Image Management

Before going air-gapped, populate the local image store:

```bash
# Edit scripts/img-seed to list the images you need, then:
docker exec cicd-cli img-seed

# Later, in a pipeline:
img-load python:3.12-slim
docker build ...
```

## Monitoring

```bash
docker exec -it cicd-cli metrics-report              # snapshot
docker exec -it cicd-cli metrics-report --sparkline  # CPU trend via gnuplot
docker exec -it cicd-cli ctop                        # live container stats
```

## Going Air-Gapped

1. Run `img-seed` while you still have internet.
2. Confirm images are present: `img-list`
3. Remove or block external network access — the container needs nothing after setup.

## Security Notes

- SSH password authentication is **disabled** — public key only.
- The `git` user is locked to `git-shell` — no interactive logins.
- No open ports beyond `2222`.
- Rotate SSH host keys if baking into an image for distribution.
