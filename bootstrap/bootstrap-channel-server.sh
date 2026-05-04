#!/usr/bin/env bash
# bootstrap-channel-server.sh — provision a NiteRide.FM channel server from bare Ubuntu 24.04 LTS.
#
# Usage:
#   sudo ./bootstrap-channel-server.sh CHANNEL_ID [--dry-run] [--env-file PATH] [--force-rebuild]
#
# Reads channel-server golden state captured from CH1/CH2 (per niteridefm-infra/discovery/) and
# reproduces it: niteride user (UID 999/GID 989), /opt/niteride/{,data,services} ownership,
# /var/www/hls/segments/ ownership, pinned Node 20.x + ffmpeg 6.1.1 + pm2 6.0.14, dual PM2 systemd
# daemons (pm2-root.service + pm2-niteride.service), .env hydration, channel-suffixed nginx site.
#
# Idempotent: re-running on a partially-bootstrapped host is safe.
# Refuses to run on an already-bootstrapped channel (existing /opt/niteride/services/streaming-core/)
# unless --force-rebuild is passed.
#
# .env source-of-truth: pipe content via stdin, or pass --env-file PATH.
# Operator workflow for cloning from existing prod:
#   ssh root@ch1 'cat /opt/niteride/.env' | sudo ./bootstrap-channel-server.sh 3
#
# Post-bootstrap manual steps:
#   1. Run channel deploy workflow:  gh workflow run deploy-ch${N}.yml --repo gunswayfm/niteridefm-streaming-core
#   2. Update DNS / GCore origin pool to include the new channel IP
#   3. Run validation:  ./bootstrap/capture-channel-state.sh > /tmp/state.yaml ; diff against CH1/CH2
#
# Exit codes: 0=success, 1=usage error, 2=pre-flight failure, 3=install/config failure,
# 4=post-validation failure.

set -euo pipefail

# ---- Pinned versions (fleet invariant — see ~/products/niteride/engineering/invariants.md) ----
readonly NODE_MAJOR=20
readonly FFMPEG_VERSION_PIN="7:6.1.1-3ubuntu5"     # Ubuntu 24.04 noble apt
readonly PM2_VERSION="6.0.14"
readonly UBUNTU_RELEASE_PIN="24.04"
readonly NITERIDE_UID=999
readonly NITERIDE_GID=989

# ---- Args ----
CHANNEL_ID=""
DRY_RUN=0
ENV_FILE=""
ENV_STDIN=0
FORCE_REBUILD=0

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \?//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN=1; shift ;;
        --env-file)       ENV_FILE="$2"; shift 2 ;;
        --env-stdin)      ENV_STDIN=1; shift ;;
        --force-rebuild)  FORCE_REBUILD=1; shift ;;
        -h|--help)        usage ;;
        [0-9]*)           CHANNEL_ID="$1"; shift ;;
        *)                echo "ERROR: unknown arg: $1" >&2; usage ;;
    esac
done

[[ -z "${CHANNEL_ID}" ]] && { echo "ERROR: CHANNEL_ID required" >&2; usage; }
[[ "${CHANNEL_ID}" =~ ^[0-9]+$ ]] || { echo "ERROR: CHANNEL_ID must be numeric, got: ${CHANNEL_ID}" >&2; exit 1; }

# Mutually exclusive .env source
if [[ -n "${ENV_FILE}" ]] && [[ "${ENV_STDIN}" -eq 1 ]]; then
    echo "ERROR: --env-file and --env-stdin are mutually exclusive" >&2; exit 1
fi
if [[ -z "${ENV_FILE}" ]] && [[ "${ENV_STDIN}" -eq 0 ]]; then
    echo "ERROR: must specify .env source: --env-file PATH OR --env-stdin (then pipe content)" >&2; exit 1
fi

# ---- Logging helpers ----
log()  { printf '[bootstrap-ch%s] %s\n' "${CHANNEL_ID}" "$*"; }
warn() { printf '[bootstrap-ch%s] WARN: %s\n' "${CHANNEL_ID}" "$*" >&2; }
die()  { printf '[bootstrap-ch%s] FATAL: %s\n' "${CHANNEL_ID}" "$1" >&2; exit "${2:-3}"; }

