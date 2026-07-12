# brew-sync — sync-macs + weekly diff email + --describe fix (CC brief)

**Job:** `brew-sync-syncmacs`
**Mode:** Autonomous with one halt
**Author:** Claude.ai (architect)
**Executor:** Claude Code (implementor)
**Target machine:** NLMacMiniM1 (deploys local to Mac Mini; MacBook deploy is a separate manual step after this brief)
**Status when authored:** drafted, parked pending SSH host key fix (see Pre-flight PF5)

---

## Resume line

```
New session: cat ~/Projects/Home-Network/brew-sync/SYNCMACS-PROGRESS.md, resume at the block it names.
```

If `SYNCMACS-PROGRESS.md` does not yet exist, start from Pre-flight.

---

## LOCKED DECISIONS (do not re-ask)

- **Repo:** `~/Projects/Home-Network/brew-sync/`
- **Remotes:**
  - `origin` = GitHub (nickleigh78/brew-sync, PUBLIC)
  - `nas` = `ssh://nickleigh@spike-chilli/volume1/git/brew-sync.git`
  - Both must succeed at Block E.
- **sync-macs.sh:** manual-use script, SSHes to MacBook + runs locally on Mac Mini. Bypasses the brew bundle interactive prompt by calling `brew bundle install` directly (no `--yes` flag needed). Never automated.
- **Weekly diff email:** launchd-scheduled Sunday 04:00 (2 hours after brew-sync at 02:00). Reads both Brewfiles from NAS — no SSH required for the email script itself.
- **Email transport:** osascript to Mail.app (no SMTP config; uses Nick's existing Mail.app account).
- **Nick's email:** `nick@nickleigh.info`
- **Brewfile location (NAS):** `/Volumes/home/Drive/Projects/Home Network Project/BrewSync/`
- **Per-Mac Brewfile naming:** `Brewfile.NLMacMiniM1`, `Brewfile.NLMacbookProM3`
- **launchd plist label:** `com.user.brewdiff`
- **Deploy paths:**
  - Scripts → `/usr/local/bin/` (sudo cp pattern)
  - Plist → `~/Library/LaunchAgents/`
- **Log paths:** `~/Library/Logs/sync-macs.log`, `~/Library/Logs/brew-diff-email.log`
- **Also fixed in this brief:** drop deprecated `--describe` flag from `scripts/brew-sync.sh` (Homebrew 6.x deprecation, flagged in master-doc v1.11 changelog).
- **MacBook deploy:** out of scope for this brief — same sudo cp pattern, separate manual step after this brief completes.
- **PQ-KEX SSH warnings** on push to NAS are benign, ignorable.

---

## Pre-flight checks

Before Block A, CC must verify and report:

1. **PF1:** `pwd` resolves to `~/Projects/Home-Network/brew-sync/`
2. **PF2:** Working tree clean (`git status --porcelain` returns empty)
3. **PF3:** Both remotes configured:
   ```bash
   git remote -v | grep -E "^(origin|nas)\s"
   ```
   Expect: 2 lines for origin (fetch + push, GitHub URL) and 2 for nas (fetch + push, NAS URL).
4. **PF4:** Shared Brewfile folder reachable from Mac Mini:
   ```bash
   ls -la "/Volumes/home/Drive/Projects/Home Network Project/BrewSync/"
   ```
   Expect: directory listing, both `Brewfile.NLMacMiniM1` and `Brewfile.NLMacbookProM3` present.
5. **PF5:** SSH host key for MacBook is in `~/.ssh/known_hosts`:
   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=5 nickleigh@NLMacbookProM3.local "echo OK"
   ```
   Expected: `OK` (after benign warnings). If `Host key verification failed`, HALT. Resolve with:
   ```bash
   ssh-keyscan -H NLMacbookProM3.local >> ~/.ssh/known_hosts
   ```
   then retry. If still failing, the MacBook is unreachable (offline/sleep/no Bonjour) — halt and report; do not proceed without SSH working, Block B requires it.
6. **PF6:** Mail.app is configured with at least one outgoing account:
   ```bash
   osascript -e 'tell application "Mail" to count of accounts'
   ```
   Expect: integer ≥ 1.

If any pre-flight check fails, HALT and report. Do not proceed.

---

## Blocks

### Block A — fix `--describe` deprecation in `scripts/brew-sync.sh`

```bash
cd ~/Projects/Home-Network/brew-sync/
```

Edit `scripts/brew-sync.sh`:
- Remove `--describe` flag from the `brew bundle dump` invocation
- Remove the comment line that documents `--describe` if present

The flag was a cosmetic addition (added human-readable descriptions to the Brewfile); Homebrew 6.x deprecated it and `brew bundle dump` writes the file without it.

**Gate A:**
```bash
grep --color=never "--describe" scripts/brew-sync.sh; echo "exit: $?"
```
Expect: `exit: 1` (grep found nothing, which means the flag is gone).

Update `SYNCMACS-PROGRESS.md`: Block A complete, diff summary recorded.

### Block B — add `scripts/sync-macs.sh`

Create `scripts/sync-macs.sh` — manual-use only, never automated.

Required behaviour:
1. Read the shared Brewfile path from NAS — fail clearly if not mounted
2. Pre-flight: `ssh -o BatchMode=yes -o ConnectTimeout=5 nickleigh@NLMacbookProM3.local "echo ok"` — exit clearly if unreachable
3. SSH to MacBook and run:
   ```
   brew bundle install --file="/Volumes/home/Drive/Projects/Home Network Project/BrewSync/Brewfile.NLMacbookProM3" --no-upgrade --verbose
   ```
4. Run the same locally on Mac Mini against `Brewfile.NLMacMiniM1`
5. Log results to `~/Library/Logs/sync-macs.log` with timestamps
6. Exit non-zero on any failure (so it surfaces clearly when invoked)

Header conventions:
```bash
#!/usr/bin/env bash
set -euo pipefail
# sync-macs.sh — MANUAL USE ONLY
# Syncs Homebrew state across both Macs from the shared Brewfiles on NAS.
# Invocation: bash /usr/local/bin/sync-macs.sh
```

**Gate B:**
```bash
test -f scripts/sync-macs.sh && echo "exists: yes" || echo "exists: no"
bash -n scripts/sync-macs.sh && echo "syntax: OK" || echo "syntax: FAIL"
```
Expect: `exists: yes`, `syntax: OK`.

Update `SYNCMACS-PROGRESS.md`: Block B complete.

### Block C — add `scripts/brew-diff-email.sh` + `launchd/com.user.brewdiff.plist`

Create `scripts/brew-diff-email.sh`. Required behaviour:

1. Verify both Brewfiles exist on NAS; if either missing, log to `~/Library/Logs/brew-diff-email.log` and exit gracefully (non-error — the cron should not panic over a missing NAS mount).
2. Run `diff` on `Brewfile.NLMacMiniM1` vs `Brewfile.NLMacbookProM3`.
3. Compose email — recipient `nick@nickleigh.info`:
   - Subject: `Weekly Brew Diff — NLMacMiniM1 vs NLMacbookProM3 — YYYY-MM-DD`
   - Body structure:
     ```
     Lines starting < = Mac Mini only
     Lines starting > = MacBook only

     Known acceptable differences (safe to ignore):
     - cairo, tcl-tk: MacBook auto-dependencies
     - libspatialite: Mac Mini GIS tool (intentional)
     - Ordering differences for chromaprint, e2fsprogs, exiftool: on both machines

     --- DIFF ---
     [full diff output]

     To sync manually: bash /usr/local/bin/sync-macs.sh
     ```
4. Send via `osascript` to Mail.app (will launch Mail if not running).
5. If diff is empty (machines identical): send a short "no differences" email (subject + body confirming sync state).
6. Log every run to `~/Library/Logs/brew-diff-email.log` with start time, diff size, send result.

Create `launchd/com.user.brewdiff.plist`:
- Label: `com.user.brewdiff`
- ProgramArguments: `/bin/bash /usr/local/bin/brew-diff-email.sh`
- StartCalendarInterval: Sunday (Weekday=0), Hour=4, Minute=0
- ThrottleInterval: 600
- StandardOutPath: `/tmp/brewdiff.out`
- StandardErrorPath: `/tmp/brewdiff.err`
- RunAtLoad: false (don't fire on initial load — wait for Sunday)

**Gate C:**
```bash
test -f scripts/brew-diff-email.sh && echo "script: present"
bash -n scripts/brew-diff-email.sh && echo "script syntax: OK"
test -f launchd/com.user.brewdiff.plist && echo "plist: present"
plutil -lint launchd/com.user.brewdiff.plist
grep -c "com.user.brewdiff" launchd/com.user.brewdiff.plist
```
Expect: present, OK, present, "OK" from plutil, count ≥ 1.

Update `SYNCMACS-PROGRESS.md`: Block C complete.

### Block D — HALT (single halt — POINT OF NO RETURN)

Print to terminal:

```
═══════════════════════════════════════════════════════════════
brew-sync-syncmacs HALT — confirmation required before deploy
═══════════════════════════════════════════════════════════════

State so far (all local-only, all reversible):
  Block A: --describe fix applied to scripts/brew-sync.sh
  Block B: scripts/sync-macs.sh authored, syntax OK
  Block C: scripts/brew-diff-email.sh authored, syntax OK
           launchd/com.user.brewdiff.plist authored, plist valid

After this halt, CC will execute without further confirmation:

  Block D: sudo cp the 3 scripts to /usr/local/bin/
           cp the plist to ~/Library/LaunchAgents/
           launchctl load the brewdiff agent
           Trigger one test run via launchctl kickstart
           Verify email arrives in nick@nickleigh.info
  Block E: git add/commit/push to both origin (GitHub) and nas (NAS)

Type 'PROCEED' to continue, anything else to abort.
═══════════════════════════════════════════════════════════════
```

If response is anything other than literal `PROCEED`, halt cleanly. `SYNCMACS-PROGRESS.md` records the abort with timestamp.

### Block E1 — deploy to NLMacMiniM1

```bash
sudo cp scripts/brew-sync.sh /usr/local/bin/brew-sync.sh
sudo cp scripts/sync-macs.sh /usr/local/bin/sync-macs.sh
sudo cp scripts/brew-diff-email.sh /usr/local/bin/brew-diff-email.sh
sudo chmod 755 /usr/local/bin/brew-sync.sh \
                /usr/local/bin/sync-macs.sh \
                /usr/local/bin/brew-diff-email.sh

cp launchd/com.user.brewdiff.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.user.brewdiff.plist
launchctl list | grep brewdiff
```

Expect `launchctl list | grep brewdiff` to show a line containing `com.user.brewdiff`.

Test the email manually:
```bash
launchctl kickstart gui/$(id -u)/com.user.brewdiff
sleep 10
tail -30 ~/Library/Logs/brew-diff-email.log
```

The log should show: start timestamp, diff result (empty or full diff), email send confirmation. No `✗` or `ERROR` lines.

**Gate E1:**
- `launchctl list | grep brewdiff` returns non-empty
- `~/Library/Logs/brew-diff-email.log` exists with one entry
- Nick confirms email arrived at `nick@nickleigh.info`

Update `SYNCMACS-PROGRESS.md`: Block E1 complete, log snippet recorded, email-arrived flag captured from Nick.

### Block E2 — commit and push

```bash
cd ~/Projects/Home-Network/brew-sync/
git status
git add scripts/brew-sync.sh \
        scripts/sync-macs.sh \
        scripts/brew-diff-email.sh \
        launchd/com.user.brewdiff.plist \
        SYNCMACS-PROGRESS.md
git status                                # confirm only the 5 files staged
git commit -m "feat: sync-macs.sh, weekly brew diff email, fix --describe deprecation

- scripts/sync-macs.sh: manual cross-Mac brew bundle install via SSH
- scripts/brew-diff-email.sh: weekly Sunday 04:00 diff to nick@nickleigh.info
- launchd/com.user.brewdiff.plist: launchd agent for weekly schedule
- scripts/brew-sync.sh: drop deprecated --describe flag (Homebrew 6.x)

Resolves the v1.11 master-doc follow-up note."

git push origin main
git push nas main
```

**Gate E2:**
```bash
git status --porcelain | wc -l           # expect 0
git log @{u}..HEAD --oneline | wc -l     # expect 0 (in sync with current upstream — origin)
# Check nas remote also caught up:
git fetch nas
git log nas/main..HEAD --oneline | wc -l # expect 0
```

All three should be 0.

Update `SYNCMACS-PROGRESS.md`: Block E2 complete, both pushes succeeded.

### Block F — final ledger + cleanup

Update `SYNCMACS-PROGRESS.md` with final state:
- All blocks DONE
- Local commit hash
- GitHub push confirmation
- NAS push confirmation
- launchd agent status
- Email-arrived flag
- All gate results

```bash
git add SYNCMACS-PROGRESS.md
git commit -m "brew-sync-syncmacs: progress ledger final"
git push origin main
git push nas main
```

---

## Self-check gates (run at end of Block F)

CC must execute all and report results in `SYNCMACS-PROGRESS.md`. All must PASS.

```bash
# Gate 1: brew-sync working tree clean
cd ~/Projects/Home-Network/brew-sync/
git status --porcelain | wc -l                              # expect 0

# Gate 2: brew-sync in sync with GitHub (origin)
git log @{u}..HEAD --oneline | wc -l                        # expect 0

# Gate 3: brew-sync in sync with NAS (nas)
git fetch nas
git log nas/main..HEAD --oneline | wc -l                    # expect 0

# Gate 4: --describe gone from scripts/brew-sync.sh and from deployed copy
grep --color=never "--describe" scripts/brew-sync.sh; echo "repo exit: $?"   # expect 1
grep --color=never "--describe" /usr/local/bin/brew-sync.sh; echo "deploy exit: $?"  # expect 1

# Gate 5: all 3 scripts deployed and executable
ls -la /usr/local/bin/brew-sync.sh /usr/local/bin/sync-macs.sh /usr/local/bin/brew-diff-email.sh

# Gate 6: launchd agent loaded
launchctl list | grep brewdiff                              # expect non-empty

# Gate 7: log shows the test run
test -s ~/Library/Logs/brew-diff-email.log && echo "log: non-empty"

# Gate 8: email confirmed (Nick reports)
```

---

## Done criteria

- All blocks marked DONE in `SYNCMACS-PROGRESS.md`
- All 8 self-check gates PASS
- No uncommitted changes in brew-sync repo
- Both pushes succeeded (origin + nas)
- Test email arrived at `nick@nickleigh.info`
- Three scripts deployed to `/usr/local/bin/`, executable
- launchd agent `com.user.brewdiff` loaded and listed
- `SYNCMACS-PROGRESS.md` final state committed and pushed

---

## Abort / rollback

If failure occurs at any point:

**Before Block D halt:** local-only changes, no system effects. Revert with `git stash; git checkout scripts/brew-sync.sh` or similar. Untracked new files can be `rm`'d.

**After Block D halt (deploy started):**
- Remove deployed scripts: `sudo rm /usr/local/bin/{brew-sync,sync-macs,brew-diff-email}.sh` (note: brew-sync.sh existed before this brief — only remove if you have a backup, or restore from repo before this brief's commit)
- Unload launchd agent: `launchctl unload ~/Library/LaunchAgents/com.user.brewdiff.plist && rm ~/Library/LaunchAgents/com.user.brewdiff.plist`
- Revert repo: `git reset --hard <pre-brief-HEAD>`

**After Block E2 (pushed):**
- Revert commit on origin: `git reset --hard HEAD~1 && git push --force-with-lease origin main` (use only if absolutely necessary; force-push is destructive)
- Same for nas remote
- Document the rollback in `SYNCMACS-PROGRESS.md`

Document any rollback in `SYNCMACS-PROGRESS.md` and HALT for Nick.

---

## Out of scope for this brief

- **MacBook deploy** of sync-macs.sh and brew-diff-email.sh — same `sudo cp` pattern, separate manual step after this brief completes. The diff-email agent only runs on the Mac Mini (single canonical source); only sync-macs.sh strictly needs to exist on both Macs.
- **Mail.app account configuration** — assumed already set up (verified at PF6).
- **MacBook SSH host key trust** — if PF5 fails, fix that *outside* this brief, then run this brief.
- **NAS Brewfile schema changes** — if `--describe` removal changes the Brewfile format meaningfully (it shouldn't; it's documented as a no-op for `brew bundle dump`), that's a follow-up.

---

## Notes for CC

- This brief was drafted before SSH from Mac Mini to MacBook was confirmed working. PF5 is the gate; do not proceed past it without `OK` response.
- The `--describe` removal is in master-doc v1.11 changelog as a known follow-up; this brief closes that out.
- `SYNCMACS-PROGRESS.md` is a *new* file for this brief and follows the deploy-scaffolding ledger convention demonstrated by `brew-sync-PROGRESS.md` in `spike-chilli-network/docs/`. Question for Nick at first-run-time: should this new ledger also live in `spike-chilli-network/docs/` per that convention, or stay in this repo? Default if unanswered: stay in this repo as a job-specific artifact, separate from the cross-cutting `brew-sync-PROGRESS.md` which tracked the original deploy.
- This is E2 work, no E1 (network) or E5 (hardware lifecycle) dependencies.
- If at any point CC is uncertain about whether to proceed, HALT rather than improvise.
