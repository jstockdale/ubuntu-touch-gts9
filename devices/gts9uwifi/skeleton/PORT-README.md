gts9uwifi device skeleton - generated 2026-08-03 from samsung-gts9 (halium-13)
Verified inputs: X910XXS5CYG1 PIT (SUPER=11744051200, RECOVERY=109576192),
stock LP layout, vendor identity gts9uwifi/SM-X910, stock kernel
5.15.153-android13-8-30958166-abX910XXS5CYG1, DTBO board-ids 00/03.
Done here: codename rename, deviceinfo, super.sh SUPER size, update-binary
assertion, overlay renames, S-Pen udev rule + kernel config notes.
TODO (needs SM-X910 OSRC drop): GTS9U_ANA38407_AMSA46AS02 panel import into
display-drivers; goodix_ts_berlin driver import; gts9u DTS import (optional,
stock dtbo path works for bring-up); wacom Kconfig wiring; regenerate pulse
XMLs from X910 vendor audio configs; bench-verify wez01_gts9u.bin fw load,
pen input name, calibration matrix, ro.boot slot handling in TWRP.
