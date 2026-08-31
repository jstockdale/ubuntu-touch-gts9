# gts9u source imports - apply guide

Provenance: SM-X910 EUR OSRC drop dated 2025-05-07 (CYD9-era, same kernel
generation 5.15.153 / KMI 30958166 as the port's X710XXU5CYD9 base;
README build target: gts9uwifi_eur_open, PROJECT_NAME=gts9uwifi).

## Layout = overlay onto the two repos

- kernel-samsung-gts9wifi/ -> gitlab azkali-samsung/gts9/ubports/
  kernel-samsung-gts9wifi (branch android13-5.15-halium)
- display-drivers/         -> .../display-drivers (android13-5.15-halium)

Copy file-for-file. Four files are MERGED complete replacements
(current tree content + additions), the rest are new:

1. drivers/input/Kconfig            +source "drivers/input/wacom/Kconfig"
2. drivers/input/Makefile           +obj-$(CONFIG_EPEN_WACOM_WEZ01) += wacom/
3. drivers/input/touchscreen/Kconfig  +source .../goodix/berlin/Kconfig
4. drivers/input/touchscreen/Makefile +obj-$(CONFIG_TOUCHSCREEN_GOODIX_BRL)
                                       += goodix/berlin/
5. drivers/input/touchscreen/goodix/berlin/   NEW - Samsung sec_input-
   integrated Goodix Berlin (module goodix_ts_berlin - name-matches the
   stock X910 vendor_dlkm module, so swap-vendor-modules replaces it
   automatically). Links against the sec_input core already being built.
6. arch/arm64/boot/dts/samsung/galaxytab/gts9uwifi/  NEW - r00/r03
   flattened DTS (matches the two DTBO board-ids). Only needed when
   rebuilding an Ultra DTBO; stock-dtbo bring-up ignores it. Mirror
   gts9wifi's parent-level inclusion when wiring it.
7. arch/arm64/configs/halium.config.gts9u-append - append these lines to
   halium.config. Note: CONFIG_EPEN_WACOM_WEZ01=m is ALREADY present in
   vendor/kalama-gki_defconfig on BOTH boards; Samsung's LEGO build
   injects the Makefile/Kconfig wiring at build time, which is why the
   symbol sat inert - the static wiring above is the whole S-Pen kernel
   enablement, for gts9uwifi and the gts9wifi backport alike.
8. display-drivers/msm/samsung/GTS9U_ANA38407_AMSA46AS02/  NEW - complete
   panel driver incl. pre-generated _PDF.h.
9. display-drivers/msm/samsung/panel_data_file/GTS9U_ANA38407_AMSA46AS02.dat
10. display-drivers/msm/Kbuild - MERGED: GTS9U block (13 lines, verbatim
    from the X910 drop) inserted directly after the GTS9 block. Both
    panel .conf files export their CONFIG_PANEL_*=y, both panels compile
    into one msm_drm.ko, and Samsung's ss_dsi framework selects the
    active panel at runtime from DT - one display module serves both
    boards.

## Verified requiring NO import (checked against the X910 drop)

- camera-kernel: config/kalama.mk in the existing X710 import already
  carries the gts9u/gts9uwifi PROJECT_NAME sensor branches (4 hits).
  PROJECT_NAME=$deviceinfo_codename does the rest.
- audio-kernel: Makefile.include's family filter includes gts9uwifi;
  one shared kalama_gts9.conf covers all six boards.
- wlan: qcacld-3.0/configs/kiwi_v2_defconfig already present in the
  X710 import; deviceinfo_kernel_wlan_chip="kiwi_v2" (set in the
  skeleton) selects it. Ultra is WCN785x kiwi, not qca6490.

## First-build watchpoints

- goodix/berlin and the GTS9U panel are the two fresh compiles; check
  for LEGO-only header assumptions if either fails.
- drivers/input/wacom/ already exists in the halium tree (byte-compare
  against the X910 copy is an optional sanity step).
- After build: confirm wacom.ko and goodix_ts_berlin.ko in the module
  set; goodix_ts_berlin will name-match into vendor_dlkm via the swap.
