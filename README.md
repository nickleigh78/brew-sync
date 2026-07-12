# brew-sync
**Spike & Chilli Home Network · E2 Mac Utilities**

Automated Homebrew maintenance across three Macs. Keeps formulae and
casks current, snapshots each machine's Brewfile weekly to the NAS,
syncs a curated shared Brewfile across the two Apple Silicon Macs,
and sends a weekly HTML diff email summarising any divergence.

---

## Machines

| Machine | Owner | Arch | macOS | Brew path |
|---|---|---|---|---|
| NLMacMiniM1 | Nick | Apple Silicon | current | `/opt/homebrew/bin/brew` |
| NLMacbookProM3 | Nick | Apple Silicon | current | `/opt/homebrew/bin/brew` |
| MZMacMini | Marty | Intel | older (permanent) | `/usr/local/bin/brew` |

Scripts auto-detect the brew path at runtime. **MZMacMini will always
be on an older macOS** (Intel CPU; cannot upgrade to match Apple Silicon
versions). Individual upgrade failures are expected and non-fatal.
Curate the shared Brewfile to exclude packages requiring newer macOS.

---

## Scripts

| Script | Trigger | Machine(s) | What it does |
|---|---|---|---|
| `brew-update.sh` | launchd weekly Wed 01:00 | all 3 | update + upgrade + cleanup |
| `brew-sync.sh` | launchd weekly Wed 02:00 | all 3 | dump `Brewfile.<MachineName>` to NAS |
| `brew-bundle-install.sh` | **manual only** | all 3 | install from shared Brewfile on this Mac |
| `sync-macs.sh` | **manual only** | MacBook or Mini | install shared Brewfile on BOTH Macs via SSH |
| `brew-diff-email.sh` | launchd weekly Wed 03:00 | MacBook only | diff both Brewfiles, send HTML email |

The three scheduled jobs form one weekly pipeline on **Wednesday**, staggered
one hour apart so each stage feeds the next: **01:00** update/upgrade →
**02:00** Brewfile snapshot → **03:00** diff email. It runs mid-week (not
Sunday) to keep it off the Sunday NAS/opnsense-backup night and so any
upgrade breakage surfaces on a working morning rather than over a weekend.
| `migrate-brewfiles.sh` | one-time (done) | — | moved Brewfiles from old NAS path to network-ops |

---

## Code vs data

This repo contains **code** (scripts, plists). Brewfiles are **data** and
live on the NAS network-ops share:

```
/Volumes/network-ops/data/brew-sync/
├── Brewfile                    ← shared curated baseline — edit manually
├── Brewfile.NLMacMiniM1        ← auto-generated weekly by brew-sync.sh
└── Brewfile.NLMacbookProM3     ← auto-generated weekly by brew-sync.sh
```

`/Volumes/network-ops` is a NAS share mounted by `mount-nas-locations`.
It is not backed up — contents are regenerable.

If the MacBook is away from home and `/Volumes/network-ops` is not
mounted, `brew-sync.sh` skips the dump and logs one line to
`~/Library/Logs/brew-sync/away.log`. `brew-update.sh` still runs
(update/upgrade/cleanup) but logs locally to `~/Library/Logs/brew-update/`.

---

## Logs

All logs go to `/Volumes/network-ops/logs/` using the house naming convention:

```
brew_<MACHINE>_<task>_<YYYY-MM-DD-HHMM>.log
```

Rotation: `sync`=15, `update`=20, `diff`=15, `syncmacs`=10 per machine.

`brew-update.sh` falls back to `~/Library/Logs/brew-update/` when
network-ops is not mounted; rotation applies to whichever dir is active.

---

## Remotes

| Remote | URL |
|---|---|
| `origin` | `https://github.com/nickleigh78/brew-sync.git` |
| `nas` | `ssh://nickleigh@spike-chilli.local/volume1/git/brew-sync.git` |

---

## Deployment status

| Machine | Scripts | Plists loaded | Notes |
|---|---|---|---|
| NLMacbookProM3 | all 6 in `/usr/local/bin/` | brewsync, brewupdate, brewdiff | Primary machine; diff email runs here |
| NLMacMiniM1 | 4 in `/usr/local/bin/` | brewsync, brewupdate | No brew-diff-email (MacBook sends) |
| MZMacMini | brew-sync.sh, brew-update.sh | brewsync, brewupdate | scp deploy only — no git repo |

