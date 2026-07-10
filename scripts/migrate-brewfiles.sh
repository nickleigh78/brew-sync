#!/bin/bash
# =============================================================================
# migrate-brewfiles.sh — ONE-TIME MIGRATION
# Spike & Chilli Home Network (E2)
# =============================================================================
# Copies Brewfiles from the old NAS path to network-ops/data/brew-sync/.
# Run once after /Volumes/network-ops is confirmed mounted on this Mac.
#
# Old path: /Volumes/home/Drive/Projects/Home Network Project/BrewSync/
# New path: /Volumes/network-ops/data/brew-sync/
#
# Does NOT delete old files — verify the new location is correct before
# removing the originals manually.
#
# After migration:
#   1. Update the shared Brewfile to add the 5 VS Code extensions:
#        vscode "github.remotehub"
#        vscode "github.vscode-github-actions"
#        vscode "github.vscode-pull-request-github"
#        vscode "ms-vscode.azure-repos"
#        vscode "ms-vscode.remote-repositories"
#   2. Run sync-macs.sh to install them on both Macs.
#   3. Remove old Brewfiles from the old NAS path when satisfied.
#
# NOT deployed to /usr/local/bin — run directly from the repo.
# Usage: bash scripts/migrate-brewfiles.sh
# =============================================================================

OLD_DIR="/Volumes/home/Drive/Projects/Home Network Project/BrewSync"
NEW_DIR="/Volumes/network-ops/data/brew-sync"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  brew-sync Brewfile migration — one-time"
echo "  FROM: $OLD_DIR"
echo "  TO:   $NEW_DIR"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
if [ ! -d "$OLD_DIR" ]; then
    echo "✗ Old path not found: $OLD_DIR"
    echo "  Is /Volumes/home mounted? (check mount-nas-locations)"
    exit 1
fi

if [ ! -d "/Volumes/network-ops" ]; then
    echo "✗ /Volumes/network-ops is not mounted"
    echo "  Mount network-ops first (mount-nas-locations pending update),"
    echo "  then re-run this script."
    exit 1
fi

# ---------------------------------------------------------------------------
# Create destination directory
# ---------------------------------------------------------------------------
if mkdir -p "$NEW_DIR"; then
    echo "✓ Destination ready: $NEW_DIR"
else
    echo "✗ Failed to create $NEW_DIR"
    exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# List what will be copied
# ---------------------------------------------------------------------------
echo "  Files to copy:"
ls "$OLD_DIR"/Brewfile* 2>/dev/null | sed 's/^/    /' || echo "    (none found)"
echo ""

# ---------------------------------------------------------------------------
# Copy
# ---------------------------------------------------------------------------
COPIED=0
FAILED=0

for f in "$OLD_DIR"/Brewfile*; do
    [ -f "$f" ] || continue
    fname="$(basename "$f")"
    printf '  → %s ... ' "$fname"
    if cp "$f" "$NEW_DIR/$fname"; then
        echo "✓"
        COPIED=$((COPIED + 1))
    else
        echo "✗  (copy failed)"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "  Summary: $COPIED copied, $FAILED failed"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "✗ Some files failed. Investigate before proceeding."
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
echo "  Verifying new location:"
ls "$NEW_DIR"/Brewfile* 2>/dev/null | sed 's/^/    /' || echo "    (no files found — something went wrong)"
echo ""

# ---------------------------------------------------------------------------
# Post-migration checklist
# ---------------------------------------------------------------------------
echo "═══════════════════════════════════════════════════════════"
echo "  Migration complete. Next steps:"
echo ""
echo "  1. Add VS Code extensions to the shared Brewfile:"
echo "       $NEW_DIR/Brewfile"
echo "     Add these lines:"
echo '       vscode "github.remotehub"'
echo '       vscode "github.vscode-github-actions"'
echo '       vscode "github.vscode-pull-request-github"'
echo '       vscode "ms-vscode.azure-repos"'
echo '       vscode "ms-vscode.remote-repositories"'
echo ""
echo "  2. Run sync-macs.sh to install on both Macs:"
echo "       bash /usr/local/bin/sync-macs.sh"
echo ""
echo "  3. Once satisfied, remove old Brewfiles:"
echo "       rm \"$OLD_DIR\"/Brewfile*"
echo "═══════════════════════════════════════════════════════════"
echo ""
