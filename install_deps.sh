#!/usr/bin/env bash
# =============================================================================
# install_deps.sh  –  macOS dependency installer for PFS-BatchKit-Manager
# Downloads and places macOS binaries into PFS-BatchKit-Manager/BAT/
# Installs Homebrew packages: sevenzip, gnu-sed, wget, macfuse, nbd
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BAT="$SCRIPT_DIR/PFS-BatchKit-Manager/BAT"
TMP_DL="$SCRIPT_DIR/.deps_tmp"

# ---- Colors ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; RESET='\033[0m'

banner() { echo -e "\n${WHITE}$1${RESET}"; echo "-------------------------------------------"; }
ok()     { echo -e "  ${GREEN}[OK]${RESET} $1"; }
warn()   { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
fail()   { echo -e "  ${RED}[FAIL]${RESET} $1"; }
info()   { echo -e "  ${CYAN}[INFO]${RESET} $1"; }

echo -e "\n${WHITE}PFS-BatchKit-Manager – macOS Dependency Installer${RESET}"
echo "==================================================="
echo ""

# ---- Homebrew ----
banner "Checking Homebrew"
if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ok "Homebrew installed"
else
    ok "Homebrew already installed: $(brew --version | head -1)"
fi

# ---- Homebrew packages ----
banner "Installing Homebrew packages"

BREW_PACKAGES=(
    "sevenzip"      # 7zz binary
    "gnu-sed"       # gsed (GNU sed for -i compatibility)
    "wget"          # wget (optional, curl used by default)
    "coreutils"     # GNU coreutils (gdu, etc.)
)

for pkg in "${BREW_PACKAGES[@]}"; do
    if brew list "$pkg" &>/dev/null; then
        ok "$pkg already installed"
    else
        info "Installing $pkg..."
        brew install "$pkg" && ok "$pkg installed" || warn "$pkg install failed"
    fi
done

# macFUSE (cask, needed for pfsfuse)
banner "Checking macFUSE (for PFS partition mounting)"
if brew list --cask macfuse &>/dev/null; then
    ok "macFUSE already installed"
else
    info "Installing macFUSE (requires password)..."
    brew install --cask macfuse && ok "macFUSE installed" \
        || warn "macFUSE install failed – pfsfuse/Explore PS2 HDD will not work"
fi

# ---- Download PS2 tools ----
banner "Downloading PS2 tools (hdl_dump, pfsshell, pfsfuse)"

mkdir -p "$TMP_DL" "$BAT"

# Detect architecture
ARCH=$(uname -m)
info "Architecture: $ARCH"

# hdl_dump (macOS binary from latest release)
HDL_BIN="$BAT/hdl_dump"
if [[ -f "$HDL_BIN" ]]; then
    ok "hdl_dump already present"
else
    info "Fetching latest hdl_dump macOS release..."
    HDL_URL=$(curl -s "https://api.github.com/repos/ps2homebrew/hdl-dump/releases/tags/latest" \
        | grep "browser_download_url" | grep "macos" | grep -v "hdl_dump_stable" \
        | head -1 | cut -d'"' -f4)
    if [[ -z "$HDL_URL" ]]; then
        warn "Could not fetch hdl_dump URL – check manually at https://github.com/ps2homebrew/hdl-dump/releases"
    else
        info "Downloading: $HDL_URL"
        curl -L "$HDL_URL" -o "$TMP_DL/hdl_dump.tar.gz"
        tar -xzf "$TMP_DL/hdl_dump.tar.gz" -C "$TMP_DL" 2>/dev/null || true
        find "$TMP_DL" -name "hdl_dump" -not -name "*.tar.gz" | head -1 | xargs -I{} cp {} "$HDL_BIN"
        chmod +x "$HDL_BIN"
        ok "hdl_dump installed → $HDL_BIN"

        # Also hdl_dump_stable if present in archive
        find "$TMP_DL" -name "hdl_dump_stable" | head -1 | xargs -I{} cp {} "$BAT/hdl_dump_stable" 2>/dev/null || true
        [[ -f "$BAT/hdl_dump_stable" ]] && chmod +x "$BAT/hdl_dump_stable" && ok "hdl_dump_stable installed"
    fi
fi

# pfsshell (macOS binary)
PFSSHELL_BIN="$BAT/pfsshell"
if [[ -f "$PFSSHELL_BIN" ]]; then
    ok "pfsshell already present"
else
    info "Fetching latest pfsshell macOS release..."
    PFS_URL=$(curl -s "https://api.github.com/repos/ps2homebrew/pfsshell/releases/tags/latest" \
        | grep "browser_download_url" | grep "pfsshell-macos" \
        | head -1 | cut -d'"' -f4)
    if [[ -z "$PFS_URL" ]]; then
        warn "Could not fetch pfsshell URL – check at https://github.com/ps2homebrew/pfsshell/releases"
    else
        info "Downloading: $PFS_URL"
        curl -L "$PFS_URL" -o "$TMP_DL/pfsshell-macos.zip"
        unzip -q "$TMP_DL/pfsshell-macos.zip" -d "$TMP_DL/pfsshell_unzip" 2>/dev/null || true
        find "$TMP_DL/pfsshell_unzip" -name "pfsshell" | head -1 | xargs -I{} cp {} "$PFSSHELL_BIN"
        chmod +x "$PFSSHELL_BIN"
        ok "pfsshell installed → $PFSSHELL_BIN"
    fi
fi

# pfsfuse (macOS binary)
PFSFUSE_BIN="$BAT/pfsfuse"
if [[ -f "$PFSFUSE_BIN" ]]; then
    ok "pfsfuse already present"
else
    info "Fetching latest pfsfuse macOS release..."
    PFSFUSE_URL=$(curl -s "https://api.github.com/repos/ps2homebrew/pfsshell/releases/tags/latest" \
        | grep "browser_download_url" | grep "pfsfuse-macos" \
        | head -1 | cut -d'"' -f4)
    if [[ -z "$PFSFUSE_URL" ]]; then
        warn "Could not fetch pfsfuse URL"
    else
        info "Downloading: $PFSFUSE_URL"
        curl -L "$PFSFUSE_URL" -o "$TMP_DL/pfsfuse-macos.zip"
        unzip -q "$TMP_DL/pfsfuse-macos.zip" -d "$TMP_DL/pfsfuse_unzip" 2>/dev/null || true
        find "$TMP_DL/pfsfuse_unzip" -name "pfsfuse" | head -1 | xargs -I{} cp {} "$PFSFUSE_BIN"
        chmod +x "$PFSFUSE_BIN"
        ok "pfsfuse installed → $PFSFUSE_BIN"
    fi
fi

# 7zz symlink (brew sevenzip installs as 7zz)
SEVENZIP_DIR="$BAT/7-Zip"
mkdir -p "$SEVENZIP_DIR"
if [[ ! -f "$SEVENZIP_DIR/7zz" ]]; then
    BREW_7ZZ=$(command -v 7zz 2>/dev/null)
    if [[ -n "$BREW_7ZZ" ]]; then
        ln -sf "$BREW_7ZZ" "$SEVENZIP_DIR/7zz"
        ok "7zz symlink created → $SEVENZIP_DIR/7zz"
    else
        warn "7zz not found in PATH – sevenzip may not be installed"
    fi
else
    ok "7zz already present in BAT/7-Zip/"
fi

# ---- Quarantine removal (macOS Gatekeeper) ----
banner "Removing Gatekeeper quarantine flags"
for bin in "$HDL_BIN" "$PFSSHELL_BIN" "$PFSFUSE_BIN" "$SEVENZIP_DIR/7zz"; do
    if [[ -f "$bin" ]]; then
        xattr -d com.apple.quarantine "$bin" 2>/dev/null || true
        ok "Cleared quarantine: $(basename $bin)"
    fi
done

# ---- Cleanup ----
rm -rf "$TMP_DL"

# ---- Make main script executable ----
MAIN_SCRIPT="$SCRIPT_DIR/PFS-BatchKit-Manager/!PFS-BatchKit-Manager.sh"
CACHE_SCRIPT="$SCRIPT_DIR/PFS-BatchKit-Manager/BAT/__ReloadHDD_cache.sh"
[[ -f "$MAIN_SCRIPT" ]]  && chmod +x "$MAIN_SCRIPT"  && ok "Main script is executable"
[[ -f "$CACHE_SCRIPT" ]] && chmod +x "$CACHE_SCRIPT" && ok "Cache script is executable"

# ---- Summary ----
echo ""
echo -e "${WHITE}==================================================="
echo -e "  Installation complete!"
echo -e "  Run: ./PFS-BatchKit-Manager/!PFS-BatchKit-Manager.sh"
echo -e "===================================================${RESET}"
echo ""

# Check missing
MISSING=()
[[ ! -f "$HDL_BIN" ]]      && MISSING+=("hdl_dump  → https://github.com/ps2homebrew/hdl-dump/releases")
[[ ! -f "$PFSSHELL_BIN" ]] && MISSING+=("pfsshell  → https://github.com/ps2homebrew/pfsshell/releases")
[[ ! -f "$PFSFUSE_BIN" ]]  && MISSING+=("pfsfuse   → https://github.com/ps2homebrew/pfsshell/releases")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${YELLOW}The following tools need manual installation:${RESET}"
    for m in "${MISSING[@]}"; do echo -e "  ${RED}•${RESET} $m"; done
    echo ""
fi
