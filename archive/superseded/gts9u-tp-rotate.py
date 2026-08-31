#!/usr/bin/env python3
# gts9u-tp-rotate v0.1 - folio touchpad orientation shim for Ubuntu Touch (gts9uwifi)
# v0.1: release-flush before any clone teardown; SYN_DROPPED protocol resync.
#
# Grabs the pogo touchpad (default name: sec_touchpad_pogo) exclusively via
# EVIOCGRAB so the compositor stops seeing the raw node, and re-emits every
# event through a uinput clone with a coordinate transform applied.
#
# Transform labels 0/90/180/270 are defined relative to the pad's NATIVE frame
# (which on gts9uwifi is portrait-correct). Which quarter-turn corresponds to
# the shell's landscape is determined empirically, not assumed.
#
# The clone is torn down and recreated on each orientation change because a
# quarter-turn swaps the axis ranges and uinput absinfo is immutable after
# creation. Active contacts and button state are replayed into the new clone.
#
# Control: write 0|90|180|270|status|quit to the FIFO (see --fifo), or use the
# gts9u-tp-orient helper. stdlib only, no third-party deps.

import argparse
import errno
import fcntl
import os
import selectors
import signal
import struct
import sys
import time

# ---------------------------------------------------------------- constants

EV_SYN, EV_KEY, EV_REL, EV_ABS, EV_MSC, EV_SW = 0x00, 0x01, 0x02, 0x03, 0x04, 0x05
SYN_REPORT = 0x00
SYN_DROPPED = 0x03
ABS_X, ABS_Y = 0x00, 0x01
ABS_MT_SLOT = 0x2F
ABS_MT_POSITION_X = 0x35
ABS_MT_POSITION_Y = 0x36
ABS_MT_TRACKING_ID = 0x39

EV_MAX, KEY_MAX, REL_MAX, ABS_MAX = 0x1F, 0x2FF, 0x0F, 0x3F
MSC_MAX, SW_MAX, INPUT_PROP_MAX = 0x07, 0x10, 0x1F

INPUT_EVENT = struct.Struct('<qqHHi')     # timeval(2xlong) + type + code + value
ABSINFO = struct.Struct('<6i')            # value min max fuzz flat resolution

# ---------------------------------------------------------------- ioctl nums


def _ioc(direction, ioc_type, nr, size):
    return (direction << 30) | (size << 16) | (ord(ioc_type) << 8) | nr


def _io(t, nr):
    return _ioc(0, t, nr, 0)


def _iow(t, nr, size):
    return _ioc(1, t, nr, size)


def _ior(t, nr, size):
    return _ioc(2, t, nr, size)


def EVIOCGNAME(n):
    return _ior('E', 0x06, n)


def EVIOCGPROP(n):
    return _ior('E', 0x09, n)


def EVIOCGBIT(ev, n):
    return _ior('E', 0x20 + ev, n)


def EVIOCGABS(code):
    return _ior('E', 0x40 + code, ABSINFO.size)


def EVIOCGKEY(n):
    return _ior('E', 0x18, n)


def EVIOCGMTSLOTS(n):
    return _ior('E', 0x0A, n)


EVIOCGRAB = _iow('E', 0x90, 4)

UI_DEV_CREATE = _io('U', 1)
UI_DEV_DESTROY = _io('U', 2)
UI_DEV_SETUP = _iow('U', 3, 92)           # struct uinput_setup
UI_ABS_SETUP = _iow('U', 4, 28)           # struct uinput_abs_setup
UI_SET_EVBIT = _iow('U', 100, 4)
UI_SET_KEYBIT = _iow('U', 101, 4)
UI_SET_RELBIT = _iow('U', 102, 4)
UI_SET_ABSBIT = _iow('U', 103, 4)
UI_SET_MSCBIT = _iow('U', 104, 4)
UI_SET_SWBIT = _iow('U', 105, 4)
UI_SET_PROPBIT = _iow('U', 110, 4)

UI_SETBIT = {EV_KEY: UI_SET_KEYBIT, EV_REL: UI_SET_RELBIT, EV_ABS: UI_SET_ABSBIT,
             EV_MSC: UI_SET_MSCBIT, EV_SW: UI_SET_SWBIT}

