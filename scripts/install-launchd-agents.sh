#!/bin/bash
# =============================================================================
# install-launchd-agents.sh — deploy the brew-sync launchd user agents, quarantine-safe
# =============================================================================
# WHY THIS EXISTS (2026-09-21):
#   plists copied from a NAS share or a download carry the com.apple.quarantine
#   extended attribute, and launchd REFUSES to load a quarantined LaunchAgent.
#   After the macOS 27 upgrade this silently broke com.user.brewsync and
#   com.user.brewupdate on NLMacMiniM1 (they never loaded). The failure mode is
#   maximally misleading: `launchctl bootstrap` -> "Bootstrap failed: 5:
#   Input/output error", IDENTICAL under sudo (looks like permissions),
#   `launchctl enable` doesn't help, and `launchctl print gui/$UID/<label>` says
#   the service was never registered (looks like a stale registration). The tell
#   is a trailing `@` in `ls -la` / an `xattr` listing on the plist. Fix is one
#   line: strip the xattr before loading. Because the fleet is deployed by copying
#   identical plists, this is LATENT on every deploy + every OS upgrade on all
#   three Macs. This installer bakes the fix in.
#
# SCOPE: installs the launchd USER AGENTS (plists) quarantine-safe and reloads
#   them, choosing the right set per machine (Mini has no brewdiff). Run as the
#   logged-in user — NOT sudo. The /usr/local/bin script copies are separate sudo
#   steps (see README "Deploying script updates").
#
# Idempotent: safe to re-run. Usage: ./install-launchd-agents.sh
# =============================================================================
set -eu

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LA="$HOME/Library/LaunchAgents"
mkdir -p "$LA"

me="$(scutil --get ComputerName 2>/dev/null | tr '[:upper:]' '[:lower:]')"
# MZMacMini is ISOLATED (security issue, 2026-09-22) — OUT OF SCOPE for deployment
# until re-enabled (spike-chilli-network/decisions/mac-ssh-mesh.md). Its arm is kept
# below so re-onboarding is a one-line un-comment, but for now it refuses to install.
case "$me" in
  nlmacbookprom3)          PLISTS="com.user.brewupdate com.user.brewsync com.user.brewdiff" ;;  # MacBook sends the diff
  nlmacminim1)             PLISTS="com.user.brewupdate com.user.brewsync" ;;                     # no brewdiff
  mzmacmini)               echo "MZMacMini is ISOLATED (out of scope until re-enabled) — refusing to deploy." >&2
                           echo "  Re-enable: see spike-chilli-network/decisions/mac-ssh-mesh.md, then set PLISTS here." >&2
                           exit 0 ;;  # future: PLISTS="com.user.brewupdate com.user.brewsync"
  *) echo "warning: unrecognised machine '$me' — installing brewupdate + brewsync only" >&2
     PLISTS="com.user.brewupdate com.user.brewsync" ;;
esac

for label in $PLISTS; do
  src="$REPO/launchd/$label.plist"
  dest="$LA/$label.plist"
  [ -f "$src" ] || { echo "error: source plist not found: $src" >&2; exit 1; }
  cp "$src" "$dest"
  # THE LOAD-BEARING LINE. launchd refuses a quarantined agent; no-op when absent.
  xattr -d com.apple.quarantine "$dest" 2>/dev/null || true
  launchctl unload "$dest" 2>/dev/null || true
  launchctl load "$dest"
  echo "loaded $label (quarantine stripped)"
done

echo "verify:  launchctl list | grep com.user.brew   (exit code 0 in col 2 = last run OK)"
