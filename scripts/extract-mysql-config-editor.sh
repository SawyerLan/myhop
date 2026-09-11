#!/usr/bin/env bash
# Extracts just the `mysql_config_editor` binary from the official MySQL
# community client RPM, without installing the full package (which would
# conflict with an existing MariaDB client).
#
# Why this exists: on RHEL/CentOS 7 (and similar), the default client is
# MariaDB's and does not ship mysql_config_editor. mysql_config_editor turns
# out to have no dependency on libmysqlclient (it only needs libssl/libcrypto
# and friends, which the system already has), so it can be dropped into
# /usr/local/bin on its own with zero side effects on the existing MariaDB
# install. Verified on CentOS 7 x86_64 with MySQL 8.0.46.
#
# Usage:
#   ./extract-mysql-config-editor.sh [el-version] [arch]
#   ./extract-mysql-config-editor.sh 7 x86_64      # default
#
# Requires: curl, rpm2cpio, cpio, and outbound HTTPS access to repo.mysql.com.

set -euo pipefail

EL_VERSION="${1:-7}"
ARCH="${2:-x86_64}"
REPO_URL="https://repo.mysql.com/yum/mysql-8.0-community/el/${EL_VERSION}/${ARCH}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v rpm2cpio >/dev/null 2>&1 || { echo "rpm2cpio is required (yum install rpm2cpio, or 'rpm-build' package)" >&2; exit 1; }
command -v cpio >/dev/null 2>&1 || { echo "cpio is required" >&2; exit 1; }

echo "==> Finding the latest mysql-community-client package for el${EL_VERSION}/${ARCH}..."
PKG=$(curl -fsSL "$REPO_URL/" \
    | grep -oE "mysql-community-client-8\.0\.[0-9]+-1\.el${EL_VERSION}\.${ARCH}\.rpm" \
    | sort -t. -k3 -n | tail -1)
[ -n "$PKG" ] || { echo "Could not find a matching package under $REPO_URL" >&2; exit 1; }

echo "==> Downloading $PKG"
curl -fsSL -o "$WORKDIR/pkg.rpm" "$REPO_URL/$PKG"

echo "==> Extracting mysql_config_editor"
(cd "$WORKDIR" && rpm2cpio pkg.rpm | cpio -idm --quiet ./usr/bin/mysql_config_editor)

BIN="$WORKDIR/usr/bin/mysql_config_editor"
[ -x "$BIN" ] || { echo "Extraction failed: binary not found in package" >&2; exit 1; }

echo "==> Checking runtime dependencies"
if command -v ldd >/dev/null 2>&1; then
    if ldd "$BIN" 2>&1 | grep -q "not found"; then
        echo "Missing shared libraries:" >&2
        ldd "$BIN" | grep "not found" >&2
        exit 1
    fi
fi

DEST="${DEST:-/usr/local/bin/mysql_config_editor}"
echo "==> Installing to $DEST (requires sudo)"
sudo install -m 755 "$BIN" "$DEST"

echo "==> Done: $("$DEST" --version 2>&1 | head -1)"
echo "This does not touch your existing MariaDB/MySQL client."
