#!/bin/bash
# =============================================================================
# brew-sync.sh
# Spike & Chilli Home Network (E2) — Homebrew Brewfile Snapshot
# =============================================================================
# Runs weekly via launchd (com.user.brewsync.plist).
# Shared across all three Macs — auto-detects machine name and brew path.
#
# WHAT THIS DOES:
#   Dumps this machine's full Homebrew state to a per-machine Brewfile
#   in the NAS BrewSync folder (or Synology Drive fallback when away).
#   Output file: Brewfile.<ComputerName>
#
# WHAT THIS DOES NOT DO:
#   Does NOT install packages — see brew-bundle-install.sh
#   Does NOT modify other machines
#   Does NOT push to any remote — Brewfiles are data, not code;
#     they live on the NAS, not in the brew-sync git repo
#
# Storage (tried in order):
#   LAN:  /Volumes/home/Drive/Projects/Home Network Project/BrewSync/
#   Away: ~/Library/CloudStorage/SynologyDrive-NASHome/Drive/
#             Projects/Home Network Project/BrewSync/
#
# MacBook (NLMacbookProM3) uses LAN path at home, Drive path when away.
# NLMacMiniM1 and MZMacMini always use the LAN path.
#
# Per-machine output files:
#   Brewfile.NLMacMiniM1       Nick's M1 Mac Mini (Apple Silicon)
#   Brewfile.NLMacbookProM3    Nick's MacBook Pro M3 (Apple Silicon)
#   Brewfile.MZMacMini         Marty's Mac Mini (Intel, older macOS)
#
# Log: ~/Library/Logs/brew-sync.log
# =============================================================================

LOG_FILE="$HOME/Library/Logs/brew-sync.log"
MAX_LOG_LINES=500

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

mkdir -p "$(dirname "$LOG_FILE")"

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"
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

# ---------------------------------------------------------------------------
# Resolve storage path — NAS LAN preferred, Synology Drive as fallback
# ---------------------------------------------------------------------------
NAS_BREWDIR="/Volumes/home/Drive/Projects/Home Network Project/BrewSync"
DRIVE_BREWDIR="$HOME/Library/CloudStorage/SynologyDrive-NASHome/Drive/Projects/Home Network Project/BrewSync"

if [ -d "$NAS_BREWDIR" ]; then
    BREWDIR="$NAS_BREWDIR"
    STORAGE_MODE="LAN"
elif [ -d "$DRIVE_BREWDIR" ]; then
    BREWDIR="$DRIVE_BREWDIR"
    STORAGE_MODE="Synology Drive (away)"
else
    log "✗ BrewSync directory not found on NAS or Synology Drive"
    log "  Tried: $NAS_BREWDIR"
    log "  Tried: $DRIVE_BREWDIR"
    log "  Ensure NAS is mounted or Synology Drive is synced."
    log "  Run manually once available: bash /usr/local/bin/brew-sync.sh"
    exit 1
fi

log "  storage: $STORAGE_MODE"
log "  path: $BREWDIR"

BREWFILE="$BREWDIR/Brewfile.$MACHINE"

# ---------------------------------------------------------------------------
# Dump Brewfile
#   --force:    overwrite existing file (update in place)
#   --describe: add a comment above each entry (self-documenting Brewfiles)
#   MAS entries are included per-machine — each Mac has its own App Store apps
# ---------------------------------------------------------------------------
log "→ brew bundle dump → Brewfile.$MACHINE"
if "$BREW" bundle dump \
    --force \
    --describe \
    --file="$BREWFILE" >> "$LOG_FILE" 2>&1; then
    # Count entries (taps, formulae, casks, mas) using awk for portability
    ENTRY_COUNT=$(awk '/^(tap|brew|cask|mas) /{count++} END{print count+0}' "$BREWFILE")
    log "✓ Brewfile.$MACHINE written ($ENTRY_COUNT entries)"
else
    log "✗ brew bundle dump failed (exit $?)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Log rotation
# ---------------------------------------------------------------------------
if [ -f "$LOG_FILE" ]; then
    LINE_COUNT=$(awk 'END{print NR}' "$LOG_FILE")
    if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
        tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" \
            && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
fi

log "━━━ brew-sync.sh complete ━━━"
log "  Brewfile.$MACHINE is at: $BREWFILE"
log "  To install from shared Brewfile: bash /usr/local/bin/brew-bundle-install.sh"
log ""
