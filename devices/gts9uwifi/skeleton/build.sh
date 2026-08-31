#!/bin/bash
set -xe

[ -d build ] || git clone -b personal/azkali/gts9-integration https://gitlab.com/azkali-samsung/gts9/ubports/halium-generic-adaptation-build-tools.git build

for tree in graphics-kernel display-drivers mm-drivers mmrm-driver securemsm-kernel audio-kernel wlan bt-kernel camera-kernel eva-kernel; do
    [ -d "workdir/downloads/vendor/qcom/opensource/$tree" ] || \
        git clone -b android13-5.15-halium "https://gitlab.com/azkali-samsung/gts9/ubports/$tree.git" \
            "workdir/downloads/vendor/qcom/opensource/$tree"
done

find overlay ramdisk-overlay vendor-ramdisk-overlay -type d -exec chmod o+rx {} +
find overlay -type f -exec chmod o+r {} +

export ROOTFS_URL="${ROOTFS_URL:-https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252F24.04-2.x/lastSuccessfulBuild/artifact/ubuntu-touch-android9plus-rootfs-arm64.tar.gz}"
export OTA_CHANNEL="${OTA_CHANNEL:-24.04-2.x/arm64/android9plus/rc}"

./build/build.sh -b workdir "$@"
./build/prepare-fake-ota.sh ./out/device_gts9uwifi_usrmerge.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command out
mv out/rootfs.img out/ubuntu.img
cp workdir/tmp/partitions/recovery.img out/ 2>/dev/null || true

FIRMWARE=${FIRMWARE:-"https://download.azka.li/samsung/tab-s9/firmware/ubuntu-touch-kalama-firmware-v.tar.xz"}
[ -f $(basename ${FIRMWARE}) ] || wget -nv ${FIRMWARE}
mkdir -p partitions
tar xf $(basename ${FIRMWARE}) -C partitions
./scripts/swap-vendor-modules.sh
