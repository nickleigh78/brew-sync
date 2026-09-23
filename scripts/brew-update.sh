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
# TRANSPORT (2026-09-24, T31): FDA-free SSH log push, not the SMB mount. The
#   old "-d /Volumes/network-ops" guard only tested whether the mount was
#   *visible*, not whether launchd could *write* to it — macOS TCC blocks the
#   launchd context from the network volume, so `brew ... >> $LOG_FILE`
#   opened an unwritable log BEFORE brew ran and the whole pipeline silently
#   no-op'd (exit 1, `Operation not permitted`; broken since ~mid-July).
#   Ported the brew-sync.sh (2026-07-28) fix: log LOCALLY always (launchd can
#   always write $HOME), run brew update/upgrade/cleanup against that local
#   log, then push the finished log to the NAS over SSH (key-based, not
#   TCC-gated) as a best-effort step at the end. brew itself never depends on
#   the NAS being mounted or reachable — only the log copy does.
#
# Log:      network-ops/logs/brew_<MACHINE>_update_<YYYY-MM-DD-HHMM>.log (pushed)
#           Local copy always kept at ~/.local/state/brew-update/ regardless.
# Rotation: newest 20 runs kept per machine (NAS-side and local both)
# =============================================================================

NAS_SSH="${BREW_NAS_SSH:-nickleigh@spike-chilli.local}"
NAS_LOGDIR="/volume1/network-ops/logs"
SSHNAS(){ ssh -o BatchMode=yes -o ConnectTimeout=8 "$NAS_SSH" "$@"; }
MAX_LOG_FILES=20

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"

# Local staging — never the SMB mount (launchd can always write $HOME).
STAGE="$HOME/.local/state/brew-update"
mkdir -p "$STAGE"
LOG_FILE="$STAGE/brew_${MACHINE}_update_$(date '+%Y-%m-%d-%H%M').log"
log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

# push the run log to the NAS (best-effort) + rotate NAS logs and local copies.
# Best-effort by design: brew update/upgrade/cleanup already ran against the
# local log by the time this is called, so a NAS/SSH outage never blocks them.
push_log() {
    SSHNAS "mkdir -p $NAS_LOGDIR && cat > $NAS_LOGDIR/$(basename "$LOG_FILE")" < "$LOG_FILE" 2>/dev/null || true
    SSHNAS "ls -1t $NAS_LOGDIR/brew_${MACHINE}_update_*.log 2>/dev/null | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f 2>/dev/null" 2>/dev/null || true
    ls -1t "$STAGE"/brew_${MACHINE}_update_*.log 2>/dev/null | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f 2>/dev/null || true
}

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
    push_log
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

log "━━━ brew-update.sh complete ━━━"
log ""
push_log
