#!/usr/bin/env python3
# gts9u: virtual EV_SW jack device so droid-extevdev's scan finds a match
# on jackless hardware. State stays 0 (unplugged) = speaker route.
import fcntl, os, signal, struct, time
UI_SET_EVBIT  = 0x40045564
UI_SET_SWBIT  = 0x4004556d
UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY= 0x5502
EV_SW = 0x05
SW_HEADPHONE_INSERT = 0x02
SW_MICROPHONE_INSERT= 0x04
SW_LINEOUT_INSERT   = 0x06
f = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(f, UI_SET_EVBIT, EV_SW)
for b in (SW_HEADPHONE_INSERT, SW_MICROPHONE_INSERT, SW_LINEOUT_INSERT):
    fcntl.ioctl(f, UI_SET_SWBIT, b)
dev = struct.pack('80s4HI', b'gts9u-virtual-h2w', 0x06, 0x1, 0x1, 1, 0)
dev += b'\x00' * (64 * 4 * 4)
os.write(f, dev)
fcntl.ioctl(f, UI_DEV_CREATE)
def bye(*a):
    fcntl.ioctl(f, UI_DEV_DESTROY)
    os._exit(0)
signal.signal(signal.SIGTERM, bye)
while True:
    time.sleep(3600)