CLONE_NAME = 'gts9u-tp-rotate pad'
VALID_ORIENTS = ('0', '90', '180', '270')

# ---------------------------------------------------------------- utilities


def log(msg):
    print(time.strftime('%F %T'), msg, flush=True)


def fail(msg, hint=None):
    print('FATAL: ' + msg, file=sys.stderr)
    if hint:
        print('  hint: ' + hint, file=sys.stderr)
    sys.exit(1)


def bits_from(buf, maxbit):
    out = set()
    for i in range(maxbit + 1):
        if buf[i >> 3] >> (i & 7) & 1:
            out.add(i)
    return out


def get_bits(fd, ev, maxbit):
    n = maxbit // 8 + 1
    buf = bytearray(n)
    fcntl.ioctl(fd, EVIOCGBIT(ev, n), buf)
    return bits_from(buf, maxbit)


def get_props(fd):
    n = INPUT_PROP_MAX // 8 + 1
    buf = bytearray(n)
    fcntl.ioctl(fd, EVIOCGPROP(n), buf)
    return bits_from(buf, INPUT_PROP_MAX)


def get_name(fd):
    buf = bytearray(256)
    fcntl.ioctl(fd, EVIOCGNAME(len(buf)), buf)
    return buf.split(b'\x00', 1)[0].decode(errors='replace')


def get_absinfo(fd, code):
    buf = bytearray(ABSINFO.size)
    fcntl.ioctl(fd, EVIOCGABS(code), buf)
    return list(ABSINFO.unpack(bytes(buf)))    # [value,min,max,fuzz,flat,res]


def find_device(name):
    try:
        entries = sorted(os.listdir('/dev/input'))
    except FileNotFoundError:
        return None
    for e in entries:
        if not e.startswith('event'):
            continue
        path = '/dev/input/' + e
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            if get_name(fd) == name:
                os.close(fd)
                return path
        except OSError:
            pass
        os.close(fd)
    return None


# ---------------------------------------------------------------- caps model


class Caps:
    def __init__(self, fd):
        self.name = get_name(fd)
        self.ev = get_bits(fd, 0, EV_MAX)
        self.key = get_bits(fd, EV_KEY, KEY_MAX) if EV_KEY in self.ev else set()
        self.rel = get_bits(fd, EV_REL, REL_MAX) if EV_REL in self.ev else set()
        self.abs = get_bits(fd, EV_ABS, ABS_MAX) if EV_ABS in self.ev else set()
        self.msc = get_bits(fd, EV_MSC, MSC_MAX) if EV_MSC in self.ev else set()
        self.sw = get_bits(fd, EV_SW, SW_MAX) if EV_SW in self.ev else set()
        self.prop = get_props(fd)
        self.absinfo = {c: get_absinfo(fd, c) for c in sorted(self.abs)}

    def dump(self):
        log('device "%s"' % self.name)
        log('  EV=%s KEY=%d codes PROP=%s'
            % (sorted(self.ev), len(self.key), sorted(self.prop)))
        for c, a in self.absinfo.items():
            log('  ABS 0x%02x: min=%d max=%d fuzz=%d flat=%d res=%d'
                % (c, a[1], a[2], a[3], a[4], a[5]))


# ---------------------------------------------------------------- transforms
#
# Labels are quarter-turns of the pad frame relative to native. inv() reflects
# a value within its source axis range. Under a swap, an incoming X event is
# emitted as a Y event on the clone (and vice versa), so the map operates on
# (code, value) pairs and remains stateless per event.


def _inv(a, v):
    return a[1] + a[2] - v


