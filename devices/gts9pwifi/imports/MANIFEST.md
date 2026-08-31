# gts9p-imports – provenance

Overlay bundle for building Ubuntu Touch gts9pwifi (SM-X810) on the
azkali android13-5.15-halium tree. Apply with cp -rf, mirroring gts9u-imports:
  kernel-samsung-gts9wifi/. -> $KDIR/     display-drivers/. -> $DDIR/

| Path | Source |
|---|---|
| kernel-.../galaxytab/gts9pwifi/ (Makefile + r00/r02/r04 dts) | SM-X810_13_Opensource_dts.zip (X810XXU1AWG1) |
| display-drivers/msm/samsung/GTS9P_ANA38407_AMSA24VU05/* | SM-X818U_13_Opensource.zip base (AWG1) |
| ... _panel.c, _panel.h (overrides base) | AWH8 delta zip (X810XXU1AWHA generation) |
| display-drivers/msm/samsung/panel_data_file/GTS9P_ANA38407_AMSA24VU05.dat | base (AWG1) |
| display-drivers/msm/Kbuild | azkali msm/Kbuild @ android13-5.15-halium + GTS9P block from base Kbuild (shell vars suffixed _GTS9P; XXD/SED defs deduped) |

Deliberately NOT included (already in azkali tree, proven on the base-S9 port):
- touchscreen driver stm/fts1ba90a (azkali drifts 14 lines in fts_ts.c vs X818U
  base – halium patches; azkali wins)
- wacom wez01 driver (azkali drifts ~148 lines in wacom_i2c.c – azkali wins)
- config fragment: CONFIG_TOUCHSCREEN_STM_FTS1BA90A=m + CONFIG_EPEN_WACOM_WEZ01=m
  already in vendor/kalama-gki_defconfig; the panel config is exported by the
  .conf include in the merged Kbuild. Cmdline retarget is a sed in
  build-gts9pwifi.sh, not an append.

## 2026-08-30 addendum – parity remediation

- `kernel-samsung-gts9wifi/drivers/input/Kconfig` + `Makefile`: ADDED. The
  merged pair from the proven gts9u bundle (wacom wiring only:
  `source "drivers/input/wacom/Kconfig"` + `obj-$(CONFIG_EPEN_WACOM_WEZ01) +=
  wacom/`; zero goodix references – the goodix wiring lives in the separate
  touchscreen/ pair that this bundle intentionally does NOT carry). Without
  these two files the armed `CONFIG_EPEN_WACOM_WEZ01=m` defconfig symbol sits
  inert (Samsung's LEGO build injects the wiring at build time upstream) and
  no `wez01.ko` is ever built. `build-gts9pwifi.sh` now gates on the wiring
  and treats a missing wez01.ko as FATAL.
