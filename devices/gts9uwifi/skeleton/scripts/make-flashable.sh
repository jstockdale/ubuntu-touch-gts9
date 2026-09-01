#!/bin/bash
# Package the flashable TWRP zip.
# v2: -euo pipefail added alongside -x; boot-chain inputs are now checked
# up front with named errors instead of relying on cp's failure message.
set -xeuo pipefail
HERE=$(dirname "$(realpath "$0")")/..
OUT=${OUT:-"$HERE/out"}
ZIP=$(realpath -m "${ZIP:-"$OUT/ubuntu-touch-gts9uwifi-super.zip"}")
ZSTD_STATIC=${ZSTD_STATIC:-"$HERE/flashable/prebuilt/zstd"}
ZSTD_LEVEL=${ZSTD_LEVEL:-19}

for f in "$OUT/super.img" "$OUT/boot.img" "$OUT/init_boot.img" "$OUT/vendor_boot.img"; do
    [ -f "$f" ] || { echo "make-flashable: missing $f (run scripts/super.sh and the image build first)" >&2; exit 1; }
done

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -r "$HERE/flashable/META-INF" "$STAGE/"
printf 'dummy\n' > "$STAGE/META-INF/com/google/android/updater-script"
cp "$OUT/boot.img" "$OUT/init_boot.img" "$OUT/vendor_boot.img" "$STAGE/"
if [ -f "$OUT/vbmeta.img" ]; then
    cp "$OUT/vbmeta.img" "$STAGE/"; echo "vbmeta: using built $OUT/vbmeta.img"
else
    cp "$HERE/vbmeta.img" "$STAGE/"; echo "vbmeta: using skeleton $HERE/vbmeta.img"
fi
# shipped for manual flashing, the updater does not touch the recovery partition
cp "$OUT/recovery.img" "$STAGE/" 2>/dev/null || true
# update-binary hard-requires zstd (recovery's own or this bundled static);
# shipping without the bundle would make the zip depend on TWRP's toolset.
[ -f "$ZSTD_STATIC" ] || { echo "make-flashable: missing static zstd at $ZSTD_STATIC" >&2; exit 1; }
cp "$ZSTD_STATIC" "$STAGE/zstd"

zstd -T0 "-$ZSTD_LEVEL" --long=27 -f "$OUT/super.img" -o "$STAGE/super.img.zst"

rm -f "$ZIP"
(cd "$STAGE" && zip -r -0 "$ZIP" .)
ls -la "$ZIP"