def build_maps(caps, orient):
    """Return (event_map, clone_absinfo).
    event_map: code -> (out_code, fn(value) -> value)
    clone_absinfo: code -> absinfo list for the clone device."""
    emap = {}
    cabs = {c: list(a) for c, a in caps.absinfo.items()}
    pairs = []
    if ABS_X in caps.abs and ABS_Y in caps.abs:
        pairs.append((ABS_X, ABS_Y))
    if ABS_MT_POSITION_X in caps.abs and ABS_MT_POSITION_Y in caps.abs:
        pairs.append((ABS_MT_POSITION_X, ABS_MT_POSITION_Y))

    for cx, cy in pairs:
        ax, ay = caps.absinfo[cx], caps.absinfo[cy]
        if orient == '0':
            emap[cx] = (cx, lambda v: v)
            emap[cy] = (cy, lambda v: v)
        elif orient == '180':
            emap[cx] = (cx, lambda v, a=ax: _inv(a, v))
            emap[cy] = (cy, lambda v, a=ay: _inv(a, v))
        elif orient == '90':
            # new_x = inv(y) on the clone X axis (range = ay); new_y = x
            emap[cx] = (cy, lambda v: v)
            emap[cy] = (cx, lambda v, a=ay: _inv(a, v))
            cabs[cx] = list(ay)
            cabs[cy] = list(ax)
        elif orient == '270':
            # new_x = y; new_y = inv(x)
            emap[cx] = (cy, lambda v, a=ax: _inv(a, v))
            emap[cy] = (cx, lambda v: v)
            cabs[cx] = list(ay)
            cabs[cy] = list(ax)
    return emap, cabs


# ---------------------------------------------------------------- uinput


def make_clone(caps, orient):
    _, cabs = build_maps(caps, orient)
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    try:
        for ev in sorted(caps.ev - {EV_SYN}):
            fcntl.ioctl(fd, UI_SET_EVBIT, ev)
        for code in sorted(caps.key):
            fcntl.ioctl(fd, UI_SET_KEYBIT, code)
        for code in sorted(caps.rel):
            fcntl.ioctl(fd, UI_SET_RELBIT, code)
        for code in sorted(caps.msc):
            fcntl.ioctl(fd, UI_SET_MSCBIT, code)
        for code in sorted(caps.sw):
            fcntl.ioctl(fd, UI_SET_SWBIT, code)
        for p in sorted(caps.prop):
            fcntl.ioctl(fd, UI_SET_PROPBIT, p)
        for code in sorted(caps.abs):
            fcntl.ioctl(fd, UI_SET_ABSBIT, code)
            a = cabs[code]
            fcntl.ioctl(fd, UI_ABS_SETUP,
                        struct.pack('<H2x6i', code, 0, a[1], a[2], a[3], a[4], a[5]))
        setup = struct.pack('<HHHH80sI', 0x06, 0x1209, 0x9001, 1,
                            CLONE_NAME.encode(), 0)
        fcntl.ioctl(fd, UI_DEV_SETUP, setup)
        fcntl.ioctl(fd, UI_DEV_CREATE)
    except OSError:
        os.close(fd)
        raise
    return fd


def destroy_clone(fd):
    if fd is None:
        return
    try:
        fcntl.ioctl(fd, UI_DEV_DESTROY)
    except OSError:
        pass
    os.close(fd)


# ---------------------------------------------------------------- daemon


