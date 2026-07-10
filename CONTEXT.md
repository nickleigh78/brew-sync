# brew-sync — Claude Code context
Project: Spike & Chilli Home Network
Epic: E2 Mac Utilities
Role: Automated Homebrew maintenance across NLMacMiniM1 and NLMacbookProM3
Parent planning: spike-chilli-network/instructions/master-doc.md
Status: PRODUCTION — deployed on NLMacMiniM1, NLMacbookProM3, MZMacMini

---

## What this repo contains

Scripts and launchd plists for Homebrew automation. No sensitive data —
GitHub mirror is appropriate (unlike opnsense-config, mount-nas-locations).

## What this repo does NOT contain

**Brewfiles are data, not code.** They live on the NAS network-ops share:

```
/Volumes/network-ops/data/brew-sync/
├── Brewfile                    ← shared curated baseline (manually edited)
├── Brewfile.NLMacMiniM1        ← auto-generated weekly by brew-sync.sh
└── Brewfile.NLMacbookProM3     ← auto-generated weekly by brew-sync.sh
```

Brewfile.MZMacMini is not yet migrated to network-ops (MZMacMini deployment
is a separate future session given its older-macOS constraints).

If the MacBook is away from home and /Volumes/network-ops is not mounted,
brew-sync.sh skips the dump and appends one line to a local skip trail:
  ~/Library/Logs/brew-sync/away.log
No Synology Drive fallback — the dump simply waits until home.

## Scripts

| Script | Type | What it does |
|---|---|---|
| `brew-sync.sh` | Automated (weekly) | Dumps per-machine Brewfile to network-ops |
| `brew-update.sh` | Automated (daily) | brew update → upgrade → cleanup |
| `brew-bundle-install.sh` | Manual | Installs shared Brewfile on this machine only |
| `sync-macs.sh` | Manual | Installs shared Brewfile on both Macs via SSH |
| `brew-diff-email.sh` | Automated (weekly) | Diffs both Brewfiles, emails HTML report |
| `migrate-brewfiles.sh` | One-time | Moves Brewfiles from old NAS path to network-ops |

## Logs

All logs go to `/Volumes/network-ops/logs/` using the house convention:

```
brew_<MACHINE>_<task>_<YYYY-MM-DD-HHMM>.log
```

Examples:
```
brew_NLMacMiniM1_sync_2026-07-13-0200.log
brew_NLMacbookProM3_update_2026-07-13-0300.log
brew_NLMacMiniM1_diff_2026-07-13-0400.log
brew_NLMacMiniM1_syncmacs_2026-07-13-1200.log
```

Rotation keeps: sync=15, diff=15, update=20, syncmacs=10 (per machine).

brew-update.sh falls back to `~/Library/Logs/brew-update/` when
network-ops is not mounted (Mac away); brew ops still run, log destination
changes. Rotation applies to whichever dir is active.

Manual test (check most recent log):
```
ls -1t /Volumes/network-ops/logs/brew_NLMacMiniM1_sync_*.log | head -1 | xargs tail
```

## Key constraints

- **MZMacMini is Intel and permanently on an older macOS** (cannot upgrade
  to match Apple Silicon macOS versions). Individual brew upgrade failures
  are expected and non-fatal. Curate the shared Brewfile to exclude packages
  requiring a newer macOS.
- brew path auto-detected at runtime: /opt/homebrew (Apple Silicon) vs
  /usr/local (Intel). Scripts work identically on all three Macs.
- Scripts deployed to /usr/local/bin/ (fixed path, no username in path —
  consistent with the mount-nas-locations pattern).
- Plists deployed to ~/Library/LaunchAgents/ on each Mac.
- /Volumes/network-ops required for brew-sync.sh, brew-bundle-install.sh,
  sync-macs.sh, and brew-diff-email.sh. mount-nas-locations handles mounting.
- sync-macs.sh requires network-ops mounted on BOTH Macs (each reads the
  shared Brewfile from its own local mount). SSH password required.

## Remotes

- origin: GitHub (public, no sensitive data) — nickleigh78/brew-sync
- nas:    ssh://nickleigh@spike-chilli.local/volume1/git/brew-sync.git

## Sibling repos

See master-doc.md for full repo/epic structure. Closely related:
- mount-nas-locations (E2, PRODUCTION) — mounts /Volumes/network-ops
- symlink-manager (E2, PRODUCTION) — ~/Links/ symlink routing
