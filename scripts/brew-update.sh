#!/bin/bash
# =============================================================================
# brew-update.sh
# Spike & Chilli Home Network (E2) — Homebrew Auto-Update
# =============================================================================
# Runs daily via launchd (com.user.brewupdate.plist).
# Shared across all three Macs — auto-detects brew path at runtime.
#
# Actions: brew update → brew upgrade → brew cleanup
#
# Does NOT install new packages (see brew-bundle-install.sh).
# Does NOT run brew doctor (noisy in automation — run manually when needed).
# Does NOT use --greedy (would push cask auto-updates to older macOS builds
# on MZMacMini — add per-machine if desired on Apple Silicon only).
#
# MZMacMini note: Intel + permanently older macOS. Individual package upgrade
# failures are expected and non-fatal — logged but script continues.
#
# Logs:
#   ~/Library/Logs/brew-update.log   trimmed to MAX_LOG_LINES each run
#   /tmp/brewupdate.out / .err        launchd stdout/stderr redirect
#
# Manual test:
#   launchctl kickstart gui/$(id -u)/com.user.brewupdate
#   tail -f ~/Library/Logs/brew-update.log
# =============================================================================

LOG_FILE="$HOME/Library/Logs/brew-update.log"
MAX_LOG_LINES=1000

# ---------------------------------------------------------------------------
# Logging — timestamp prefix, always appends
# ---------------------------------------------------------------------------
log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

mkdir -p "$(dirname "$LOG_FILE")"

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"
log "━━━ brew-update.sh starting — $MACHINE ━━━"

# ---------------------------------------------------------------------------
# Detect brew binary — Apple Silicon: /opt/homebrew, Intel: /usr/local
# ---------------------------------------------------------------------------
if   [ -x "/opt/homebrew/bin/brew" ]; then
    BREW="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    BREW="/usr/local/bin/brew"
else
    log "✗ brew not found at /opt/homebrew/bin/brew or /usr/local/bin/brew"
    log "  Is Homebrew installed?"
    exit 1
fi
log "  brew: $BREW"

# ---------------------------------------------------------------------------
# brew update — fetch latest formula/cask metadata from GitHub
# ---------------------------------------------------------------------------
log "→ brew update"
if "$BREW" update >> "$LOG_FILE" 2>&1; then
    log "✓ brew update complete"
else
    log "⚠ brew update exited non-zero — check lines above for detail"
    log "  Continuing (transient network issues are common)"
fi

# ---------------------------------------------------------------------------
# brew upgrade — upgrade installed formulae and casks
# Non-fatal: individual package failures (common on MZMacMini / older macOS)
# are logged and the script continues to cleanup.
# ---------------------------------------------------------------------------
log "→ brew upgrade"
if "$BREW" upgrade >> "$LOG_FILE" 2>&1; then
    log "✓ brew upgrade complete"
else
    log "⚠ brew upgrade exited non-zero (exit $?)"
    log "  On MZMacMini: individual package failures for newer macOS versions"
    log "  are expected and safe to ignore. Review above for specifics."
fi

# ---------------------------------------------------------------------------
# brew cleanup — remove stale downloads and old formula versions
# ---------------------------------------------------------------------------
log "→ brew cleanup"
if "$BREW" cleanup >> "$LOG_FILE" 2>&1; then
    log "✓ brew cleanup complete"
else
    log "⚠ brew cleanup exited non-zero — check above for detail"
fi

# ---------------------------------------------------------------------------
# Log rotation — trim to MAX_LOG_LINES to prevent unbounded growth
# Uses awk to avoid macOS wc -l leading-whitespace issue
# ---------------------------------------------------------------------------
if [ -f "$LOG_FILE" ]; then
    LINE_COUNT=$(awk 'END{print NR}' "$LOG_FILE")
    if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
        tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" \
            && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "  (log trimmed to $MAX_LOG_LINES lines)"
    fi
fi

log "━━━ brew-update.sh complete ━━━"
log ""
