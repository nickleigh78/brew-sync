# brew-sync pipeline — health check 2026-09-12 (Helm/T28)

Read-only verification of the Wednesday pipeline across all 3 Macs (last scheduled Wed = 2026-09-09).
Nothing was modified. **Net: the pipeline is only partly alive — snapshotting works, the actual
`brew upgrade` and the weekly diff email are broken/silent, and MZMacMini isn't running it at all.**

## Per-Mac status

### NLMacMiniM1 (core node) — 1 of 2 jobs healthy
- **`brewsync`: HEALTHY** — loaded, exit 0, ran Wed 09-09 02:00, Brewfile published to NAS over SSH; weekly cadence intact back to July.
- **`brewupdate`: BROKEN (exit 1)** — `/tmp/brewupdate.err` = repeated `Operation not permitted` on `/Volumes/network-ops/logs/...`. macOS **TCC blocks the launchd context from the SMB mount** — same class of bug `brew-sync.sh` was fixed for on 2026-07-28, but `brew-update.sh` never got the fix. Because `brew … >> $LOG_FILE` opens the unwritable logfile *before* running brew, the redirection fails and **`brew update/upgrade/cleanup` never execute.** Broken since ~mid-July. 11 outdated formulae + 1 cask piling up.
- `brewdiff`: not installed here (correct — MacBook owns it).

### NLMacBookProM3 — sync healthy, update degraded, diff dead
- **`brewsync`: HEALTHY** — all 3 plists loaded, SSH-transport version deployed, pushed to NAS 09-09 02:00, correctly logs "away" skips when travelling.
- **`brewupdate`: INTERMITTENT** — old 10-Jul script. Works when *away* (mount absent → local fallback, logs through 2026-08-26); when network-ops IS mounted (09-02, 09-09) it hits the same TCC failure silently. 20 outdated formulae + 2 casks accumulating.
- **`brewdiff`: NON-FUNCTIONAL** — no diff logs since 2026-07-10 manual tests; no weekly email/heartbeat for ~2 months. Two bugs: (a) **casing** — line 54 hardcodes `Brewfile.NLMacbookProM3` (lower-b) but ComputerName is `NLMacBookProM3` (capital B) → diffs a stale 10-Jul leftover; (b) **TCC** — reads Brewfiles + writes its log directly on the SMB mount from launchd (blocked).

### MZMacMini (Marty's, Intel, 10.0.10.22) — NOT running at all
- Reachable + awake, but **no brew launchd agents installed** (`~/Library/LaunchAgents` has only Adobe/Dropbox/Google). brewsync/brewupdate are unscheduled — they never run. **Contradicts the README/CONTEXT deployment table.**
- Scripts present but stale (`/usr/local/bin/brew-{sync,update}.sh` dated 11-Jul, pre-SSH-fix).
- **No GUI session** (console user = root; uid 501 has no Aqua domain) → user LaunchAgents couldn't fire even if installed — consistent with the EFI-sleep-fix posture.

## Data hygiene
Stale duplicate `Brewfile.NLMacbookProM3` (lower-b, 2026-07-10) sits beside the live `Brewfile.NLMacBookProM3` on the NAS — it's what the broken diff reads. Delete after fixing the casing.

## Recommended fixes (NOT applied)
1. **Port the `brew-sync.sh` fix to `brew-update.sh` + `brew-diff-email.sh`.** The `-d /Volumes/network-ops` existence test (update line 32, diff line 37) is the trap — the mount is *visible* but not *writable/readable* from launchd. For update: always log locally (`~/Library/Logs/…`) or probe real write access + fall back. For diff: read Brewfiles via SSH from the NAS (as sync does), not via the mount.
2. **Fix the diff casing:** `brew-diff-email.sh` line 54 → `Brewfile.NLMacBookProM3` (capital B) or derive filenames dynamically; then delete the stale lower-b Brewfile on the NAS.
3. **MZMacMini — decide scope.** In-scope → install plists, redeploy current scripts, solve the no-GUI-session issue (needs a LaunchDaemon or auto-login given sleep is disabled). Out-of-scope → correct the README/CONTEXT deployment table (currently overstates its status).

**Common thread for the Apple-Silicon failures:** one unaddressed bug — launchd can't touch the SMB mount, and only `brew-sync.sh` was ever fixed for it.
