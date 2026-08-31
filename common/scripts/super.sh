#!/bin/bash
# Assemble super.img from the UT system image + stock dynamic partitions.
# v2 (F6): strict mode + named errors. Previously a missing input produced an
# empty stat and a cryptic lpmake failure; now the absent file is named, and a
# non-host-runnable lpmake (e.g. the aarch64 prebuilt on an x86 host) is
# reported instead of dying with a bare "Exec format error".
# v3 (2026-08-30, parity remediation): LP group budget. The group maximum is
# now the super capacity minus a metadata reserve instead of the plain sum of
# the images. This bakes in the on-device root-grow headroom: with the group
# ceiling at capacity, a future resize2fs/lpresize needs no metadata surgery,
# and rebuilding no longer regresses the device to a sum-tight layout. The
# root size itself comes from deviceinfo_system_partition_size (the rootfs
# image is built at that size; system partition = image size, single-extent).
set -euo pipefail

LPMAKE=${LPMAKE:-lpmake}
command -v "${LPMAKE}" >/dev/null || LPMAKE="$(dirname "$0")/prebuilt/lpmake"
SUPER=${SUPER:-"11744051200"}    # X910 GTS9UWIFI_EUR_OPEN.pit; override per device
GROUP=${GROUP:-"ubuntu"}
PARTS=${PARTS:-"./partitions"}
OUT=${OUT:-"./out/super.img"}
UBUNTU_IMG=${UBUNTU_IMG:-"./out/ubuntu.img"}
# Group ceiling: super capacity minus an 8 MiB reserve for LP metadata and
# alignment. Override with GROUP_LIMIT if a device ever needs otherwise.
GROUP_LIMIT=${GROUP_LIMIT:-$((SUPER - 8388608))}

# lpmake exec probe: 126 = wrong format / not executable, 127 = not found.
# lpmake with no args exits nonzero after usage - that is acceptable here.
rc=0; "${LPMAKE}" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
    echo "lpmake at '${LPMAKE}' is not runnable on this host" >&2
    echo "(the skeleton prebuilt is aarch64; set LPMAKE=/path/to/host/lpmake)" >&2
    exit 1
fi

for f in "${UBUNTU_IMG}" \
         "${PARTS}/system_ext.img" "${PARTS}/system_dlkm.img" \
         "${PARTS}/product.img" "${PARTS}/vendor.img" \
         "${PARTS}/vendor_dlkm.img" "${PARTS}/odm.img"; do
    [ -f "$f" ] || { echo "super.sh: missing input image: $f" >&2; exit 1; }
done

SYSTEM=$(stat -c '%s' "${UBUNTU_IMG}")
SYSTEM_EXT=$(stat -c '%s' "${PARTS}/system_ext.img")
SYSTEM_DLKM=$(stat -c '%s' "${PARTS}/system_dlkm.img")
PRODUCT=$(stat -c '%s' "${PARTS}/product.img")
VENDOR=$(stat -c '%s' "${PARTS}/vendor.img")
VENDOR_DLKM=$(stat -c '%s' "${PARTS}/vendor_dlkm.img")
ODM=$(stat -c '%s' "${PARTS}/odm.img")
METADATA="65536"
TOTAL=$((SYSTEM + PRODUCT + VENDOR + ODM + SYSTEM_EXT + SYSTEM_DLKM + VENDOR_DLKM))

if [ "$TOTAL" -gt "$GROUP_LIMIT" ]; then
    echo "super.sh: images total $TOTAL B > group ceiling $GROUP_LIMIT B" >&2
    echo "(super capacity $SUPER). The rootfs image is the tunable input:" >&2
    echo "lower deviceinfo_system_partition_size and rebuild, or verify SUPER" >&2
    echo "matches this device's PIT." >&2
    exit 1
fi

mkdir -p "$(dirname "${OUT}")"

"${LPMAKE}" \
  --metadata-size ${METADATA} \
  --super-name super \
  --metadata-slots 2 \
  --device super:${SUPER} \
  --group ${GROUP}:${GROUP_LIMIT} \
  --partition system:readonly:${SYSTEM}:${GROUP} \
  --image system="${UBUNTU_IMG}" \
  --partition system_ext:readonly:${SYSTEM_EXT}:${GROUP} \
  --image system_ext="${PARTS}/system_ext.img" \
  --partition system_dlkm:readonly:${SYSTEM_DLKM}:${GROUP} \
  --image system_dlkm="${PARTS}/system_dlkm.img" \
  --partition product:readonly:${PRODUCT}:${GROUP} \
  --image product="${PARTS}/product.img" \
  --partition vendor:readonly:${VENDOR}:${GROUP} \
  --image vendor="${PARTS}/vendor.img" \
  --partition vendor_dlkm:readonly:${VENDOR_DLKM}:${GROUP} \
  --image vendor_dlkm="${PARTS}/vendor_dlkm.img" \
  --partition odm:readonly:${ODM}:${GROUP} \
  --image odm="${PARTS}/odm.img" \
  --output "${OUT}"
