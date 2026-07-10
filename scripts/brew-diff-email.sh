#!/bin/bash
# =============================================================================
# brew-diff-email.sh
# Spike & Chilli Home Network (E2) — Weekly Brew Diff Email
# =============================================================================
# Automated — runs weekly via com.user.brewdiff (Sunday 04:00, after brew-sync
# at 02:00 so Brewfiles are fresh).
#
# Reads both per-machine Brewfiles from network-ops/data/brew-sync/, diffs
# them, and sends a styled HTML email summarising what differs.
#
# If the machines are identical, a heartbeat "all in sync" email is sent
# so there is always a weekly confirmation the agent ran.
#
# Requires /Volumes/network-ops to be mounted. Exits cleanly if not.
# Requires Mail.app configured with the target email on this machine.
# On first run: approve "Terminal wants to control Mail" in
#   System Settings → Privacy & Security → Automation.
#
# Log:      /Volumes/network-ops/logs/brew_<MACHINE>_diff_<YYYY-MM-DD-HHMM>.log
# Rotation: newest 15 runs kept
# =============================================================================

NETWORK_OPS="/Volumes/network-ops"
BREWDIR="$NETWORK_OPS/data/brew-sync"
LOGDIR="$NETWORK_OPS/logs"
EMAIL="nickleigh78@gmail.com"
MAX_LOG_FILES=15

MACHINE="$(scutil --get ComputerName 2>/dev/null || echo "unknown")"
DATE_DISPLAY="$(date '+%A %-d %B %Y')"
DATE_SHORT="$(date '+%Y-%m-%d')"

# ---------------------------------------------------------------------------
# Guard: network-ops must be mounted
# ---------------------------------------------------------------------------
if [ ! -d "$BREWDIR" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')  ✗ /Volumes/network-ops not mounted — skipping diff email" >&2
    exit 1
fi

mkdir -p "$LOGDIR"
LOG_FILE="$LOGDIR/brew_${MACHINE}_diff_$(date '+%Y-%m-%d-%H%M').log"

log() {
    local line
    line="$(printf '%s  %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$*")"
    printf '%s\n' "$line" | tee -a "$LOG_FILE"
}

log "━━━ brew-diff-email.sh starting — $MACHINE ━━━"

MINI_FILE="$BREWDIR/Brewfile.NLMacMiniM1"
MACBOOK_FILE="$BREWDIR/Brewfile.NLMacbookProM3"

for f in "$MINI_FILE" "$MACBOOK_FILE"; do
    if [ ! -f "$f" ]; then
        log "✗ Brewfile not found: $f"
        exit 1
    fi
done

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
    exit 1
fi

rm -f "$HTML_FILE"

# ---------------------------------------------------------------------------
# Log rotation
# ---------------------------------------------------------------------------
ls -1t "$LOGDIR"/brew_${MACHINE}_diff_*.log 2>/dev/null \
    | tail -n "+$((MAX_LOG_FILES + 1))" | xargs rm -f 2>/dev/null || true

log "━━━ brew-diff-email.sh complete ━━━"
log ""
