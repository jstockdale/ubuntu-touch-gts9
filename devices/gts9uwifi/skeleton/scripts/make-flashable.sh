#!/bin/bash
set -xe
HERE=$(dirname "$(realpath "$0")")/..
OUT=${OUT:-"$HERE/out"}
ZIP=$(realpath -m "${ZIP:-"$OUT/ubuntu-touch-gts9uwifi-super.zip"}")
ZSTD_STATIC=${ZSTD_STATIC:-"$HERE/flashable/prebuilt/zstd"}
ZSTD_LEVEL=${ZSTD_LEVEL:-19}

[ -f "$OUT/super.img" ] || { echo "no $OUT/super.img; run scripts/super.sh first"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -r "$HERE/flashable/META-INF" "$STAGE/"
printf 'dummy\n' > "$STAGE/META-INF/com/google/android/updater-script"
cp "$OUT/boot.img" "$OUT/init_boot.img" "$OUT/vendor_boot.img" "$STAGE/"
cp "$OUT/vbmeta.img" "$STAGE/" 2>/dev/null || cp "$HERE/vbmeta.img" "$STAGE/"
# shipped for manual flashing, the updater does not touch the recovery partition
cp "$OUT/recovery.img" "$STAGE/" 2>/dev/null || true
[ -f "$ZSTD_STATIC" ] && cp "$ZSTD_STATIC" "$STAGE/zstd"

zstd -T0 "-$ZSTD_LEVEL" --long=27 -f "$OUT/super.img" -o "$STAGE/super.img.zst"

rm -f "$ZIP"
(cd "$STAGE" && zip -r -0 "$ZIP" .)
ls -la "$ZIP"
