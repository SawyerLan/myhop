#!/usr/bin/env bash
# myhop installer: copies the CLI + bash completion into place and makes a
# best-effort attempt to install the tools myhop depends on:
#   - fzf                 (interactive picker)
#   - mysql_config_editor (encrypted credential storage; ships with the
#                           official MySQL client package)
#   - mycli                (optional; nicer interactive SQL shell)
#
# Usage:
#   One-liner (downloads bin/myhop and the completion script from GitHub):
#     curl -fsSL https://raw.githubusercontent.com/SawyerLan/myhop/main/install.sh | bash
#
#   From a local clone (useful for contributors, or the CentOS7 helper script):
#     git clone https://github.com/SawyerLan/myhop.git && cd myhop && ./install.sh
#
#   ./install.sh --system        install into /usr/local/bin (needs sudo)
#   ./install.sh --skip-deps     only install the myhop script itself
#
# Safe to re-run.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/SawyerLan/myhop/main"
PREFIX="$HOME/.local/bin"
SKIP_DEPS=false

for arg in "$@"; do
    case "$arg" in
        --system) PREFIX="/usr/local/bin" ;;
        --skip-deps) SKIP_DEPS=true ;;
        -h|--help)
            sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }

# When run via `curl | bash`, BASH_SOURCE has no usable directory to read
# sibling files from — fall back to downloading bin/myhop and the completion
# script straight from GitHub into a scratch dir.
RESOLVED_SCRIPT="${BASH_SOURCE[0]:-}"
if [ -n "$RESOLVED_SCRIPT" ] && [ -f "$RESOLVED_SCRIPT" ] && [ -f "$(dirname "$RESOLVED_SCRIPT")/bin/myhop" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$RESOLVED_SCRIPT")" && pwd)"
else
    have curl || { echo "curl is required to install myhop this way" >&2; exit 1; }
    SCRIPT_DIR="$(mktemp -d)"
    trap 'rm -rf "$SCRIPT_DIR"' EXIT
    mkdir -p "$SCRIPT_DIR/bin" "$SCRIPT_DIR/completions"
    echo "==> Fetching myhop from $REPO_RAW"
    curl -fsSL -o "$SCRIPT_DIR/bin/myhop" "$REPO_RAW/bin/myhop"
    curl -fsSL -o "$SCRIPT_DIR/completions/myhop.bash" "$REPO_RAW/completions/myhop.bash"
fi

log()  { echo "==> $1"; }
warn() { echo "WARNING: $1" >&2; }

detect_pkg_manager() {
    if have brew; then echo brew
    elif have apt-get; then echo apt
    elif have dnf; then echo dnf
    elif have yum; then echo yum
    elif have pacman; then echo pacman
    else echo none
    fi
}

PKG_MGR="$(detect_pkg_manager)"

install_pkg() {
    local pkg="$1"
    case "$PKG_MGR" in
        brew)   brew install "$pkg" ;;
        apt)    sudo apt-get update -qq && sudo apt-get install -y "$pkg" ;;
        dnf)    sudo dnf install -y "$pkg" ;;
        yum)    sudo yum install -y "$pkg" ;;
        pacman) sudo pacman -Sy --noconfirm "$pkg" ;;
        *)      return 1 ;;
    esac
}

ensure_fzf() {
    if have fzf; then
        log "fzf: already installed ($(command -v fzf))"
        return
    fi
    log "fzf: installing..."
    case "$PKG_MGR" in
        brew)   install_pkg fzf ;;
        apt)    install_pkg fzf ;;
        dnf)    install_pkg fzf ;;
        yum)    install_pkg fzf ;;
        pacman) install_pkg fzf ;;
        *)
            warn "no supported package manager found; install fzf manually: https://github.com/junegunn/fzf#installation"
            return
            ;;
    esac
    if have fzf; then log "fzf: installed"; else warn "fzf install may have failed, check manually"; fi
}

ensure_mycli() {
    if have mycli; then
        log "mycli: already installed ($(command -v mycli))"
        return
    fi
    log "mycli: installing (optional, myhop falls back to 'mysql' without it)..."
    if have pipx; then
        pipx install mycli && { log "mycli: installed via pipx"; return; }
    fi
    if have pip3; then
        pip3 install --user mycli && { log "mycli: installed via pip3 --user"; return; }
    fi
    case "$PKG_MGR" in
        brew) install_pkg mycli && return ;;
        apt)  install_pkg mycli && return ;;
    esac
    warn "could not auto-install mycli; myhop will use the plain 'mysql' client instead. See https://www.mycli.net/install"
}

ensure_mysql_config_editor() {
    if have mysql_config_editor; then
        log "mysql_config_editor: already installed ($(command -v mysql_config_editor))"
        return
    fi
    log "mysql_config_editor: installing (this is required — it's how myhop stores credentials without plaintext passwords)..."
    case "$PKG_MGR" in
        brew)
            brew install mysql-client
            brew link --force mysql-client >/dev/null 2>&1 || true
            ;;
        apt)
            install_pkg mysql-client || install_pkg default-mysql-client || true
            ;;
        dnf|yum)
            install_pkg mysql || true
            ;;
    esac

    if have mysql_config_editor; then
        log "mysql_config_editor: installed"
        return
    fi

    warn "mysql_config_editor is still missing."
    warn "Your distro's default client is likely MariaDB's, which doesn't ship this tool."
    warn "See scripts/extract-mysql-config-editor.sh for a way to pull just this one"
    warn "binary from the official MySQL client package without touching your"
    warn "existing MariaDB/MySQL client installation (tested on CentOS 7/RHEL 7)."
}

log "Installing myhop to $PREFIX"
mkdir -p "$PREFIX"
install -m 755 "$SCRIPT_DIR/bin/myhop" "$PREFIX/myhop"
log "myhop: installed to $PREFIX/myhop"

case ":$PATH:" in
    *":$PREFIX:"*) ;;
    *) warn "$PREFIX is not in your PATH. Add this to your shell rc file:
    export PATH=\"$PREFIX:\$PATH\"" ;;
esac

COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
mkdir -p "$COMPLETION_DIR"
install -m 644 "$SCRIPT_DIR/completions/myhop.bash" "$COMPLETION_DIR/myhop"
log "bash completion installed to $COMPLETION_DIR/myhop (new shells will pick it up automatically if bash-completion is installed; otherwise: source $COMPLETION_DIR/myhop)"

if ! $SKIP_DEPS; then
    ensure_fzf
    ensure_mysql_config_editor
    ensure_mycli
else
    log "Skipping dependency installation (--skip-deps)"
fi

echo
log "Done. Run 'myhop add' to register your first instance, or 'myhop help' for usage."
