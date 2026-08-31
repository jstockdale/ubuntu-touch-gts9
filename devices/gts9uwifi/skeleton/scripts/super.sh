#!/bin/bash
LPMAKE=${LPMAKE:-lpmake}
command -v ${LPMAKE} >/dev/null || LPMAKE="$(dirname "$0")/prebuilt/lpmake"
SUPER=${SUPER:-"11744051200"}
GROUP=${GROUP:-"ubuntu"}
PARTS=${PARTS:-"./partitions"}
OUT=${OUT:-"./out/super.img"}
SYSTEM=$(stat -c '%s' ./out/ubuntu.img)
SYSTEM_EXT=$(stat -c '%s' ${PARTS}/system_ext.img)
SYSTEM_DLKM=$(stat -c '%s' ${PARTS}/system_dlkm.img)
PRODUCT=$(stat -c '%s' ${PARTS}/product.img)
VENDOR=$(stat -c '%s' ${PARTS}/vendor.img)
VENDOR_DLKM=$(stat -c '%s' ${PARTS}/vendor_dlkm.img)
ODM=$(stat -c '%s' ${PARTS}/odm.img)
METADATA="65536"
QTI=$((${SYSTEM} + ${PRODUCT} + ${VENDOR} + ${ODM} + ${SYSTEM_EXT} + ${SYSTEM_DLKM} + ${VENDOR_DLKM}))

${LPMAKE} \
  --metadata-size ${METADATA} \
  --super-name super \
  --metadata-slots 2 \
  --device super:${SUPER} \
  --group ${GROUP}:${QTI} \
  --partition system:readonly:${SYSTEM}:${GROUP} \
  --image system=./out/ubuntu.img \
  --partition system_ext:readonly:${SYSTEM_EXT}:${GROUP} \
  --image system_ext=${PARTS}/system_ext.img \
  --partition system_dlkm:readonly:${SYSTEM_DLKM}:${GROUP} \
  --image system_dlkm=${PARTS}/system_dlkm.img \
  --partition product:readonly:${PRODUCT}:${GROUP} \
  --image product=${PARTS}/product.img \
  --partition vendor:readonly:${VENDOR}:${GROUP} \
  --image vendor=${PARTS}/vendor.img \
  --partition vendor_dlkm:readonly:${VENDOR_DLKM}:${GROUP} \
  --image vendor_dlkm=${PARTS}/vendor_dlkm.img \
  --partition odm:readonly:${ODM}:${GROUP} \
  --image odm=${PARTS}/odm.img \
  --output ${OUT}
