#!/bin/bash
# =============================================================================
# brew-diff-email.sh
# Spike & Chilli Home Network (E2) — Weekly Brew Diff Email
# =============================================================================
# Automated — runs weekly via com.user.brewdiff (Sunday 04:00, after brew-sync
# at 02:00 so Brewfiles are fresh).
#
# Fetches both per-machine Brewfiles from network-ops/data/brew-sync/, diffs
# them, and sends a styled HTML email summarising what differs.
#
# If the machines are identical, a heartbeat "all in sync" email is sent
# so there is always a weekly confirmation the agent ran.
#
# TRANSPORT (2026-09-24, T31): FDA-free SSH, not the SMB mount. The old
#   "-d /Volumes/network-ops" guard only checks the mount is *visible*, not
#   writable/readable from launchd — macOS TCC blocks the launchd context
#   from the network volume, so this script never actually ran under launchd
#   (dead since the 2026-07-10 manual tests, ~2 months of silence). Ported
#   the brew-sync.sh (2026-07-28) fix: fetch both Brewfiles over SSH
#   (key-based, not TCC-gated) into a local staging dir, and log LOCALLY
#   (launchd can always write $HOME), pushing the finished log to the NAS
#   over SSH as a best-effort step at the end.
#
# ALSO FIXED (2026-09-24, T31): casing bug — this script read
#   "Brewfile.NLMacbookProM3" (lowercase b) which does not match the file
#   brew-sync.sh actually writes, "Brewfile.NLMacBookProM3" (ComputerName is
#   capital-B "NLMacBookProM3"). Every diff was therefore comparing the live
#   Mini Brewfile against a stale lowercase-b leftover from 2026-07-10
#   instead of the current MacBook Brewfile. See NEXT.md re: deleting that
#   stale NAS-side file (not done here — this task is repo-only).
#
# Requires Mail.app configured with the target email on this machine.
# On first run: approve "Terminal wants to control Mail" in
#   System Settings → Privacy & Security → Automation.
#
# Log:      network-ops/logs/brew_<MACHINE>_diff_<YYYY-MM-DD-HHMM>.log (pushed)
# Rotation: newest 15 runs kept (NAS-side and local both)
# =============================================================================

NAS_SSH="${BREW_NAS_SSH:-nickleigh@spike-chilli.local}"
NAS_ROOT="/volume1/network-ops"
NAS_BREWDIR="$NAS_ROOT/data/brew-sync"
NAS_LOGDIR="$NAS_ROOT/logs"
SSHNAS(){ ssh -o BatchMode=yes -o ConnectTimeout=8 "$NAS_SSH" "$@"; }
EMAIL="nickleigh78@gmail.com"
MAX_LOG_FILES=15

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"
DATE_DISPLAY="$(date '+%A %-d %B %Y')"
DATE_SHORT="$(date '+%Y-%m-%d')"

# Local staging — never the SMB mount (launchd can always write $HOME).
STAGE="$HOME/.local/state/brew-diff"
mkdir -p "$STAGE"
LOG_FILE="$STAGE/brew_${MACHINE}_diff_$(date '+%Y-%m-%d-%H%M').log"

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