SSH key auth is configured between MacBook and Mini (no password prompts).

---

## Deploying script updates

### NLMacbookProM3 / NLMacMiniM1

```bash
# After pulling latest changes on MacBook:
sudo cp scripts/brew-update.sh         /usr/local/bin/brew-update.sh
sudo cp scripts/brew-sync.sh           /usr/local/bin/brew-sync.sh
sudo cp scripts/brew-bundle-install.sh /usr/local/bin/brew-bundle-install.sh
sudo cp scripts/sync-macs.sh           /usr/local/bin/sync-macs.sh
sudo cp scripts/brew-diff-email.sh     /usr/local/bin/brew-diff-email.sh
sudo chmod 755 /usr/local/bin/brew-{update,sync,bundle-install,diff-email}.sh \
               /usr/local/bin/sync-macs.sh

# Deploy to Mini via scp (no git repo on Mini):
scp scripts/brew-update.sh scripts/brew-sync.sh \
    scripts/brew-bundle-install.sh scripts/sync-macs.sh \
    nickleigh@NLMacMiniM1.local:/tmp/
ssh -t nickleigh@NLMacMiniM1.local \
    "sudo cp /tmp/brew-update.sh /tmp/brew-sync.sh \
             /tmp/brew-bundle-install.sh /tmp/sync-macs.sh \
             /usr/local/bin/ && \
     sudo chmod 755 /usr/local/bin/brew-{update,sync,bundle-install}.sh \
                    /usr/local/bin/sync-macs.sh"
```

### MZMacMini (Intel — scp only)

```bash
scp scripts/brew-update.sh scripts/brew-sync.sh \
    nickleigh@MZMacMini.local:/tmp/
ssh -t nickleigh@MZMacMini.local \
    "sudo cp /tmp/brew-update.sh /tmp/brew-sync.sh /usr/local/bin/ && \
     sudo chmod 755 /usr/local/bin/brew-{update,sync}.sh"
```

---

## Loading launchd agents (first-time or after plist changes)

```bash
# MacBook / Mini (adjust list per machine — Mini has no brewdiff)
cp launchd/com.user.brewupdate.plist ~/Library/LaunchAgents/
cp launchd/com.user.brewsync.plist   ~/Library/LaunchAgents/
cp launchd/com.user.brewdiff.plist   ~/Library/LaunchAgents/  # MacBook only

launchctl load ~/Library/LaunchAgents/com.user.brewupdate.plist
launchctl load ~/Library/LaunchAgents/com.user.brewsync.plist
launchctl load ~/Library/LaunchAgents/com.user.brewdiff.plist  # MacBook only

# Verify
launchctl list | grep com.user.brew
```

---

## Ongoing operations

### Check logs

```bash
ls -1t /Volumes/network-ops/logs/brew_$(scutil --get ComputerName)_*.log | head -5
tail -50 $(ls -1t /Volumes/network-ops/logs/brew_$(scutil --get ComputerName)_sync_*.log | head -1)
```

### Edit shared Brewfile

```bash
open /Volumes/network-ops/data/brew-sync/Brewfile
# or: nano /Volumes/network-ops/data/brew-sync/Brewfile
```

### Sync shared Brewfile to both Macs

```bash
bash /usr/local/bin/sync-macs.sh
```

### Install from shared Brewfile (this Mac only)

```bash
bash /usr/local/bin/brew-bundle-install.sh
```

### VS Code extensions

VS Code extensions are included in the shared Brewfile as `vscode "..."` lines.
For these to work on a Mac, VS Code must be installed via Homebrew:

```bash
brew list --cask | grep visual-studio-code  # confirm it's brew-managed
# If not: brew reinstall --cask visual-studio-code
```

### Reloading agents after plist changes

```bash
launchctl unload ~/Library/LaunchAgents/com.user.brewupdate.plist
launchctl load   ~/Library/LaunchAgents/com.user.brewupdate.plist
```

---

## MZMacMini notes

- Intel, permanently on an older macOS — individual upgrade failures non-fatal
- No git repo — deploy scripts via scp (see Deploying section above)
- Does not mount `/Volumes/network-ops` (Nick-only share)
- `brew-sync.sh` and `brew-update.sh` only; no sync-macs or diff email
- Brewfiles for MZMacMini not yet migrated to network-ops (separate future task)
