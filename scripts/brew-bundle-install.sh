#!/bin/bash
# =============================================================================
# brew-bundle-install.sh
# Spike & Chilli Home Network (E2) — Homebrew Shared Bundle Install
# =============================================================================
# MANUAL USE ONLY — never automated. Run this deliberately.
#
# Installs packages listed in the shared curated Brewfile that are not yet
# present on this machine. Does NOT upgrade or remove existing packages.
#
# The shared Brewfile is a manually maintained common baseline.
# It is separate from the auto-generated Brewfile.<MachineName> files.
# Edit it directly at the NAS path before running this script.
#
# Shared Brewfile location (tried in order):
#   LAN:  /Volumes/home/Drive/Projects/Home Network Project/BrewSync/Brewfile
#   Away: ~/Library/CloudStorage/SynologyDrive-NASHome/Drive/
#             Projects/Home Network Project/BrewSync/Brewfile
#
# MZMacMini curation note: MZMacMini is Intel and permanently on an older
# macOS version. Packages that require a newer macOS should be excluded from
# the shared Brewfile, or installed only on Apple Silicon machines manually.
# Failures on individual packages are non-fatal — the script will continue
# and report them at the end.
#
# Usage:
#   bash /usr/local/bin/brew-bundle-install.sh
# =============================================================================

NAS_BREWDIR="/Volumes/home/Drive/Projects/Home Network Project/BrewSync"
DRIVE_BREWDIR="$HOME/Library/CloudStorage/SynologyDrive-NASHome/Drive/Projects/Home Network Project/BrewSync"

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"

echo ""
echo "══════════════════════════════════════════════"
echo "  brew-bundle-install — Spike & Chilli (E2)"
echo "  Machine: $MACHINE"
echo "══════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------------------------
# Detect brew binary
# ---------------------------------------------------------------------------
if   [ -x "/opt/homebrew/bin/brew" ]; then
    BREW="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    BREW="/usr/local/bin/brew"
else
    echo "✗ brew not found — is Homebrew installed?"
    exit 1
fi

# ---------------------------------------------------------------------------
# Locate shared Brewfile
# ---------------------------------------------------------------------------
if [ -f "$NAS_BREWDIR/Brewfile" ]; then
    SHARED_BREWFILE="$NAS_BREWDIR/Brewfile"
    echo "  Source: LAN ($SHARED_BREWFILE)"
elif [ -f "$DRIVE_BREWDIR/Brewfile" ]; then
    SHARED_BREWFILE="$DRIVE_BREWDIR/Brewfile"
    echo "  Source: Synology Drive / away ($SHARED_BREWFILE)"
else
    echo "✗ Shared Brewfile not found."
    echo "  Tried: $NAS_BREWDIR/Brewfile"
    echo "  Tried: $DRIVE_BREWDIR/Brewfile"
    echo ""
    echo "  To create it:"
    echo "    touch \"$NAS_BREWDIR/Brewfile\""
    echo "  Then add packages (one per line, e.g. 'brew \"git\"') and re-run."
    exit 1
fi

echo ""
echo "  Packages in shared Brewfile:"
grep -E '^(tap|brew|cask|mas) ' "$SHARED_BREWFILE" \
    | sed 's/^/    /' \
    || echo "    (empty — no packages defined yet)"
echo ""

# ---------------------------------------------------------------------------
# MZMacMini permanent older macOS warning
# ---------------------------------------------------------------------------
if echo "$MACHINE" | grep -qi "MZMac"; then
    echo "  ⚠  MZMacMini detected (Intel, permanently older macOS)"
    echo "     Some packages in the shared Brewfile may not support this"
    echo "     macOS version. Failures are non-fatal — the script continues"
    echo "     past them. Review at the end and remove incompatible entries"
    echo "     from the shared Brewfile."
    echo ""
fi

# ---------------------------------------------------------------------------
# Mac App Store warning
# ---------------------------------------------------------------------------
if grep -q '^mas ' "$SHARED_BREWFILE" 2>/dev/null; then
    echo "  ℹ  The shared Brewfile includes Mac App Store (mas) entries."
    echo "     These require the 'mas' CLI and the matching Apple ID to be"
    echo "     signed into the App Store on this Mac."
    echo ""
fi

read -rp "  Install missing packages from shared Brewfile on $MACHINE? [y/N]: " CONFIRM
echo ""

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "  Aborted — no changes made."
    exit 0
fi

echo "  Running: brew bundle --no-upgrade --no-lock --verbose"
echo "  (installs missing packages only; does not upgrade existing ones)"
echo ""

# --no-upgrade: don't upgrade packages already installed but outdated
# --no-lock:    don't write Brewfile.lock.json
# --verbose:    show each package as it's processed
if "$BREW" bundle \
    --file="$SHARED_BREWFILE" \
    --no-upgrade \
    --no-lock \
    --verbose 2>&1; then
    echo ""
    echo "  ✓ brew bundle complete"
else
    EXIT_CODE=$?
    echo ""
    echo "  ⚠ brew bundle exited with code $EXIT_CODE"
    echo "  One or more packages may not be compatible with this macOS version."
    echo "  Review the output above. Consider removing incompatible packages"
    echo "  from the shared Brewfile, or noting them with a comment."
fi

echo ""
echo "  Run brew-sync to snapshot this machine's updated state:"
echo "    bash /usr/local/bin/brew-sync.sh"
echo ""
