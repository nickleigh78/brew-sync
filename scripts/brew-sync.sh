#!/bin/bash
# =============================================================================
# brew-sync.sh
# Spike & Chilli Home Network (E2) — Homebrew Brewfile Snapshot
# =============================================================================
# Runs weekly via launchd (com.user.brewsync.plist).
# Shared across NLMacMiniM1 and NLMacbookProM3 — auto-detects machine name
# and brew path.
#
# WHAT THIS DOES:
#   Dumps this machine's full Homebrew state to a per-machine Brewfile
#   in network-ops/data/brew-sync/ on the NAS.
#   Output file: Brewfile.<ComputerName>
#
# WHAT THIS DOES NOT DO:
#   Does NOT install packages — see brew-bundle-install.sh
#   Does NOT modify other machines
#
# Requires /Volumes/network-ops to be mounted. If not mounted (Mac is away
# or NAS is down), the run is skipped and one line is appended to a local
# away log. The dump waits until network-ops is reachable again.
#
# Per-machine output files:
#   Brewfile.NLMacMiniM1       Nick's M1 Mac Mini (Apple Silicon)
#   Brewfile.NLMacbookProM3    Nick's MacBook Pro M3 (Apple Silicon)
#
# Log:      /Volumes/network-ops/logs/brew_<MACHINE>_sync_<YYYY-MM-DD-HHMM>.log
# Away log: ~/Library/Logs/brew-sync/away.log  (skip trail — no dump)
# Rotation: newest 15 runs kept per machine
# =============================================================================

NETWORK_OPS="/Volumes/network-ops"
BREWDIR="$NETWORK_OPS/data/brew-sync"
LOGDIR="$NETWORK_OPS/logs"
MAX_LOG_FILES=15

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"

# ---------------------------------------------------------------------------
# Guard: network-ops must be mounted
# ---------------------------------------------------------------------------
if [ ! -d "$BREWDIR" ]; then
    AWAY_LOG="$HOME/Library/Logs/brew-sync/away.log"
    mkdir -p "$(dirname "$AWAY_LOG")"
    printf '%s  skipped — /Volumes/network-ops not mounted (away or NAS down)\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >> "$AWAY_LOG"
    exit 1
fi

LOG_FILE="$LOGDIR/brew_${MACHINE}_sync_$(date '+%Y-%m-%d-%H%M').log"
mkdir -p "$LOGDIR"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

log "━━━ brew-sync.sh starting — $MACHINE ━━━"

# ---------------------------------------------------------------------------
# Detect brew binary
# ---------------------------------------------------------------------------
if   [ -x "/opt/homebrew/bin/brew" ]; then
    BREW="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    BREW="/usr/local/bin/brew"
else
    log "✗ brew not found at /opt/homebrew/bin/brew or /usr/local/bin/brew"
    exit 1
fi
log "  brew: $BREW"
log "  data: $BREWDIR"

BREWFILE="$BREWDIR/Brewfile.$MACHINE"

# ---------------------------------------------------------------------------
# Dump Brewfile
#   --force: overwrite existing file (update in place)
#   MAS entries included per-machine — each Mac has its own App Store apps
# ---------------------------------------------------------------------------
log "→ brew bundle dump → Brewfile.$MACHINE"
if "$BREW" bundle dump \
    --force \
    --file="$BREWFILE" >> "$LOG_FILE" 2>&1; then
    ENTRY_COUNT=$(awk '/^(tap|brew|cask|mas) /{count++} END{print count+0}' "$BREWFILE")
    log "✓ Brewfile.$MACHINE written ($ENTRY_COUNT entries)"
else
    log "✗ brew bundle dump failed (exit $?)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Log rotation — keep newest MAX_LOG_FILES, delete the rest
# ---------------------------------------------------------------------------
ls -1t "$LOGDIR"/brew_${MACHINE}_sync_*.log 2>/dev/null \
    | tail -n "+$((MAX_LOG_FILES + 1))" | xargs rm -f 2>/dev/null || true

log "━━━ brew-sync.sh complete ━━━"
log "  Brewfile.$MACHINE: $BREWFILE"
log "  To install from shared Brewfile: bash /usr/local/bin/brew-bundle-install.sh"
log ""
