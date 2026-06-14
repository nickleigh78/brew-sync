# brew-sync — Claude Code context
Project: Spike & Chilli Home Network
Epic: E2 Mac Utilities
Role: Automated Homebrew maintenance across three Macs
Parent planning: spike-chilli-network/instructions/master-doc.md
Status: PRODUCTION — deployed on NLMacMiniM1, NLMacbookProM3, MZMacMini

---

## What this repo contains

Scripts and launchd plists for Homebrew automation. No sensitive data —
GitHub mirror is appropriate (unlike opnsense-config, mount-nas-locations).

## What this repo does NOT contain

**Brewfiles are data, not code.** They live on the NAS (not here):

```
/Volumes/home/Drive/Projects/Home Network Project/BrewSync/
├── Brewfile                    ← shared curated baseline (manually edited)
├── Brewfile.NLMacMiniM1        ← auto-generated weekly by brew-sync.sh
├── Brewfile.NLMacbookProM3     ← auto-generated weekly by brew-sync.sh
└── Brewfile.MZMacMini          ← auto-generated weekly by brew-sync.sh
```

MacBook (NLMacbookProM3) away-from-home fallback:
```
~/Library/CloudStorage/SynologyDrive-NASHome/Drive/Projects/Home Network Project/BrewSync/
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
- NAS mount required for brew-sync.sh and brew-bundle-install.sh.
  NAS mount system (mount-nas-locations repo) handles this automatically.

## Remotes

- origin: GitHub (public, no sensitive data)
- nas:    ssh://nickleigh@Spike-Chilli/volume1/git/brew-sync.git

## Sibling repos

See master-doc.md for full repo/epic structure. Closely related:
- mount-nas-locations (E2, PRODUCTION) — NAS mounts that brew-sync depends on
- symlink-manager (E2, PRODUCTION) — ~/Links/ symlink routing
