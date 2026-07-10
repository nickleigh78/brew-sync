#!/bin/bash
# =============================================================================
# sync-macs.sh
# Spike & Chilli Home Network (E2) — Cross-Mac Homebrew Sync
# =============================================================================
# MANUAL USE ONLY — never automated.
#
# Installs packages from the shared NAS Brewfile on this machine AND the
# other Mac via SSH. Machine-aware: auto-detects which Mac it's running on
# and targets the other.
#
#   NLMacMiniM1     → installs locally, then SSHes to NLMacbookProM3
#   NLMacbookProM3  → installs locally, then SSHes to NLMacMiniM1
#
# SSH uses key-based auth (no password prompt).
# /Volumes/network-ops must be mounted on BOTH Macs for this to work
# (each Mac reads the shared Brewfile from its own mount).
#
# Usage: bash /usr/local/bin/sync-macs.sh
# Log:   /Volumes/network-ops/logs/brew_<MACHINE>_syncmacs_<YYYY-MM-DD-HHMM>.log
# Rotation: newest 10 runs kept
# =============================================================================

NETWORK_OPS="/Volumes/network-ops"
BREWDIR="$NETWORK_OPS/data/brew-sync"
LOGDIR="$NETWORK_OPS/logs"
SHARED_BREWFILE="$BREWDIR/Brewfile"
MAX_LOG_FILES=10

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"

# ---------------------------------------------------------------------------
# Detect local brew binary
# ---------------------------------------------------------------------------
if   [ -x "/opt/homebrew/bin/brew" ]; then
    LOCAL_BREW="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    LOCAL_BREW="/usr/local/bin/brew"
else
    echo "✗ brew not found — is Homebrew installed?"
    exit 1
fi

# ---------------------------------------------------------------------------
# Machine-aware SSH target
# ---------------------------------------------------------------------------
case "$MACHINE" in
    NLMacMiniM1)
        SSH_USER="nickleigh"
        SSH_HOST="NLMacbookProM3.local"
        ;;
    NLMacbookProM3)
        SSH_USER="nickleigh"
        SSH_HOST="NLMacMiniM1.local"
        ;;
    *)
        echo "✗ Unknown machine: $MACHINE"
        echo "  sync-macs.sh supports NLMacMiniM1 and NLMacbookProM3 only."
        exit 1
        ;;
esac

SSH_TARGET="$SSH_USER@$SSH_HOST"

# ---------------------------------------------------------------------------
# Guard: network-ops and shared Brewfile must exist locally
# ---------------------------------------------------------------------------
if [ ! -f "$SHARED_BREWFILE" ]; then
    echo "✗ Shared Brewfile not found: $SHARED_BREWFILE"
    echo "  Check that /Volumes/network-ops is mounted on this Mac."
    exit 1
fi

mkdir -p "$LOGDIR"
LOG_FILE="$LOGDIR/brew_${MACHINE}_syncmacs_$(date '+%Y-%m-%d-%H%M').log"

log() {
    local line
    line="$(printf '%s  %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$*")"
    printf '%s\n' "$line"
    printf '%s\n' "$line" >> "$LOG_FILE"
}

echo ""
echo "══════════════════════════════════════════════════════"
echo "  sync-macs — Spike & Chilli Home Network (E2)"
echo "  This machine : $MACHINE"
echo "  SSH target   : $SSH_TARGET"
echo "  Brewfile     : $SHARED_BREWFILE"
echo "══════════════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------------------------
# Check remote is reachable before asking for a password
# ---------------------------------------------------------------------------
log "→ Checking connectivity to $SSH_HOST..."
if ! nc -z -w 5 "$SSH_HOST" 22 2>/dev/null; then
    log "✗ Cannot reach $SSH_HOST port 22"
    log "  Is the Mac on and connected to the network?"
    exit 1
fi
log "✓ $SSH_HOST is reachable"
echo ""

# ---------------------------------------------------------------------------
# Local install
# ---------------------------------------------------------------------------
log "→ Installing on $MACHINE (local)..."
if "$LOCAL_BREW" bundle \
    --file="$SHARED_BREWFILE" \
    --no-upgrade \
    --verbose 2>&1 | tee -a "$LOG_FILE"; then
    log "✓ Local install complete"
else
    log "⚠ Local install exited non-zero — review output above"
fi

echo ""
log "→ Installing on $SSH_HOST (SSH)..."
echo ""

# Remote install — network-ops must also be mounted on the remote Mac
ssh "$SSH_TARGET" bash << 'REMOTE' 2>&1 | tee -a "$LOG_FILE"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
BREW="/opt/homebrew/bin/brew"
SHARED_BREWFILE="/Volumes/network-ops/data/brew-sync/Brewfile"
if [ ! -f "$SHARED_BREWFILE" ]; then
    echo "✗ Brewfile not found on remote: $SHARED_BREWFILE"
    echo "  /Volumes/network-ops may not be mounted on this Mac."
    exit 1
fi
"$BREW" bundle --file="$SHARED_BREWFILE" --no-upgrade --verbose
REMOTE

REMOTE_EXIT="${PIPESTATUS[0]}"
if [ "$REMOTE_EXIT" -eq 0 ]; then
    log "✓ Remote install on $SSH_HOST complete"
else
    log "⚠ Remote install on $SSH_HOST exited with code $REMOTE_EXIT"
fi

# ---------------------------------------------------------------------------
# Log rotation
# ---------------------------------------------------------------------------
ls -1t "$LOGDIR"/brew_${MACHINE}_syncmacs_*.log 2>/dev/null \
    | tail -n "+$((MAX_LOG_FILES + 1))" | xargs rm -f 2>/dev/null || true

log "━━━ sync-macs.sh complete ━━━"
echo ""
echo "  Run brew-sync to snapshot both machines' updated state:"
echo "    bash /usr/local/bin/brew-sync.sh"
echo ""
