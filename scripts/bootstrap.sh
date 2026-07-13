#!/bin/bash
# Checks prerequisites before deploying: WSL2, Docker, .env, hosts file.
# Fails loudly with clear instructions instead of continuing into a
# half-configured stack (things like the Windows hosts entry can't be
# fixed automatically - they need admin rights on the Windows side).
set -u
cd "$(dirname "$0")/.."

FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  [ok]   $desc"
    else
        echo "  [FAIL] $desc"
        FAIL=1
    fi
}

echo "=== WSL2 ==="
check "running inside WSL2" grep -qi microsoft /proc/version

echo "=== Docker ==="
check "docker CLI available" command -v docker
check "docker daemon reachable" docker info
check "docker compose plugin available" docker compose version

echo "=== .env ==="
if [ ! -f .env ]; then
    echo "  [FAIL] .env not found"
    echo "         Run: cp .env.example .env, then fill in real values"
    FAIL=1
else
    echo "  [ok]   .env exists"
    # shellcheck disable=SC1091
    set -a; source .env; set +a
    for var in NC_DOMAIN DUCKDNS_TOKEN MYSQL_ROOT_PASSWORD MYSQL_PASSWORD NEXTCLOUD_ADMIN_PASSWORD LETSENCRYPT_EMAIL; do
        val="${!var:-}"
        case "$val" in
            ""|*YOURNAME*|*your-*|change-me*|*@email.com)
                echo "  [FAIL] $var is still a placeholder in .env"
                FAIL=1
                ;;
            *)
                echo "  [ok]   $var is set"
                ;;
        esac
    done
fi

echo "=== hosts resolution (NC_DOMAIN -> 127.0.0.1) ==="
if [ -n "${NC_DOMAIN:-}" ]; then
    RESOLVED=$(getent hosts "$NC_DOMAIN" | awk '{print $1}')
    if [ "$RESOLVED" = "127.0.0.1" ]; then
        echo "  [ok]   $NC_DOMAIN resolves to 127.0.0.1 inside WSL"
    else
        echo "  [FAIL] $NC_DOMAIN does not resolve to 127.0.0.1 in WSL (got: ${RESOLVED:-<nothing>})"
        echo "         Fix: sudo bash -c 'echo \"127.0.0.1 $NC_DOMAIN\" >> /etc/hosts'"
        echo "         (persists only if /etc/wsl.conf has [network] generateHosts = false)"
        FAIL=1
    fi
    echo "  [info] Also confirm C:\\Windows\\System32\\drivers\\etc\\hosts has:"
    echo "         127.0.0.1 $NC_DOMAIN"
    echo "         (edit via Notepad run as Administrator - this cannot be automated)"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "All checks passed."
    exit 0
else
    echo "One or more checks failed - fix the items above before 'make deploy'."
    exit 1
fi