# push the run log to the NAS (best-effort) + rotate NAS logs and local copies.
push_log() {
    SSHNAS "mkdir -p $NAS_LOGDIR && cat > $NAS_LOGDIR/$(basename "$LOG_FILE")" < "$LOG_FILE" 2>/dev/null || true
    SSHNAS "ls -1t $NAS_LOGDIR/brew_${MACHINE}_diff_*.log 2>/dev/null | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f 2>/dev/null" 2>/dev/null || true
    ls -1t "$STAGE"/brew_${MACHINE}_diff_*.log 2>/dev/null | tail -n +$((MAX_LOG_FILES + 1)) | xargs rm -f 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Guard: NAS reachable over SSH? (replaces the SMB "-d $BREWDIR" mount check)
# ---------------------------------------------------------------------------
if ! SSHNAS true 2>/dev/null; then
    log "✗ NAS unreachable over SSH — skipping diff email (away or NAS down)"
    push_log
    exit 1
fi

log "━━━ brew-diff-email.sh starting — $MACHINE ━━━"

MINI_FILE="$STAGE/Brewfile.NLMacMiniM1"
MACBOOK_FILE="$STAGE/Brewfile.NLMacBookProM3"

# ---------------------------------------------------------------------------
# Fetch both Brewfiles over SSH (not the SMB mount)
# ---------------------------------------------------------------------------
if ! SSHNAS "cat $NAS_BREWDIR/Brewfile.NLMacMiniM1" > "$MINI_FILE" 2>/dev/null || [ ! -s "$MINI_FILE" ]; then
    log "✗ failed to fetch Brewfile.NLMacMiniM1 from $NAS_SSH:$NAS_BREWDIR"
    push_log
    exit 1
fi
if ! SSHNAS "cat $NAS_BREWDIR/Brewfile.NLMacBookProM3" > "$MACBOOK_FILE" 2>/dev/null || [ ! -s "$MACBOOK_FILE" ]; then
    log "✗ failed to fetch Brewfile.NLMacBookProM3 from $NAS_SSH:$NAS_BREWDIR"
    push_log
    exit 1
fi
log "✓ fetched both Brewfiles from $NAS_SSH:$NAS_BREWDIR"

# ---------------------------------------------------------------------------
# Diff — strip any residual --describe comment lines
# ---------------------------------------------------------------------------
DIFF_OUTPUT="$(diff \
    <(grep -v '^#' "$MINI_FILE") \
    <(grep -v '^#' "$MACBOOK_FILE"))"

SUBJECT="Weekly Brew Diff — NLMacMiniM1 vs NLMacbookProM3 — ${DATE_SHORT}"
log "  subject: $SUBJECT"

# ---------------------------------------------------------------------------
# Known acceptable differences
# ---------------------------------------------------------------------------
KNOWN_MINI_ONLY="libspatialite"
KNOWN_BOOK_ONLY="cairo tcl-tk"
KNOWN_BOTH_ORDER="chromaprint e2fsprogs exiftool"

in_list() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Build HTML email
# ---------------------------------------------------------------------------
HTML_FILE="$(mktemp /tmp/brew-diff-XXXXXX.html)"

# Static CSS + opening tags
cat >> "$HTML_FILE" << 'HTMLHEAD'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
body{margin:0;padding:20px;background:#f0f2f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif}
.card{max-width:580px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.1)}
.hdr{background:linear-gradient(135deg,#1c1c2e 0%,#2d2d4a 100%);color:#fff;padding:28px}
.hdr-icon{font-size:32px;line-height:1;margin-bottom:10px}
.hdr-title{font-size:20px;font-weight:700;margin:0 0 4px;letter-spacing:-.3px}
.hdr-sub{font-size:13px;opacity:.6;margin:0}
.status{display:flex;align-items:center;gap:10px;padding:14px 24px;background:#fafafa;border-bottom:1px solid #eee}
.badge{display:inline-block;padding:3px 10px;border-radius:20px;font-size:12px;font-weight:700}
.badge-ok{background:#d4edda;color:#155724}
.badge-warn{background:#fff3cd;color:#856404}
.status-msg{font-size:13px;color:#555}
.section{padding:20px 24px;border-bottom:1px solid #f0f0f0}
.section-label{font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:#aaa;margin:0 0 12px}
.key{display:flex;gap:20px}
.key-item{display:flex;align-items:center;gap:8px;font-size:13px;color:#444}
.dot{width:10px;height:10px;border-radius:50%;flex-shrink:0}
.dot-mini{background:#d35400}
.dot-book{background:#1a73c4}
.row{display:flex;align-items:baseline;gap:8px;padding:7px 10px;border-radius:7px;margin-bottom:3px;font-family:'SF Mono','Monaco','Menlo',monospace;font-size:13px;line-height:1.4}
.row-mini{background:#fef0e8;color:#a83200}
.row-book{background:#e8f0fe;color:#174ea6}
.row-tag{font-size:11px;font-weight:700;opacity:.6;min-width:16px}
.row-note{font-size:11px;color:#bbb;font-style:italic;font-family:-apple-system,sans-serif;margin-left:4px}
.raw{background:#1c1c2e;color:#c8c8e0;border-radius:8px;padding:16px;font-family:'SF Mono','Monaco','Menlo',monospace;font-size:12px;line-height:1.7;white-space:pre;overflow-x:auto}
.raw-mini{color:#e07050}
.raw-book{color:#5b9bd5}
.ok-body{padding:40px 24px;text-align:center}
.ok-icon{font-size:44px;margin-bottom:12px}
.ok-title{font-size:16px;font-weight:600;color:#333;margin-bottom:6px}
.ok-sub{font-size:13px;color:#888}
.footer{padding:16px 24px;background:#fafafa;font-size:12px;color:#888;line-height:2}
.footer code{background:#eee;padding:2px 6px;border-radius:4px;font-family:'SF Mono',monospace;font-size:11px;color:#444}
</style>
</head>
<body>
<div class="card">
HTMLHEAD

# Header (dynamic date)
printf '<div class="hdr"><div class="hdr-icon">📦</div><p class="hdr-title">Weekly Brew Diff</p><p class="hdr-sub">NLMacMiniM1 vs NLMacbookProM3 &nbsp;·&nbsp; %s</p></div>\n' \
    "$DATE_DISPLAY" >> "$HTML_FILE"

if [ -z "$DIFF_OUTPUT" ]; then
    # ---------------------------------------------------------------------------
    # Heartbeat — no differences
    # ---------------------------------------------------------------------------
    cat >> "$HTML_FILE" << 'NODIFF'
<div class="status"><span class="badge badge-ok">✅ Identical</span><span class="status-msg">Both machines are in sync.</span></div>
<div class="ok-body">
  <div class="ok-icon">✅</div>
  <div class="ok-title">Machines are in sync</div>
  <div class="ok-sub">NLMacMiniM1 and NLMacbookProM3 share the same Homebrew state.</div>
</div>
NODIFF

else
    # ---------------------------------------------------------------------------
    # Process diff — categorise and build HTML rows
    # ---------------------------------------------------------------------------
    DIFF_ROWS=""
    RAW_HTML=""
    HAS_UNEXPECTED=false
    UNEXPECTED_COUNT=0

    while IFS= read -r line; do
        case "$line" in
            "< "*)
                raw="${line#< }"
                pkg="$(printf '%s' "$raw" | grep -oE '"[^"]+"' | head -1 | tr -d '"')"
                esc="${raw//&/&amp;}"; esc="${esc//</&lt;}"; esc="${esc//>/&gt;}"
                # shellcheck disable=SC2086
                if in_list "$pkg" $KNOWN_MINI_ONLY; then
                    note='<span class="row-note">Mini only — expected</span>'
                elif in_list "$pkg" $KNOWN_BOTH_ORDER; then
                    note='<span class="row-note">ordering only — on both machines</span>'
                else
                    note=''
                    HAS_UNEXPECTED=true
                    UNEXPECTED_COUNT=$((UNEXPECTED_COUNT + 1))
                fi
                DIFF_ROWS+="<div class=\"row row-mini\"><span class=\"row-tag\">&lt;</span><span>🖥️ ${esc}</span>${note}</div>"
                raw_esc="${line//&/&amp;}"; raw_esc="${raw_esc//</&lt;}"; raw_esc="${raw_esc//>/&gt;}"
                RAW_HTML+="<span class=\"raw-mini\">${raw_esc}</span>"$'\n'
                ;;
            "> "*)
                raw="${line#> }"
                pkg="$(printf '%s' "$raw" | grep -oE '"[^"]+"' | head -1 | tr -d '"')"
                esc="${raw//&/&amp;}"; esc="${esc//</&lt;}"; esc="${esc//>/&gt;}"
                # shellcheck disable=SC2086
                if in_list "$pkg" $KNOWN_BOOK_ONLY; then
                    note='<span class="row-note">MacBook only — expected</span>'
                elif in_list "$pkg" $KNOWN_BOTH_ORDER; then
                    note='<span class="row-note">ordering only — on both machines</span>'
                else
                    note=''
                    HAS_UNEXPECTED=true
                    UNEXPECTED_COUNT=$((UNEXPECTED_COUNT + 1))
                fi
                DIFF_ROWS+="<div class=\"row row-book\"><span class=\"row-tag\">&gt;</span><span>💻 ${esc}</span>${note}</div>"
                raw_esc="${line//&/&amp;}"; raw_esc="${raw_esc//</&lt;}"; raw_esc="${raw_esc//>/&gt;}"
                RAW_HTML+="<span class=\"raw-book\">${raw_esc}</span>"$'\n'
                ;;
            *)
                raw_esc="${line//&/&amp;}"; raw_esc="${raw_esc//</&lt;}"; raw_esc="${raw_esc//>/&gt;}"
                RAW_HTML+="${raw_esc}"$'\n'
                ;;
        esac
    done <<< "$DIFF_OUTPUT"

    # Status bar
    if $HAS_UNEXPECTED; then
        printf '<div class="status"><span class="badge badge-warn">⚠️ Review needed</span><span class="status-msg">%d package(s) outside the expected list.</span></div>\n' \
            "$UNEXPECTED_COUNT" >> "$HTML_FILE"
    else
        printf '<div class="status"><span class="badge badge-ok">✅ Expected only</span><span class="status-msg">All differences are on the known list.</span></div>\n' \
            >> "$HTML_FILE"
    fi

    # Key
    cat >> "$HTML_FILE" << 'KEY'
<div class="section">
<p class="section-label">Key</p>
<div class="key">
<div class="key-item"><div class="dot dot-mini"></div>🖥️ Mac Mini only (&lt;)</div>
<div class="key-item"><div class="dot dot-book"></div>💻 MacBook only (&gt;)</div>
</div></div>
KEY

    # Packages
    printf '<div class="section"><p class="section-label">📋 Packages</p>%s</div>\n' \
        "$DIFF_ROWS" >> "$HTML_FILE"

    # Raw diff
    printf '<div class="section"><p class="section-label">📄 Raw diff</p><div class="raw">%s</div></div>\n' \
        "$RAW_HTML" >> "$HTML_FILE"
fi

# Footer (static)
cat >> "$HTML_FILE" << 'HTMLFOOT'
<div class="footer">
🔁 &nbsp;<code>bash /usr/local/bin/sync-macs.sh</code> — sync both Macs to the shared Brewfile<br>
📂 &nbsp;<code>/Volumes/network-ops/data/brew-sync/Brewfile</code> — shared baseline
</div>
</div>
</body>
</html>
HTMLFOOT

# ---------------------------------------------------------------------------
# Send via Mail.app
# ---------------------------------------------------------------------------
log "→ Sending email to $EMAIL..."

SUBJECT_ESCAPED="${SUBJECT//\"/\\\"}"
if osascript << APPLESCRIPT
set htmlPath to "$HTML_FILE"
set htmlContent to do shell script "cat " & quoted form of htmlPath
tell application "Mail"
    set newMsg to make new outgoing message with properties ¬
        {subject:"$SUBJECT_ESCAPED", html content:htmlContent, sender:"$EMAIL", visible:false}
    tell newMsg
        make new to recipient with properties {address:"$EMAIL"}
        send
    end tell
end tell
APPLESCRIPT
then
    log "✓ Email sent to $EMAIL"
else
    log "✗ osascript failed — check Mail.app Automation permission in"
    log "  System Settings → Privacy & Security → Automation"
    rm -f "$HTML_FILE"
    push_log
    exit 1
fi

rm -f "$HTML_FILE"

log "━━━ brew-diff-email.sh complete ━━━"
log ""
push_log
