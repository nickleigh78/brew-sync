# NEXT — brew-sync (T31)

**State:** T31 pipeline fixes complete on branch `t31-brew-sync-fix`, pushed to `nas`.
**Repo-only — NOT deployed to any Mac.** No sudo, no launchctl, no scp, no live
system access was taken. This branch has NOT been merged to `main` — merge is
Nick's review gate.

## What was fixed (this branch)

1. **`scripts/brew-update.sh`** — ported the brew-sync.sh (2026-07-28) SSH-log-push
   fix. Was silently no-op'ing since ~mid-July: the `-d /Volumes/network-ops` guard
   only checked the mount was *visible*, not writable — launchd's TCC sandbox blocks
   the SMB write, so `brew ... >> $LOG_FILE` failed before brew ever ran. Now stages
   the log under `~/.local/state/brew-update/` (always writable), runs
   update/upgrade/cleanup against that, then pushes the finished log to the NAS over
   SSH as best-effort. brew itself no longer depends on the mount at all.
2. **`scripts/brew-diff-email.sh`** — same SSH-fetch/SSH-log-push port, PLUS fixed the
   casing bug: it was reading `Brewfile.NLMacbookProM3` (lowercase b) instead of the
   real `Brewfile.NLMacBookProM3` (capital B) that brew-sync.sh writes — every diff
   was silently comparing against a stale 2026-07-10 leftover, not the current
   MacBook state.
3. **README/CONTEXT MZMacMini scope** — verified consistent, no changes needed.
   Confirmed README, CONTEXT.md, and `install-launchd-agents.sh` all agree MZMacMini
   is isolated/out-of-scope (2026-09-22) and the installer actively refuses to deploy
   there.
4. **`bash -n` syntax-checked** both edited scripts — both clean.

## NOT done — flagged, not guessed

**Stale `Brewfile.NLMacbookProM3` (lowercase b) on the NAS was NOT deleted.**
It lives at `nickleigh@spike-chilli.local:/volume1/network-ops/data/brew-sync/
Brewfile.NLMacbookProM3` — this is **data on the NAS, not a repo file** (the repo
only ever generates/reads it; nothing in `~/Projects/Home-Network/brew-sync` itself
is stale). This task's hard constraint was repo-only work on local disk, so deleting
a live NAS data file was out of scope here even though it's low-risk. Recommended:

```bash
# Confirm the stale file first (dated 2026-07-10, capital-B one should be much newer):
ssh nickleigh@spike-chilli.local "ls -la /volume1/network-ops/data/brew-sync/Brewfile.NLMac*"
# If confirmed stale, delete it:
ssh nickleigh@spike-chilli.local "rm /volume1/network-ops/data/brew-sync/Brewfile.NLMacbookProM3"
```

## Exact remaining steps for Nick (deploy — live-box, needs local sudo)

This branch only changes files in the repo. To make the fix live, per README's
"Deploying script updates" section:

```bash
cd ~/Projects/Home-Network/brew-sync
git fetch nas && git checkout t31-brew-sync-fix   # or merge to main first, your call

# NLMacbookProM3 (run locally on the MacBook):
sudo cp scripts/brew-update.sh      /usr/local/bin/brew-update.sh
sudo cp scripts/brew-diff-email.sh  /usr/local/bin/brew-diff-email.sh
sudo chmod 755 /usr/local/bin/brew-update.sh
sudo chmod 644 /usr/local/bin/brew-diff-email.sh   # matches repo perms; launchd invokes it via bash regardless

# NLMacMiniM1 (brew-update.sh only — no brew-diff-email there):
scp scripts/brew-update.sh nickleigh@NLMacMiniM1.local:/tmp/
ssh -t nickleigh@NLMacMiniM1.local \
    "sudo cp /tmp/brew-update.sh /usr/local/bin/ && sudo chmod 755 /usr/local/bin/brew-update.sh"

# No plist changes needed on either machine — the fix is entirely inside the
# scripts; existing com.user.brewupdate / com.user.brewdiff agents pick it up
# on next scheduled fire, no reload required. (Watch for the quarantine
# gotcha from the 2026-09-21 upgrade if you DO touch plists — README §"quarantine gotcha".)
```

**Suggested manual test after deploying** (don't wait for next Wednesday):

```bash
# On whichever Mac you just deployed to:
launchctl kickstart -k gui/$(id -u)/com.user.brewupdate
sleep 5   # brew update/upgrade/cleanup take longer than this in practice — check back
ls -1t ~/.local/state/brew-update/*.log | head -1 | xargs tail -30
# Expect: "brew update complete" / "brew upgrade complete" / "brew cleanup complete"
# lines, NOT "Operation not permitted".

# On the MacBook only, after brew-sync has produced fresh Brewfiles on the NAS:
launchctl kickstart -k gui/$(id -u)/com.user.brewdiff
ls -1t ~/.local/state/brew-diff/*.log | head -1 | xargs tail -30
# Expect an email in Mail.app Sent, subject "Weekly Brew Diff — ... — <today>",
# and the diff should now be against the REAL MacBook Brewfile (capital B),
# not the stale lowercase-b one.
```

If either kickstart doesn't fire cleanly, check for the quarantine xattr first
(`xattr -l ~/Library/LaunchAgents/com.user.brew*.plist` — a trailing `@` in `ls -la`
means it's quarantined) before assuming the script itself is broken again.

## Branch

`t31-brew-sync-fix` — pushed to `nas` remote. NOT merged to `main`. Merge is Nick's
call after reviewing the diff + (ideally) running the manual test above.
