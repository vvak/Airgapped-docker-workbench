#!/usr/bin/env bash
# =============================================================================
# Entrypoint — starts SSH, fcron, telegraf, and the CI dispatcher loop
# =============================================================================
set -euo pipefail

LOG=/var/log/ci/platform.log
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [entrypoint] $*"; }

# -----------------------------------------------------------------------------
# 0. Ensure runtime directories exist (volumes start empty on first run)
# -----------------------------------------------------------------------------
mkdir -p \
    /data/images \
    /data/metrics/raw \
    /var/spool/ci/pending \
    /var/spool/ci/running \
    /var/spool/ci/done \
    /var/log/ci

# -----------------------------------------------------------------------------
# 1. SSH daemon
# -----------------------------------------------------------------------------
log "Starting SSH daemon on port 2222..."
/usr/sbin/sshd -f /etc/ssh/sshd_config
log "sshd started."

# -----------------------------------------------------------------------------
# 2. Seed images on first boot (requires internet at this point)
# -----------------------------------------------------------------------------
SEED_MARKER=/data/images/.seeded
if [[ ! -f "$SEED_MARKER" ]]; then
    log "First boot: running img-seed..."
    /usr/local/bin/img-seed && touch "$SEED_MARKER"
    log "Image seed complete."
else
    log "Images already seeded — skipping."
fi

# -----------------------------------------------------------------------------
# 3. fcron — for logrotate and metrics scheduling
# -----------------------------------------------------------------------------
log "Starting fcron..."
# Install crontab entries
cat > /tmp/cicd.cron <<'EOF'
# Rotate logs daily
0 0 * * * root /usr/sbin/logrotate /etc/logrotate.d/cicd

# Collect metrics every 60 seconds via telegraf one-shot
* * * * * root /usr/local/bin/telegraf \
    --config /etc/cicd/telegraf.conf \
    --once >> /data/metrics/raw/telegraf.log 2>&1
EOF
fcrontab /tmp/cicd.cron
fcron -f &
FCRON_PID=$!
log "fcron started (PID $FCRON_PID)."

# -----------------------------------------------------------------------------
# 4. CI dispatcher — polls /var/spool/ci/pending and runs jobs serially
#    Use flock so a second container exec can't double-dispatch
# -----------------------------------------------------------------------------
log "Starting CI dispatcher loop..."
(
    while true; do
        for job in /var/spool/ci/pending/*.job; do
            [[ -e "$job" ]] || continue
            flock -n "/var/spool/ci/running/$(basename "$job").lock" \
                /usr/local/bin/ci-run "$job" || true
        done
        sleep 5
    done
) &
DISPATCHER_PID=$!
log "CI dispatcher started (PID $DISPATCHER_PID)."

log ""
log "Platform ready."
log "  SSH git access : ssh git@<host> -p 2222"
log "  New repo       : new-repo <name>"
log "  Queue status   : ci-queue"
log "  Job logs       : ci-logs <job-id>"
log "  OCI images     : img-list"
log "  Metrics        : metrics-report"
log ""

# -----------------------------------------------------------------------------
# 5. Keep alive — trap signals for clean shutdown
# -----------------------------------------------------------------------------
cleanup() {
    log "Shutting down..."
    kill "$DISPATCHER_PID" 2>/dev/null || true
    kill "$FCRON_PID"      2>/dev/null || true
    pkill sshd             2>/dev/null || true
    log "Done."
}
trap cleanup SIGTERM SIGINT

wait "$DISPATCHER_PID"
