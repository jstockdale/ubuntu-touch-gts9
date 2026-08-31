# Folio touchpad rotation – gts9u-tp-rotate v0.1

The Book Cover Keyboard touchpad (`sec_touchpad_pogo`, stm32 pogo family) is
panel-portrait-native; Lomiri rotates touchscreen coordinates but not pointer
motion, so the pad is 90° off in landscape.

`gts9u-tp-rotate/` (unpacked v0.1 release – its own README has full usage):
EVIOCGRAB + uinput clone daemon; label 270 = landscape default; `.default`
config; systemd unit; `install.sh`. Name-generic – works on any device with a
`sec_touchpad_pogo` input node (all three tablets' folio keyboards).

Proper fix, staged but never flashed: DTS `touchpad,invert <0x01 0x00 0x00>`
(driver `stm,touchpad`, cells `<x_invert y_invert xy_switch>`) baked into a
build – then flip the daemon default 270→0. One-bit mirror risk; verify
on-device. Tracked in PORT-STATE.md §6 #6.

Still broken family-wide (likely upstream Mir/qtmir, not this daemon):
two-finger scroll in Morph, pinch gestures. §6 #16.

Superseded copies (`v0` tarball, loose daemon .py): `archive/superseded/`.
