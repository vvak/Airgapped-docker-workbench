# =============================================================================
# CLI-Only Air-Gapped CI/CD Platform
# Tools: git/SSH, fcron, skopeo, telegraf, ctop, gnuplot
# No inner Docker daemon, no web UIs, no service containers
# =============================================================================

FROM alpine:3.20

LABEL maintainer="your-team"
LABEL description="Minimal CLI-only CI/CD platform — git, pipelines, OCI images, metrics"

# -----------------------------------------------------------------------------
# Core system packages
# -----------------------------------------------------------------------------
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    git \
    openssh \
    openssl \
    ca-certificates \
    fcron \
    logrotate \
    gnuplot \
    jq \
    file \
    procps \
    coreutils \
    findutils \
    sed \
    gawk \
    ncurses \
    tzdata \
    shadow \
    sudo \
    flock \
    && rm -rf /var/cache/apk/*

# -----------------------------------------------------------------------------
# Install skopeo (OCI image copy tool)
# -----------------------------------------------------------------------------
RUN apk add --no-cache skopeo --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
    || (echo "skopeo not in community, building from edge" && \
        apk add --no-cache skopeo --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main \
                                   --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community)

# -----------------------------------------------------------------------------
# Install ctop (container top — live stats)
# https://github.com/bcicen/ctop
# -----------------------------------------------------------------------------
ARG CTOP_VERSION=0.7.7
RUN wget -qO /usr/local/bin/ctop \
    "https://github.com/bcicen/ctop/releases/download/v${CTOP_VERSION}/ctop-${CTOP_VERSION}-linux-amd64" \
    && chmod +x /usr/local/bin/ctop

# -----------------------------------------------------------------------------
# Install telegraf (metrics agent, writes to flat files — no daemon needed)
# -----------------------------------------------------------------------------
ARG TELEGRAF_VERSION=1.30.3
RUN wget -qO /tmp/telegraf.tar.gz \
    "https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}_linux_amd64.tar.gz" \
    && tar -xzf /tmp/telegraf.tar.gz -C /tmp \
    && mv /tmp/telegraf-${TELEGRAF_VERSION}/usr/bin/telegraf /usr/local/bin/telegraf \
    && rm -rf /tmp/telegraf*

# -----------------------------------------------------------------------------
# Create the git user (owns all repos, accepts SSH)
# -----------------------------------------------------------------------------
RUN adduser -D -s /bin/bash -h /home/git git \
    && passwd -d git \
    && passwd -u git \
    && mkdir -p /home/git/.ssh \
    && chmod 700 /home/git/.ssh \
    && touch /home/git/.ssh/authorized_keys \
    && chmod 600 /home/git/.ssh/authorized_keys \
    && chown -R git:git /home/git

# -----------------------------------------------------------------------------
# Directory structure
# -----------------------------------------------------------------------------
RUN mkdir -p \
    /home/git/repos \
    /var/spool/ci/pending \
    /var/spool/ci/running \
    /var/spool/ci/done \
    /var/log/ci \
    /data/images \
    /data/metrics \
    /data/metrics/raw \
    /etc/cicd \
    /usr/local/lib/cicd \
    && chown -R git:git /home/git/repos \
    && chown -R nobody:nobody /var/spool/ci \
    && chmod -R 1777 /var/spool/ci

# -----------------------------------------------------------------------------
# Copy all configuration and scripts
# -----------------------------------------------------------------------------
COPY configs/sshd_config          /etc/ssh/sshd_config
COPY configs/logrotate.conf        /etc/logrotate.d/cicd
COPY configs/telegraf.conf         /etc/cicd/telegraf.conf
COPY configs/git-shell-commands/   /home/git/git-shell-commands/

COPY scripts/entrypoint.sh         /usr/local/bin/entrypoint
COPY scripts/ci-run                /usr/local/bin/ci-run
COPY scripts/ci-status             /usr/local/bin/ci-status
COPY scripts/ci-logs               /usr/local/bin/ci-logs
COPY scripts/ci-queue              /usr/local/bin/ci-queue
COPY scripts/img-seed              /usr/local/bin/img-seed
COPY scripts/img-load              /usr/local/bin/img-load
COPY scripts/img-list              /usr/local/bin/img-list
COPY scripts/metrics-report        /usr/local/bin/metrics-report
COPY scripts/new-repo              /usr/local/bin/new-repo
COPY scripts/hooks/post-receive    /usr/local/lib/cicd/post-receive

RUN chmod +x \
    /usr/local/bin/entrypoint \
    /usr/local/bin/ci-run \
    /usr/local/bin/ci-status \
    /usr/local/bin/ci-logs \
    /usr/local/bin/ci-queue \
    /usr/local/bin/img-seed \
    /usr/local/bin/img-load \
    /usr/local/bin/img-list \
    /usr/local/bin/metrics-report \
    /usr/local/bin/new-repo \
    /usr/local/lib/cicd/post-receive \
    && chown -R git:git /home/git/git-shell-commands

# Generate SSH host keys
RUN ssh-keygen -A

# Allow root (CI dispatcher) to clone repos owned by the git user.
# safe.directory=* is required from git 2.35.2+ when uid of caller != uid of repo owner.
RUN git config --system safe.directory '*'

# -----------------------------------------------------------------------------
# Expose SSH only — everything else is CLI/file-based
# -----------------------------------------------------------------------------
EXPOSE 2222

# -----------------------------------------------------------------------------
# Persistent volumes
# -----------------------------------------------------------------------------
VOLUME ["/home/git/repos", "/data/images", "/data/metrics", "/var/log/ci"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD pgrep sshd > /dev/null && pgrep fcron > /dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint"]
