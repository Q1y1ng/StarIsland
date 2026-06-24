#!/bin/bash
# =============================================================================
# StarIsland — CI Build Diagnostic Script
# =============================================================================
# Runs during GitHub Actions Build Verification job.
# Collects environment + project metadata for troubleshooting.
#
# Output: diagnostic.log (uploaded as artifact)
# =============================================================================

set -euo pipefail

DIAG_LOG="${PWD}/diagnostic.log"
PROJECT_ROOT="${PWD}"

echo "═════════════════════════════════════════════════════════════════" | tee "$DIAG_LOG"
echo "  StarIsland CI Diagnostic — $(date -u '+%Y-%m-%d %H:%M:%S UTC')" | tee -a "$DIAG_LOG"
echo "═════════════════════════════════════════════════════════════════" | tee -a "$DIAG_LOG"
echo "" | tee -a "$DIAG_LOG"

# ── Build Environment ──────────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"
echo "  Build Environment" | tee -a "$DIAG_LOG"
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"

echo "macOS Version:  $(sw_vers -productVersion 2>/dev/null || echo 'N/A')" | tee -a "$DIAG_LOG"
echo "Xcode:          $(xcodebuild -version 2>/dev/null | head -1 || echo 'N/A')" | tee -a "$DIAG_LOG"
echo "Swift:          $(swift --version 2>/dev/null | head -1 || echo 'N/A')" | tee -a "$DIAG_LOG"

# SDK list
echo "SDKs:" | tee -a "$DIAG_LOG"
xcodebuild -showsdks 2>/dev/null | grep -i "ios" | sed 's/^/  /' | tee -a "$DIAG_LOG" || echo "  (none)" | tee -a "$DIAG_LOG"

echo "" | tee -a "$DIAG_LOG"

# ── Project Structure ──────────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"
echo "  Project Structure" | tee -a "$DIAG_LOG"
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"

# Swift files
SWIFT_COUNT=$(find "$PROJECT_ROOT/StarIsland" -name "*.swift" | wc -l)
echo "Swift files:    $SWIFT_COUNT" | tee -a "$DIAG_LOG"

# Swift files per directory
echo "  By directory:" | tee -a "$DIAG_LOG"
for dir in "$PROJECT_ROOT/StarIsland"/*/; do
  dname=$(basename "$dir")
  count=$(find "$dir" -name "*.swift" 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "    $dname/ → $count files" | tee -a "$DIAG_LOG"
done

# Resource files
RESOURCE_COUNT=$(find "$PROJECT_ROOT/StarIsland" \
  \( -name "*.xcassets" -o -name "*.storyboard" -o -name "*.plist" \) \
  2>/dev/null | wc -l)
echo "Resource dirs:  $RESOURCE_COUNT" | tee -a "$DIAG_LOG"

echo "" | tee -a "$DIAG_LOG"

# ── Required Files Check ───────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"
echo "  Required Files Check" | tee -a "$DIAG_LOG"
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"

check_file() {
  local path="$1"
  local label="$2"
  if [ -f "$PROJECT_ROOT/$path" ]; then
    local size=$(wc -c < "$PROJECT_ROOT/$path" | tr -d ' ')
    echo "  ✅  $label  ($path, ${size}B)" | tee -a "$DIAG_LOG"
  else
    echo "  ❌  $label  ($path — MISSING!)" | tee -a "$DIAG_LOG"
  fi
}

check_file "project.yml"              "XcodeGen Spec"
check_file "ExportOptions.plist"      "IPA Export Options"
check_file "StarIsland/Info.plist"    "App Info.plist"
check_file ".gitignore"               "Git Ignore"
check_file "README.md"                "README"
check_file "CHANGELOG.md"             "CHANGELOG"
check_file "Roadmap.md"               "Roadmap"
check_file "LICENSE"                  "License"
check_file ".github/workflows/ios-build.yml" "CI Workflow"
check_file "StarIsland/Base.lproj/LaunchScreen.storyboard" "Launch Screen"
check_file "StarIsland/Assets.xcassets/Contents.json"      "Asset Catalog"

echo "" | tee -a "$DIAG_LOG"

# ── Swift File Integrity ───────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"
echo "  Swift File Integrity" | tee -a "$DIAG_LOG"
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"

# Check for zero-length Swift files
ZERO_COUNT=0
while IFS= read -r -d '' f; do
  if [ ! -s "$f" ]; then
    echo "  ⚠️   Empty file: $f" | tee -a "$DIAG_LOG"
    ZERO_COUNT=$((ZERO_COUNT + 1))
  fi
done < <(find "$PROJECT_ROOT/StarIsland" -name "*.swift" -type f -print0)

if [ "$ZERO_COUNT" -eq 0 ]; then
  echo "  ✅  All Swift files non-empty" | tee -a "$DIAG_LOG"
fi

# Check for common import issues
echo "" | tee -a "$DIAG_LOG"
echo "  Import stats (unique system frameworks):" | tee -a "$DIAG_LOG"
grep -rh '^import ' "$PROJECT_ROOT/StarIsland" 2>/dev/null \
  | sort | uniq -c | sort -rn \
  | while read count mod; do
    printf "    %3d  %s\n" "$count" "$mod" | tee -a "$DIAG_LOG"
  done

echo "" | tee -a "$DIAG_LOG"

# ── XcodeGen Validation ────────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"
echo "  XcodeGen Validation" | tee -a "$DIAG_LOG"
echo "──────────────────────────────────────────────────────────────────" | tee -a "$DIAG_LOG"

if command -v xcodegen &>/dev/null; then
  echo "xcodegen:       $(xcodegen --version 2>/dev/null || echo 'installed')" | tee -a "$DIAG_LOG"
  if xcodegen generate --project "$PROJECT_ROOT" 2>/dev/null; then
    echo "  ✅  Project generation successful" | tee -a "$DIAG_LOG"
  else
    echo "  ❌  Project generation FAILED" | tee -a "$DIAG_LOG"
  fi
else
  echo "  ⚠️   xcodegen not installed on this machine" | tee -a "$DIAG_LOG"
fi

echo "" | tee -a "$DIAG_LOG"

# ── Summary ─────────────────────────────────────────────────────────────────
echo "═════════════════════════════════════════════════════════════════" | tee -a "$DIAG_LOG"
echo "  Diagnostic Complete" | tee -a "$DIAG_LOG"
echo "═════════════════════════════════════════════════════════════════" | tee -a "$DIAG_LOG"
