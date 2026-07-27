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
#   Dumps this machine's full Homebrew state to a per-machine Brewfile and
#   publishes it to network-ops/data/brew-sync/ on the NAS. Output: Brewfile.<ComputerName>
#
# WHAT THIS DOES NOT DO:
#   Does NOT install packages — see brew-bundle-install.sh
#   Does NOT modify other machines
#
# TRANSPORT (2026-07-28): FDA-free SSH, not the SMB mount. macOS TCC blocks the
#   launchd context from the /Volumes/network-ops network volume (the old
#   "-d $BREWDIR" guard silently skipped every scheduled run), so this generates
#   the Brewfile + log LOCALLY and pushes them to the NAS over SSH (key-based,
#   not TCC-gated). Same pattern as control-hub/publishers/publish-pulse.sh.
#   Uses the explicit host spike-chilli.local (not a `nas` ssh alias — may not
#   exist on every Mac). If the NAS is unreachable (away / down), the run is
#   skipped with one line to a local away log; the dump waits until reachable.
#
# Log:      network-ops/logs/brew_<MACHINE>_sync_<YYYY-MM-DD-HHMM>.log  (pushed)
# Away log: ~/Library/Logs/brew-sync/away.log  (skip trail — no dump)
# Rotation: newest 15 runs kept per machine (rotated NAS-side over SSH)
# =============================================================================

NAS_SSH="${BREW_NAS_SSH:-nickleigh@spike-chilli.local}"
NAS_ROOT="/volume1/network-ops"
NAS_BREWDIR="$NAS_ROOT/data/brew-sync"
NAS_LOGDIR="$NAS_ROOT/logs"
SSHNAS(){ ssh -o BatchMode=yes -o ConnectTimeout=8 "$NAS_SSH" "$@"; }
MAX_LOG_FILES=15

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"

# Local staging — never the SMB mount (launchd can always write $HOME).
STAGE="$HOME/.local/state/brew-sync"
mkdir -p "$STAGE"
LOG_FILE="$STAGE/brew_${MACHINE}_sync_$(date '+%Y-%m-%d-%H%M').log"
log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

# push the run log to the NAS (best-effort) + rotate NAS logs; keep a few local.
push_log() {
    SSHNAS "mkdir -p $NAS_LOGDIR && cat > $NAS_LOGDIR/$(basename "$LOG_FILE")" < "$LOG_FILE" 2>/dev/null || true
    SSHNAS "ls -1t $NAS_LOGDIR/brew_${MACHINE}_sync_*.log 2>/dev/null | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f 2>/dev/null" 2>/dev/null || true
    ls -1t "$STAGE"/brew_${MACHINE}_sync_*.log 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Guard: NAS reachable over SSH? (replaces the SMB "-d $BREWDIR" mount check)
# ---------------------------------------------------------------------------
if ! SSHNAS true 2>/dev/null; then
    AWAY_LOG="$HOME/Library/Logs/brew-sync/away.log"
    mkdir -p "$(dirname "$AWAY_LOG")"
    printf '%s  skipped — NAS unreachable over SSH (away or NAS down)\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >> "$AWAY_LOG"
    exit 1
fi

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
    push_log
    exit 1
fi
log "  brew: $BREW"
log "  data: $NAS_SSH:$NAS_BREWDIR"

BREWFILE="$STAGE/Brewfile.$MACHINE"

# ---------------------------------------------------------------------------
# Dump Brewfile locally
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
    push_log
    exit 1
fi

# ---------------------------------------------------------------------------
# Publish Brewfile to the NAS over SSH (single connection, stdin stream)
# ---------------------------------------------------------------------------
if SSHNAS "mkdir -p $NAS_BREWDIR && cat > $NAS_BREWDIR/Brewfile.$MACHINE" < "$BREWFILE" 2>/dev/null; then
    log "✓ published Brewfile.$MACHINE → $NAS_SSH:$NAS_BREWDIR"
else
    log "✗ failed to publish Brewfile to the NAS over SSH"
    push_log
    exit 1
fi

log "━━━ brew-sync.sh complete ━━━"
log "  Brewfile.$MACHINE: $NAS_SSH:$NAS_BREWDIR/Brewfile.$MACHINE"
log "  To install from shared Brewfile: bash /usr/local/bin/brew-bundle-install.sh"
push_log