class State:
    """Track raw (source-frame) contact + button state for replay."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.slots = {}          # slot -> [tid, mt_x, mt_y]
        self.cur = 0
        self.keys = {}           # code -> value
        self.st = [None, None]   # last ABS_X / ABS_Y

    def feed(self, etype, code, value):
        if etype == EV_ABS:
            if code == ABS_MT_SLOT:
                self.cur = value
            else:
                slot = self.slots.setdefault(self.cur, [-1, None, None])
                if code == ABS_MT_TRACKING_ID:
                    slot[0] = value
                elif code == ABS_MT_POSITION_X:
                    slot[1] = value
                elif code == ABS_MT_POSITION_Y:
                    slot[2] = value
                elif code == ABS_X:
                    self.st[0] = value
                elif code == ABS_Y:
                    self.st[1] = value
        elif etype == EV_KEY:
            self.keys[code] = value

    def active(self):
        return {s: v for s, v in self.slots.items() if v[0] != -1}


class Daemon:
    def __init__(self, args):
        self.args = args
        self.orient = args.default
        self.src_fd = None
        self.src_path = None
        self.uin_fd = None
        self.caps = None
        self.emap = {}
        self.state = State()
        self.buf = b''
        self.resyncing = False
        self.sel = selectors.DefaultSelector()
        self.fifo_fd = None
        self.running = True

    # ---- source device

    def acquire(self, wait):
        while True:
            path = find_device(self.args.device_name)
            if path:
                break
            if not wait:
                fail('input device "%s" not found' % self.args.device_name,
                     'attach the folio keyboard, or check the name with: '
                     'grep -B1 Handlers /proc/bus/input/devices')
            time.sleep(0.5)
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        try:
            fcntl.ioctl(fd, EVIOCGRAB, 1)
        except OSError as e:
            os.close(fd)
            if e.errno == errno.EBUSY:
                fail('%s is already grabbed - another instance running?' % path,
                     'systemctl status gts9u-tp-rotate; or pkill -f gts9u-tp-rotate')
            raise
        self.src_fd, self.src_path = fd, path
        self.caps = Caps(fd)
        self.caps.dump()
        self.state.reset()
        self.buf = b''
        self.resyncing = False
        self.sel.register(fd, selectors.EVENT_READ, self.on_source)
        log('grabbed %s' % path)

    def release_source(self):
        if self.src_fd is None:
            return
        try:
            self.sel.unregister(self.src_fd)
        except KeyError:
            pass
        try:
            fcntl.ioctl(self.src_fd, EVIOCGRAB, 0)
        except OSError:
            pass
        os.close(self.src_fd)
        self.src_fd = None

    # ---- clone lifecycle

    def rebuild(self, replay=True):
        # Never let the compositor see a device vanish with contacts/buttons
        # down - lift everything on the old clone first.
        self.flush_releases()
        destroy_clone(self.uin_fd)
        self.uin_fd = make_clone(self.caps, self.orient)
        self.emap, _ = build_maps(self.caps, self.orient)
        log('clone up, orient=%s' % self.orient)
        if replay:
            time.sleep(0.3)      # let udev/compositor attach before replaying
            self.replay()

    def flush_releases(self):
        """Emit synthetic release for every contact/button currently down,
        into the existing clone. Orphan releases are harmless downstream."""
        if self.uin_fd is None:
            return
        out = []
        for slot in sorted(self.state.active()):
            out.append((EV_ABS, ABS_MT_SLOT, slot))
            out.append((EV_ABS, ABS_MT_TRACKING_ID, -1))
        for code, val in sorted(self.state.keys.items()):
            if val:
                out.append((EV_KEY, code, 0))
        if out:
            out.append((EV_SYN, SYN_REPORT, 0))
            self.emit(out)
            log('flushed %d release event(s) before teardown' % (len(out) - 1))

    def resync(self):
        """After SYN_DROPPED: rebuild state from kernel ground truth and
        re-assert it on the clone (evdev client protocol)."""
        log('SYN_DROPPED - resyncing from ioctl state')
        try:
            self.flush_releases()
            st = State()
            kbuf = bytearray(KEY_MAX // 8 + 1)
            fcntl.ioctl(self.src_fd, EVIOCGKEY(len(kbuf)), kbuf)
            for c in bits_from(kbuf, KEY_MAX):
                if c in self.caps.key:
                    st.keys[c] = 1
            if ABS_MT_SLOT in self.caps.abs:
                nslots = self.caps.absinfo[ABS_MT_SLOT][2] + 1

                def mtvals(code):
                    buf = bytearray(4 + 4 * nslots)
                    struct.pack_into('<i', buf, 0, code)
                    fcntl.ioctl(self.src_fd, EVIOCGMTSLOTS(len(buf)), buf)
                    return struct.unpack_from('<%di' % nslots, buf, 4)

                tids = mtvals(ABS_MT_TRACKING_ID)
                xs = mtvals(ABS_MT_POSITION_X)
                ys = mtvals(ABS_MT_POSITION_Y)
                for i in range(nslots):
                    if tids[i] != -1:
                        st.slots[i] = [tids[i], xs[i], ys[i]]
                st.cur = get_absinfo(self.src_fd, ABS_MT_SLOT)[0]
            for code, idx in ((ABS_X, 0), (ABS_Y, 1)):
                if code in self.caps.abs:
                    st.st[idx] = get_absinfo(self.src_fd, code)[0]
            self.state = st
            self.replay()
        except OSError as e:
            if e.errno in (errno.ENODEV, errno.EIO):
                self.detached()
            else:
                raise

    def replay(self):
        act = self.state.active()
        if not act and not any(self.state.keys.values()):
            return
        out = []
        for slot, (tid, x, y) in sorted(act.items()):
            out.append((EV_ABS, ABS_MT_SLOT, slot))
            out.append((EV_ABS, ABS_MT_TRACKING_ID, tid))
            if x is not None:
                out.append(self.map_abs(ABS_MT_POSITION_X, x))
            if y is not None:
                out.append(self.map_abs(ABS_MT_POSITION_Y, y))
        for code, val in sorted(self.state.keys.items()):
            if val:
                out.append((EV_KEY, code, val))
        if self.state.st[0] is not None:
            out.append(self.map_abs(ABS_X, self.state.st[0]))
        if self.state.st[1] is not None:
            out.append(self.map_abs(ABS_Y, self.state.st[1]))
        out.append((EV_SYN, SYN_REPORT, 0))
        self.emit(out)
        log('replayed %d active contact(s)' % len(act))

    def map_abs(self, code, value):
        m = self.emap.get(code)
        if m is None:
            return (EV_ABS, code, value)
        return (EV_ABS, m[0], m[1](value))

    def emit(self, events):
        data = b''.join(INPUT_EVENT.pack(0, 0, t, c, v) for t, c, v in events)
        try:
            os.write(self.uin_fd, data)
        except OSError as e:
            log('uinput write failed: %s' % e)

    # ---- event pump

    def on_source(self):
        while True:
            try:
                data = os.read(self.src_fd, INPUT_EVENT.size * 128)
            except BlockingIOError:
                return
            except OSError as e:
                if e.errno in (errno.ENODEV, errno.EIO):
                    self.detached()
                    return
                raise
            if not data:
                self.detached()
                return
            self.buf += data
            out = []
            n = len(self.buf) // INPUT_EVENT.size * INPUT_EVENT.size
            chunk, self.buf = self.buf[:n], self.buf[n:]
            resync_now = False
            for off in range(0, n, INPUT_EVENT.size):
                _, _, etype, code, value = INPUT_EVENT.unpack_from(chunk, off)
                if self.resyncing:
                    # discard everything up to and incl. the next SYN_REPORT
                    if etype == EV_SYN and code == SYN_REPORT:
                        self.resyncing = False
                        resync_now = True
                    continue
                if etype == EV_SYN and code == SYN_DROPPED:
                    self.resyncing = True
                    continue
                self.state.feed(etype, code, value)
                if etype == EV_ABS:
                    out.append(self.map_abs(code, value))
                else:
                    out.append((etype, code, value))
            if out:
                self.emit(out)
            if resync_now:
                self.resync()

    def detached(self):
        log('source vanished (folio detached?) - waiting for reattach')
        self.release_source()
        self.flush_releases()
        destroy_clone(self.uin_fd)
        self.uin_fd = None
        self.state.reset()
        while self.running:
            if find_device(self.args.device_name):
                self.acquire(wait=True)
                self.rebuild(replay=False)
                return
            self.poll_fifo()
            time.sleep(0.5)

    # ---- control fifo

    def setup_fifo(self):
        p = self.args.fifo
        if os.path.exists(p):
            import stat as st
            if not st.S_ISFIFO(os.stat(p).st_mode):
                fail('%s exists and is not a FIFO' % p, 'remove it and restart')
        else:
            os.mkfifo(p)
        os.chmod(p, 0o666)       # local users may rotate the pad; see README
        # O_RDWR keeps a writer open so reads never hit EOF-storm
        self.fifo_fd = os.open(p, os.O_RDWR | os.O_NONBLOCK)
        self.sel.register(self.fifo_fd, selectors.EVENT_READ, self.on_fifo)
        log('control fifo at %s' % p)

    def poll_fifo(self):
        try:
            data = os.read(self.fifo_fd, 4096)
        except (BlockingIOError, OSError):
            return
        self.handle_commands(data)

    def on_fifo(self):
        try:
            data = os.read(self.fifo_fd, 4096)
        except (BlockingIOError, OSError):
            return
        self.handle_commands(data)

    def handle_commands(self, data):
        for line in data.decode(errors='replace').split('\n'):
            cmd = line.strip()
            if not cmd:
                continue
            if cmd in VALID_ORIENTS:
                if cmd == self.orient:
                    log('orient already %s' % cmd)
                    continue
                self.orient = cmd
                if self.src_fd is not None:
                    self.rebuild()
            elif cmd == 'status':
                log('status: orient=%s src=%s clone=%s contacts=%d'
                    % (self.orient, self.src_path or 'detached',
                       'up' if self.uin_fd is not None else 'down',
                       len(self.state.active())))
            elif cmd == 'quit':
                log('quit requested')
                self.running = False
            else:
                log('unknown command %r (want 0|90|180|270|status|quit)' % cmd)

    # ---- lifecycle

    def run(self):
        self.acquire(wait=self.args.wait)
        self.rebuild(replay=False)
        self.setup_fifo()
        log('ready - default orient=%s' % self.orient)
        while self.running:
            for key, _ in self.sel.select(timeout=1.0):
                key.data()
                if not self.running:
                    break
        self.shutdown()

    def shutdown(self):
        log('shutting down')
        self.release_source()
        self.flush_releases()
        destroy_clone(self.uin_fd)
        self.uin_fd = None
        if self.fifo_fd is not None:
            try:
                self.sel.unregister(self.fifo_fd)
            except KeyError:
                pass
            os.close(self.fifo_fd)


# ---------------------------------------------------------------- modes


def prereqs():
    if os.geteuid() != 0:
        fail('must run as root (needs /dev/uinput and EVIOCGRAB)',
             'sudo gts9u-tp-rotate ...')
    if not os.path.exists('/dev/uinput'):
        fail('/dev/uinput missing',
             'modprobe uinput - if that fails the kernel lacks CONFIG_UINPUT')
    try:
        fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
        os.close(fd)
    except OSError as e:
        fail('cannot open /dev/uinput: %s' % e)
    if not os.path.isdir('/dev/input'):
        fail('/dev/input missing - no evdev support?')


def run_check(args):
    prereqs()
    path = find_device(args.device_name)
    if not path:
        fail('input device "%s" not found - attach the folio and retry'
             % args.device_name)
    print('device: %s' % path)
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    caps = Caps(fd)
    caps.dump()
    fcntl.ioctl(fd, EVIOCGRAB, 1)
    print('grab: OK')
    fcntl.ioctl(fd, EVIOCGRAB, 0)
    print('release: OK')
    for orient in VALID_ORIENTS:
        ufd = make_clone(caps, orient)
        destroy_clone(ufd)
        print('clone create/destroy orient=%s: OK' % orient)
    os.close(fd)
    print('check: ALL OK')


def main():
    ap = argparse.ArgumentParser(description='gts9u folio touchpad rotation shim')
    ap.add_argument('--device-name', default='sec_touchpad_pogo',
                    help='evdev device name to grab (default: %(default)s)')
    ap.add_argument('--default', default='0', choices=VALID_ORIENTS,
                    help='orientation at startup (default: %(default)s)')
    ap.add_argument('--fifo', default='/run/gts9u-tp-rotate.ctl',
                    help='control FIFO path (default: %(default)s)')
    ap.add_argument('--wait', action='store_true',
                    help='wait for the device instead of failing fast')
    ap.add_argument('--check', action='store_true',
                    help='validate prerequisites and device, then exit')
    args = ap.parse_args()

    if args.check:
        run_check(args)
        return

    prereqs()
    d = Daemon(args)

    def on_term(signum, frame):
        d.running = False

    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)
    d.run()


if __name__ == '__main__':
    main()
