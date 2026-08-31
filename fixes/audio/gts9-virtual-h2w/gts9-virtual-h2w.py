#!/usr/bin/env python3
# Copyright (c) 2026 John Stockdale and Off by One, Inc.
# BSD 3-Clause License - see LICENSE at the repository root.
# Virtual headset jack for jackless devices - stops droid-extevdev
# (pulseaudio-modules-droid 14.2.107..14.2.109) from aborting PulseAudio.
# Switch state stays 0 (unplugged) = speaker route.
# Validated on Samsung Galaxy Tab S9 (gts9wifi), UT 24.04, 2026-08-10.
import fcntl, os, signal, struct
UI_SET_EVBIT  = 0x40045564  # _IOW('U',100,int)
UI_SET_SWBIT  = 0x4004556D  # _IOW('U',109,int)
UI_DEV_SETUP  = 0x405C5503  # _IOW('U',3,uinput_setup)
UI_DEV_CREATE = 0x00005501
EV_SW = 0x05
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_SW)
for sw in (0x02, 0x04, 0x06):  # HEADPHONE, MICROPHONE, LINEOUT insert
    fcntl.ioctl(fd, UI_SET_SWBIT, sw)
fcntl.ioctl(fd, UI_DEV_SETUP,
            struct.pack("<HHHH80sI", 0x06, 0x1D6B, 0x0104, 1, b"gts9-virtual-h2w", 0))
fcntl.ioctl(fd, UI_DEV_CREATE)
signal.pause()
