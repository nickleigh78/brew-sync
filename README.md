# brew-sync
**Spike & Chilli Home Network · E2 Mac Utilities**

Automated Homebrew maintenance across three Macs. Keeps formulae and
casks current, snapshots each machine's Brewfile weekly to the NAS, and
provides a manual tool for installing a curated shared package baseline.

---

## Machines

| Machine | Owner | Arch | macOS | Brew path |
|---|---|---|---|---|
| NLMacMiniM1 | Nick | Apple Silicon | current | `/opt/homebrew/bin/brew` |
| NLMacbookProM3 | Nick | Apple Silicon | current | `/opt/homebrew/bin/brew` |
| MZMacMini | Marty | Intel | older (permanent) | `/usr/local/bin/brew` |

Scripts auto-detect the brew path at runtime. **MZMacMini will always
be on an older macOS** (Intel CPU; cannot upgrade to match Apple Silicon
versions). Individual package upgrade failures are expected and non-fatal.
Curate the shared Brewfile accordingly.

---

## How it works

| Script | Trigger | What it does |
|---|---|---|
| `brew-update.sh` | launchd daily 03:00 | update + upgrade + cleanup |
| `brew-sync.sh` | launchd weekly Sun 02:00 | dump `Brewfile.<MachineName>` to NAS |
| `brew-bundle-install.sh` | **manual only** | install from shared Brewfile |

### Code vs data

This repo contains **code** (scripts, plists). Brewfiles are **data** and
live on the NAS:

```
/Volumes/home/Drive/Projects/Home Network Project/BrewSync/
├── Brewfile                    ← shared curated baseline — edit this manually
├── Brewfile.NLMacMiniM1        ← auto-generated weekly
├── Brewfile.NLMacbookProM3     ← auto-generated weekly
└── Brewfile.MZMacMini          ← auto-generated weekly
```

MacBook fallback when away from home:
```
~/Library/CloudStorage/SynologyDrive-NASHome/Drive/
    Projects/Home Network Project/BrewSync/
```

---

## Remotes

| Remote | URL |
|---|---|
| `origin` | `https://github.com/<username>/brew-sync` |
| `nas` | `ssh://nickleigh@Spike-Chilli/volume1/git/brew-sync.git` |

---

## One-time setup (run once from NLMacMiniM1)

### 1. Create NAS BrewSync data folder

```bash
mkdir -p "/Volumes/home/Drive/Projects/Home Network Project/BrewSync"
touch "/Volumes/home/Drive/Projects/Home Network Project/BrewSync/Brewfile"
```

Edit the shared `Brewfile` to your curated common package list. Start
lean — add packages that all three Macs should share. Exclude anything
that requires a macOS version newer than MZMacMini can run.

### 2. Create NAS bare remote

```bash
ssh nickleigh@Spike-Chilli "git init --bare /volume1/git/brew-sync.git"
```

### 3. Clone the repo (or init from this directory)

```bash
cd ~/Projects/Home-Network
git clone https://github.com/<username>/brew-sync.git
# or if starting from scratch:
git init brew-sync && cd brew-sync
git remote add origin https://github.com/<username>/brew-sync.git
git remote add nas ssh://nickleigh@Spike-Chilli/volume1/git/brew-sync.git
```

---

## Deployment — per Mac

Run these steps on each Mac: NLMacMiniM1, NLMacbookProM3, MZMacMini.

### 1. Deploy scripts to /usr/local/bin/

```bash
sudo cp scripts/brew-update.sh         /usr/local/bin/brew-update.sh
sudo cp scripts/brew-sync.sh           /usr/local/bin/brew-sync.sh
sudo cp scripts/brew-bundle-install.sh /usr/local/bin/brew-bundle-install.sh
sudo chmod 755 \
    /usr/local/bin/brew-update.sh \
    /usr/local/bin/brew-sync.sh \
    /usr/local/bin/brew-bundle-install.sh
```

### 2. Load launchd agents

```bash
cp launchd/com.user.brewupdate.plist ~/Library/LaunchAgents/
cp launchd/com.user.brewsync.plist   ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.user.brewupdate.plist
launchctl load ~/Library/LaunchAgents/com.user.brewsync.plist
```

### 3. Verify agents loaded

```bash
launchctl list | grep -E 'brew(update|sync)'
```

Expected: two rows with PID (if running) or `-` (waiting for schedule).

### 4. Test immediately

```bash
# Test update (runs brew update + upgrade + cleanup)
launchctl kickstart gui/$(id -u)/com.user.brewupdate
sleep 5 && tail -20 ~/Library/Logs/brew-update.log

# Test sync (requires NAS mounted)
launchctl kickstart gui/$(id -u)/com.user.brewsync
sleep 10 && tail -20 ~/Library/Logs/brew-sync.log
```

Expected after sync: `Brewfile.<ComputerName>` appears in the NAS BrewSync folder.

### 5. First manual sync

```bash
bash /usr/local/bin/brew-sync.sh
ls "/Volumes/home/Drive/Projects/Home Network Project/BrewSync/"
```

---

## Ongoing operations

### Checking logs

```bash
tail -50 ~/Library/Logs/brew-update.log
tail -50 ~/Library/Logs/brew-sync.log
```

### Installing from the shared Brewfile

```bash
# Edit the shared Brewfile first (on NAS, accessible from any Mac):
open "/Volumes/home/Drive/Projects/Home Network Project/BrewSync/Brewfile"

# Then install on whichever Mac you want to add packages to:
bash /usr/local/bin/brew-bundle-install.sh
```

### Updating scripts after repo changes

Re-run the `sudo cp` block from step 1 on each Mac. Launchd agents do not
need to be reloaded unless the plist itself changed.

### Reloading agents after plist changes

```bash
launchctl unload ~/Library/LaunchAgents/com.user.brewupdate.plist
launchctl load   ~/Library/LaunchAgents/com.user.brewupdate.plist

launchctl unload ~/Library/LaunchAgents/com.user.brewsync.plist
launchctl load   ~/Library/LaunchAgents/com.user.brewsync.plist
```

---

## MZMacMini notes

Marty's Mac Mini is Intel and permanently on an older macOS version.
When deploying there:

- `brew upgrade` will warn or fail on individual packages that have
  dropped support for older macOS. This is logged and non-fatal.
- Curate the shared `Brewfile` to exclude packages that require newer
  macOS. Add a comment in the Brewfile noting the exclusion.
- MAS (Mac App Store) entries in the shared Brewfile require Marty's
  Apple ID — remove or exclude these if they differ from Nick's.