run() {
    # Each caller passes a single shell-line string. We use bash -c so pipes and quoted
    # paths inside the string evaluate as written (NodeSource curl|bash, install with
    # quoted source/target, etc.). The string is internally controlled — never operator
    # input — so command-injection risk is bounded to the script's own contents.
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        printf '[dry-run] %s\n' "$*"
    else
        bash -c "$*"
    fi
}

# Staged .env content. Captured in preflight, consumed in phase_env.
# ENV_TEMP holds the path to either the operator's --env-file (do NOT delete) or our mktemp tempfile (DO delete).
ENV_TEMP=""
ENV_TEMP_OWNED=0
cleanup_envtemp() {
    if [[ "${ENV_TEMP_OWNED}" -eq 1 ]] && [[ -n "${ENV_TEMP}" ]] && [[ -f "${ENV_TEMP}" ]]; then
        rm -f "${ENV_TEMP}"
    fi
}
trap cleanup_envtemp EXIT

# Strip an inline comment + surrounding quotes/whitespace from an env-file value.
parse_env_value() {
    awk -v key="$1" -F= '
        $1 == key {
            sub(/[ \t]*#.*/,"",$2);
            gsub(/^[ \t"]+|[ \t"\047]+$/,"",$2);
            print $2;
            exit
        }' "$2"
}

# ---- Phase 1: Pre-flight (fully validates inputs BEFORE any state mutation) ----
phase_preflight() {
    log "Phase 1: pre-flight checks"

    if [[ "$(id -u)" -ne 0 ]]; then
        if [[ "${DRY_RUN}" -eq 1 ]]; then
            warn "not running as root — preview only; real run requires sudo"
        else
            die "must run as root (use sudo)" 2
        fi
    fi

    if [[ -r /etc/os-release ]]; then
        local version_id
        version_id=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        [[ "${version_id}" == "${UBUNTU_RELEASE_PIN}" ]] || \
            warn "Ubuntu ${UBUNTU_RELEASE_PIN} expected, got ${version_id} — proceeding but fleet-parity not guaranteed"
    fi

    # Refuse to clobber an existing channel-server install
    if [[ -d /opt/niteride/services/streaming-core ]] && [[ "${FORCE_REBUILD}" -ne 1 ]]; then
        die "/opt/niteride/services/streaming-core/ exists — pass --force-rebuild to proceed" 2
    fi

    # Resolve .env source NOW (not in phase_env). Either --env-file points at a readable file,
    # or --env-stdin captures stdin into a tempfile. Either way, ENV_TEMP holds the staged content
    # and phase_env just installs it.
    if [[ -n "${ENV_FILE}" ]]; then
        [[ -r "${ENV_FILE}" ]] || die "--env-file ${ENV_FILE} unreadable" 2
        ENV_TEMP="${ENV_FILE}"
        ENV_TEMP_OWNED=0  # operator's file — do not delete on exit
    else
        # --env-stdin: drain stdin to a tempfile and verify non-empty
        ENV_TEMP=$(mktemp /tmp/bootstrap-env.XXXXXX)
        ENV_TEMP_OWNED=1  # we created it — clean up on exit
        chmod 0600 "${ENV_TEMP}"
        cat > "${ENV_TEMP}"
        [[ -s "${ENV_TEMP}" ]] || die "--env-stdin received empty content (pipe a populated .env)" 2
    fi

    # Validate the staged .env BEFORE we touch the box
    local staged_channel
    staged_channel=$(parse_env_value CHANNEL_ID "${ENV_TEMP}")
    if [[ -z "${staged_channel}" ]]; then
        warn "staged .env has no CHANNEL_ID — script will append CHANNEL_ID=${CHANNEL_ID} during phase 6"
    elif [[ "${staged_channel}" != "${CHANNEL_ID}" ]]; then
        die "staged .env CHANNEL_ID=${staged_channel} contradicts arg CHANNEL_ID=${CHANNEL_ID}" 2
    fi

    # Sanity: require a minimum set of vars that downstream services depend on
    local required=(REDIS_URL DATABASE_URL SUPABASE_JWT_SECRET SEGMENT_SIGNING_SECRET)
    local missing=()
    for var in "${required[@]}"; do
        [[ -n "$(parse_env_value "${var}" "${ENV_TEMP}")" ]] || missing+=("${var}")
    done
    if [[ "${#missing[@]}" -gt 0 ]]; then
        die "staged .env missing required vars: ${missing[*]}" 2
    fi
}

# ---- Phase 2: apt packages ----
phase_apt() {
    log "Phase 2: apt install (Node ${NODE_MAJOR}.x + ffmpeg ${FFMPEG_VERSION_PIN})"

    run "apt-get update -qq"

    # Node via NodeSource (matches CH1/CH2 install method)
    if ! command -v node >/dev/null 2>&1 || [[ "$(node -v 2>/dev/null | cut -d. -f1 | tr -d v)" != "${NODE_MAJOR}" ]]; then
        run "curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -"
        run "apt-get install -y nodejs"
    fi

    # Verify ffmpeg pin available before install (FAIL LOUD per Risk #2)
    local available_ffmpeg
    available_ffmpeg=$(apt-cache madison ffmpeg 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")
    if [[ "${available_ffmpeg}" != "${FFMPEG_VERSION_PIN}" ]] && [[ "${DRY_RUN}" -ne 1 ]]; then
        die "ffmpeg pin drift: wanted ${FFMPEG_VERSION_PIN}, apt offers ${available_ffmpeg}. Review backlog before continuing." 3
    fi

    run "apt-get install -y ffmpeg=${FFMPEG_VERSION_PIN} nginx redis-tools postgresql-client jq python3 python3-pip curl ca-certificates"

    # PM2 global pin
    if ! command -v pm2 >/dev/null 2>&1 || [[ "$(pm2 --version 2>/dev/null)" != "${PM2_VERSION}" ]]; then
        run "npm install -g pm2@${PM2_VERSION}"
    fi

    # CrowdSec + cs-firewall-bouncer (defends origin from bot scans)
    if ! command -v cscli >/dev/null 2>&1; then
        # Bootstrap the CrowdSec apt repo (idempotent) then install.
        # See https://docs.crowdsec.net/u/getting_started/installation
        run "curl -fsSL https://install.crowdsec.net | bash"
        run "apt-get install -y crowdsec crowdsec-firewall-bouncer-iptables"
    fi
}

# ---- Phase 3: niteride user/group ----
phase_user() {
    log "Phase 3: niteride user (UID ${NITERIDE_UID}/GID ${NITERIDE_GID})"

    if ! getent group niteride >/dev/null; then
        run "groupadd --gid ${NITERIDE_GID} niteride"
    fi
    if ! getent passwd niteride >/dev/null; then
        run "useradd --uid ${NITERIDE_UID} --gid ${NITERIDE_GID} --create-home --shell /bin/bash niteride"
    fi
}

# ---- Phase 4: directory layout ----
phase_dirs() {
    log "Phase 4: /opt/niteride + /var/www/hls layout"

    run "install -d -o niteride -g niteride -m 0755 /opt/niteride"
    run "install -d -o niteride -g niteride -m 0755 /opt/niteride/services"
    run "install -d -o niteride -g niteride -m 0775 /opt/niteride/data"
    run "install -d -o niteride -g niteride -m 0755 /var/www/hls"
    run "install -d -o niteride -g niteride -m 0775 /var/www/hls/segments"
}

# ---- Phase 4.5: sshd hardening drop-in ----
# Codifies the 6-directive hardening set CH1 + CH2 carried operator-applied
# pre-2026-05-04 (audit row #11). Drop-in form so distro sshd_config stays
# package-managed; dpkg upgrades won't prompt for conffile resolution.
phase_ssh() {
    log "Phase 4.5: sshd hardening drop-in"

    local repo_root src dst
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    src="${repo_root}/bootstrap/sshd_config.d/99-niteride-hardening.conf"
    dst="/etc/ssh/sshd_config.d/99-niteride-hardening.conf"

    [[ -f "${src}" ]] || die "sshd hardening drop-in missing in repo at ${src}" 7

    run "install -d -o root -g root -m 0755 /etc/ssh/sshd_config.d"
    run "install -o root -g root -m 0644 '${src}' '${dst}'"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "  [dry-run] skipping sshd -t + reload ssh"
        return 0
    fi

    sshd -t || die "sshd config invalid after drop-in install" 7
    run "systemctl reload ssh"

    log "  ✓ 99-niteride-hardening.conf installed; sshd reloaded"
}

# ---- Phase 5: dual PM2 systemd daemons ----
phase_systemd() {
    log "Phase 5: pm2-root.service + pm2-niteride.service"

    # Canonical pm2 startup template (matches `pm2 startup systemd` output, audited against CH1/CH2)
    local pm2_path
    pm2_path=$(command -v pm2 || echo /usr/bin/pm2)

    write_unit() {
        local user="$1"
        local pm2_home="$2"
        local unit_path="$3"

        local content
        content=$(cat <<EOF
[Unit]
Description=PM2 process manager (${user})
Documentation=https://pm2.keymetrics.io/
After=network.target

[Service]
Type=forking
User=${user}
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/node/bin
Environment=PM2_HOME=${pm2_home}
PIDFile=${pm2_home}/pm2.pid
Restart=on-failure

ExecStart=${pm2_path} resurrect
ExecReload=${pm2_path} reload all
ExecStop=${pm2_path} kill

[Install]
WantedBy=multi-user.target
EOF
        )

        if [[ "${DRY_RUN}" -eq 1 ]]; then
            printf '[dry-run] write %s:\n%s\n' "${unit_path}" "${content}"
        else
            printf '%s\n' "${content}" > "${unit_path}"
        fi
    }

    write_unit root      /root/.pm2           /etc/systemd/system/pm2-root.service
    write_unit niteride  /home/niteride/.pm2  /etc/systemd/system/pm2-niteride.service

    run "systemctl daemon-reload"
    run "systemctl enable pm2-root.service pm2-niteride.service"

    # Pre-create PM2_HOME dirs so pm2 doesn't create them root-owned on first start
    run "install -d -o root -g root -m 0755 /root/.pm2"
    run "install -d -o niteride -g niteride -m 0755 /home/niteride/.pm2"

    # Re-run safety: if pm2 daemons are already active and the unit content changed,
    # daemon-reload only refreshes systemd's view — the running daemon keeps the old ExecStart.
    # Don't auto-restart (would kill in-flight channel apps); surface a warn instead.
    if [[ "${DRY_RUN}" -ne 1 ]] && [[ "${FORCE_REBUILD}" -eq 1 ]]; then
        for svc in pm2-root.service pm2-niteride.service; do
            if systemctl is-active --quiet "${svc}"; then
                warn "${svc} is currently running with a possibly older unit file. To pick up unit changes: systemctl restart ${svc} (operator decides — restart kills in-flight services)"
            fi
        done
    fi
}

# ---- Phase 6: .env hydration ----
# Validation already happened in phase_preflight; this phase just installs the staged tempfile.
phase_env() {
    log "Phase 6: /opt/niteride/.env hydration"

    local target=/opt/niteride/.env
    run "install -m 0600 -o niteride -g niteride '${ENV_TEMP}' '${target}'"

    if [[ "${DRY_RUN}" -ne 1 ]]; then
        local staged_channel
        staged_channel=$(parse_env_value CHANNEL_ID "${target}")
        if [[ -z "${staged_channel}" ]]; then
            warn ".env had no CHANNEL_ID line — appending CHANNEL_ID=${CHANNEL_ID}"
            printf '\nCHANNEL_ID=%s\n' "${CHANNEL_ID}" >> "${target}"
        fi
    fi
}

# ---- Phase 7: nginx site ----
phase_nginx() {
    log "Phase 7: nginx ch${CHANNEL_ID}-hls.conf"

    local template_dir
    template_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local template="${template_dir}/ch-hls.conf.template"

    [[ -r "${template}" ]] || die "nginx template missing at ${template}" 3

    local target=/etc/nginx/sites-available/ch${CHANNEL_ID}-hls.conf

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        printf '[dry-run] render %s -> %s with CHANNEL_ID=%s\n' "${template}" "${target}" "${CHANNEL_ID}"
    else
        sed "s/__CHANNEL_ID__/${CHANNEL_ID}/g" "${template}" > "${target}"
    fi

    # Remove Ubuntu's default site to avoid duplicate `default_server` collision on port 80
    run "rm -f /etc/nginx/sites-enabled/default"

    run "ln -sf '${target}' /etc/nginx/sites-enabled/ch${CHANNEL_ID}-hls.conf"
    run "nginx -t" || die "nginx config test failed — review ${target}" 3
    run "systemctl reload nginx"
}

# ---- Phase 7.5: CrowdSec parsers (GCore CDN whitelist) ----
# Without the GCore whitelist, bot scans flowing through cdn.niteride.fm get
# attributed to the GCore shield POP IP — CrowdSec then bans the shield IP and
# nukes the stream. See engineering/platforms/gcore-cdn.md (2026-05-03 P0).
phase_crowdsec() {
    log "Phase 7.5: CrowdSec parsers (GCore CDN whitelist)"

    local repo_root src dst
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    src="${repo_root}/crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml"
    dst="/etc/crowdsec/parsers/s02-enrich/niteride-gcore-whitelist.yaml"

    if [[ ! -f "${src}" ]]; then
        die "CrowdSec whitelist missing in repo at ${src}" 5
    fi

    run "install -o root -g root -m 0644 '${src}' '${dst}'"
    run "systemctl reload crowdsec || systemctl restart crowdsec"

    [[ "${DRY_RUN}" -eq 1 ]] && { log "  [dry-run] skipping cscli ops"; return 0; }

    if ! cscli parsers inspect niteride/gcore-cdn-whitelist >/dev/null 2>&1; then
        die "CrowdSec did not register niteride/gcore-cdn-whitelist after reload" 6
    fi

    log "  ✓ niteride/gcore-cdn-whitelist registered"

    # Hub collections — codifies what CH1 + CH2 had operator-installed
    # pre-2026-05-04 (audit row #13). Without these, fresh bootstrap ships
    # bare CrowdSec — no nginx/sshd/CVE detection scenarios. cscli install
    # is idempotent; --force reconciles content drift if collections were
    # touched outside the script.
    log "  installing hub collections (idempotent)..."
    run "cscli hub update"
    local collections=(
        crowdsecurity/linux
        crowdsecurity/nginx
        crowdsecurity/sshd
        crowdsecurity/base-http-scenarios
        crowdsecurity/http-cve
        crowdsecurity/whitelist-good-actors
    )
    for c in "${collections[@]}"; do
        run "cscli collections install '${c}' --force"
    done
    run "systemctl reload crowdsec"

    log "  ✓ 6 hub collections installed"
}

# ---- Phase 8: post-bootstrap validation ----
phase_validate() {
    log "Phase 8: post-bootstrap validation"

    [[ "${DRY_RUN}" -eq 1 ]] && { log "  [dry-run] skipping validation"; return 0; }

    local fail=0

    # niteride user
    getent passwd niteride | grep -qE ":${NITERIDE_UID}:${NITERIDE_GID}:" || \
        { warn "niteride user UID/GID mismatch"; fail=1; }

    # ownership
    [[ "$(stat -c '%U:%G' /opt/niteride/data)"     == "niteride:niteride" ]] || { warn "/opt/niteride/data not niteride-owned"; fail=1; }
    [[ "$(stat -c '%U:%G' /var/www/hls/segments)"  == "niteride:niteride" ]] || { warn "/var/www/hls/segments not niteride-owned"; fail=1; }

    # systemd units enabled
    systemctl is-enabled --quiet pm2-root.service     || { warn "pm2-root.service not enabled"; fail=1; }
    systemctl is-enabled --quiet pm2-niteride.service || { warn "pm2-niteride.service not enabled"; fail=1; }

    # versions pinned
    local node_major
    node_major=$(node -v | cut -d. -f1 | tr -d v)
    [[ "${node_major}" == "${NODE_MAJOR}" ]] || { warn "Node major mismatch: want ${NODE_MAJOR}, got ${node_major}"; fail=1; }

    local ffmpeg_ver
    ffmpeg_ver=$(ffmpeg -version 2>&1 | head -1 | awk '{print $3}' | cut -d- -f1)
    [[ "${ffmpeg_ver}" == "6.1.1" ]] || { warn "ffmpeg version mismatch: want 6.1.1, got ${ffmpeg_ver}"; fail=1; }

    local pm2_ver
    pm2_ver=$(pm2 --version)
    [[ "${pm2_ver}" == "${PM2_VERSION}" ]] || { warn "pm2 version mismatch: want ${PM2_VERSION}, got ${pm2_ver}"; fail=1; }

    # nginx site
    [[ -L "/etc/nginx/sites-enabled/ch${CHANNEL_ID}-hls.conf" ]] || { warn "nginx site symlink missing"; fail=1; }

    # .env present + readable by niteride only
    [[ "$(stat -c '%U:%G %a' /opt/niteride/.env)" == "niteride:niteride 600" ]] || \
        { warn "/opt/niteride/.env perms drift"; fail=1; }

    # PM2_HOME dirs present + correctly owned
    [[ "$(stat -c '%U' /root/.pm2)"          == "root"     ]] || { warn "/root/.pm2 not root-owned"; fail=1; }
    [[ "$(stat -c '%U' /home/niteride/.pm2)" == "niteride" ]] || { warn "/home/niteride/.pm2 not niteride-owned"; fail=1; }

    # CrowdSec parser present (defends origin from bot-scan-via-CDN bans)
    cscli parsers inspect niteride/gcore-cdn-whitelist >/dev/null 2>&1 || \
        { warn "CrowdSec parser niteride/gcore-cdn-whitelist not registered"; fail=1; }

    # CrowdSec hub collections (audit row #13)
    local required_collections=(
        crowdsecurity/linux
        crowdsecurity/nginx
        crowdsecurity/sshd
        crowdsecurity/base-http-scenarios
        crowdsecurity/http-cve
        crowdsecurity/whitelist-good-actors
    )
    for c in "${required_collections[@]}"; do
        cscli collections inspect "${c}" >/dev/null 2>&1 || \
            { warn "CrowdSec collection ${c} not installed"; fail=1; }
    done

    # sshd hardening drop-in present + effective (audit row #11)
    [[ -f /etc/ssh/sshd_config.d/99-niteride-hardening.conf ]] || \
        { warn "sshd hardening drop-in missing"; fail=1; }
    # Verify effective config picked up the drop-in
    local sshd_effective
    sshd_effective=$(sshd -T 2>/dev/null)
    grep -q '^passwordauthentication no$' <<<"${sshd_effective}" || \
        { warn "sshd PasswordAuthentication != no (drop-in not effective?)"; fail=1; }
    grep -q '^permitrootlogin prohibit-password$' <<<"${sshd_effective}" || \
        { warn "sshd PermitRootLogin != prohibit-password (drop-in not effective?)"; fail=1; }

    [[ "${fail}" -eq 0 ]] || die "post-bootstrap validation FAILED" 4

    log "  ✓ all post-bootstrap checks pass"
}

# ---- Phase 9: next-step hint ----
phase_next() {
    log "Phase 9: bootstrap complete"
    cat <<EOF

  Next steps (manual):
    1. Trigger channel deploy workflow to clone streaming-core repo + start services:
         gh workflow run deploy-ch${CHANNEL_ID}.yml --repo gunswayfm/niteridefm-streaming-core
       (creates /opt/niteride/services/* and registers apps with both PM2 daemons)

    2. After services are running, save dump files for reboot survival:
         pm2 save
         sudo -u niteride PM2_HOME=/home/niteride/.pm2 pm2 save

    3. Verify dual-daemon invariant (no overlap):
         ~/code/niteridefm-infra/scripts/pm2-dump-overlap-check.sh

    4. DNS / GCore origin pool update (if onboarding a new channel CH${CHANNEL_ID})

    5. CrowdSec agent enrollment against orch's LAPI (REQUIRES OPERATOR INPUT):
         # On orch: cscli machines add ch${CHANNEL_ID}-agent --auto > /tmp/enroll.yaml
         # SCP /tmp/enroll.yaml to this host as /etc/crowdsec/local_api_credentials.yaml
         # systemctl restart crowdsec
       Verify with: cscli lapi status

EOF
}

# ---- Main ----
log "starting (DRY_RUN=${DRY_RUN}, FORCE_REBUILD=${FORCE_REBUILD})"
phase_preflight
phase_apt
phase_user
phase_ssh
phase_dirs
phase_systemd
phase_env
phase_nginx
phase_crowdsec
phase_validate
phase_next
log "OK"
