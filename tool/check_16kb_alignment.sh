#!/usr/bin/env bash
# Reports whether the 64-bit native libraries inside an APK or AAB are aligned for
# 16 KB memory pages (Google Play requires this for apps targeting Android 15+).
#
#   tool/check_16kb_alignment.sh build/app/outputs/bundle/release/app-release.aab [--strict]
#
# Only arm64-v8a and x86_64 are checked: 16 KB pages exist only on 64-bit devices, and
# 32-bit libraries are listed for information. A library is compliant when the largest
# `Align` of its LOAD segments is at least 0x4000 (16384). With --strict the script
# exits 1 if any 64-bit library is not compliant; otherwise it only warns.
set -euo pipefail

archive="${1:?usage: check_16kb_alignment.sh <file.aab|file.apk> [--strict]}"
strict="${2:-}"
[ -f "$archive" ] || { echo "error: $archive not found" >&2; exit 2; }
command -v readelf >/dev/null || { echo "error: readelf (binutils) is required" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
unzip -oq "$archive" -d "$work"

bad=()
printf '%-48s %-12s %-8s %s\n' LIBRARY ABI ALIGN STATUS
while IFS= read -r so; do
  rel="${so#"$work"/}"
  abi="$(printf '%s' "$rel" | grep -oE 'arm64-v8a|armeabi-v7a|x86_64|x86' | head -n1 || true)"
  align=0
  while read -r hex; do
    [ -n "$hex" ] || continue
    dec=$((hex))
    [ "$dec" -gt "$align" ] && align=$dec
  done < <(readelf -lW "$so" 2>/dev/null | awk '$1 == "LOAD" { print $NF }')
  case "$abi" in
    arm64-v8a|x86_64)
      if [ "$align" -ge 16384 ]; then status=OK; else status=FAIL; bad+=("$rel (align=$(printf '0x%x' "$align"))"); fi ;;
    *) status="n/a (not 64-bit)" ;;
  esac
  printf '%-48s %-12s %-8s %s\n' "$(basename "$so")" "${abi:-unknown}" "$(printf '0x%x' "$align")" "$status"
done < <(find "$work" -name '*.so' | sort)

echo
if [ "${#bad[@]}" -eq 0 ]; then
  echo "All 64-bit native libraries are 16 KB aligned (or there are none)."
  exit 0
fi
echo "Not 16 KB aligned (${#bad[@]}):"
printf '  - %s\n' "${bad[@]}"
echo "Find the plugin that ships each library and look for a newer release."
[ "$strict" = "--strict" ] && exit 1
echo "::warning::${#bad[@]} native librar(ies) are not 16 KB aligned; see the log."
exit 0
