#!/usr/bin/env python3
"""Bluetooth (SPP / RFCOMM) GPS host for PUF-mobile.

Reads John Deere 616R GPS/TCM from a CANable (slcan) using the field-proven
PUFworks decoder (PUFworks-isobus/scripts/gps_bridge_lib.py) and serves the
resulting NMEA over a Bluetooth serial link to the tablet. This sidesteps the
tablet's USB-host power/brownout problem: the CANable runs on a mains-powered
host (laptop now, a Pi/standalone later) and only NMEA crosses Bluetooth.

Two Bluetooth transports, auto-picked by platform (override with --transport):

  Linux / Raspberry Pi : a built-in RFCOMM server socket (BlueZ). No PyBluez.
                         The tablet connects to a fixed channel (default 1).
  Windows laptop       : write NMEA to the paired *incoming* Bluetooth COM port
                         with pyserial; the tablet connects as the SPP client.

On the tablet (PUF-mobile): Setup -> GPS -> Bluetooth GPS -> pick the host ->
Connect BT. Status should read "Bluetooth GPS live".

Examples
--------
  # Raspberry Pi appliance: CANable on /dev/ttyACM0, serve RFCOMM channel 1
  sudo python3 bt_gps_host.py --interface /dev/ttyACM0 --bitrate 250000 --channel 1

  # Windows laptop: CANable on COM3, paired incoming Bluetooth COM port = COM5
  python bt_gps_host.py --interface COM3 --bitrate 250000 --bt-serial COM5

  # Test the Bluetooth link with synthetic motion (no CANable / JD needed)
  sudo python3 bt_gps_host.py --demo --channel 1
"""
from __future__ import annotations

import argparse
import math
import os
import socket
import sys
import time

# Reuse the field-validated PUFworks decoder living in the sibling repo.
_ISOBUS_SCRIPTS = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "PUFworks-isobus", "scripts")
)
if _ISOBUS_SCRIPTS not in sys.path:
    sys.path.insert(0, _ISOBUS_SCRIPTS)

_JD_PGNS = (0xFEF3, 0xFEE8, 0xFEE6, 0xFEF1)


# --------------------------------------------------------------------------- #
# Bluetooth transports
# --------------------------------------------------------------------------- #
class RfcommServer:
    """BlueZ RFCOMM server (Linux/Pi). One client at a time; auto re-accepts.

    No SDP record is published, so the tablet connects by channel number (its
    reflection fallback). Make the adapter pairable/discoverable first, e.g.:
        sudo bluetoothctl -- discoverable on
    and pair the tablet to this host once at the OS level.
    """

    def __init__(self, channel: int):
        if not hasattr(socket, "AF_BLUETOOTH"):
            raise RuntimeError("This Python build has no AF_BLUETOOTH (use Linux/Pi).")
        self.channel = channel
        self.srv = socket.socket(
            socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM
        )
        self.srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        bdaddr = getattr(socket, "BDADDR_ANY", "00:00:00:00:00:00")
        self.srv.bind((bdaddr, channel))
        self.srv.listen(1)
        self.client = None
        print(f"[bt] RFCOMM server listening on channel {channel}", flush=True)

    def _accept(self):
        print("[bt] waiting for the tablet to connect...", flush=True)
        self.client, info = self.srv.accept()
        print(f"[bt] tablet connected: {info}", flush=True)

    def send(self, payload: bytes):
        if self.client is None:
            self._accept()
        try:
            self.client.sendall(payload)
        except OSError:
            print("[bt] tablet disconnected", flush=True)
            try:
                self.client.close()
            except OSError:
                pass
            self.client = None

    def close(self):
        for s in (self.client, self.srv):
            try:
                if s:
                    s.close()
            except OSError:
                pass


class WinSerialSink:
    """Windows: write to the paired *incoming* Bluetooth COM port via pyserial.

    Pair the tablet and this PC in Windows Bluetooth settings; under
    'More Bluetooth options -> COM Ports' use the *Incoming* port here. The
    tablet (SPP client) connecting routes its link to that port.
    """

    def __init__(self, port: str, baud: int = 115200):
        try:
            import serial  # pyserial
        except ImportError as e:
            raise RuntimeError("pip install pyserial") from e
        self.ser = serial.Serial(port, baud, timeout=0, write_timeout=2)
        print(f"[bt] writing NMEA to Bluetooth COM {port}", flush=True)

    def send(self, payload: bytes):
        try:
            self.ser.write(payload)
        except Exception as e:  # noqa: BLE001 - port may drop when tablet leaves
            print(f"[bt] COM write failed ({e}); retrying", flush=True)
            time.sleep(0.2)

    def close(self):
        try:
            self.ser.close()
        except Exception:  # noqa: BLE001
            pass


def make_sink(args) -> "RfcommServer | WinSerialSink":
    transport = args.transport
    if transport == "auto":
        transport = "win-serial" if (os.name == "nt" or args.bt_serial) else "rfcomm"
    if transport == "win-serial":
        if not args.bt_serial:
            raise SystemExit("--bt-serial COMx is required for the win-serial transport")
        return WinSerialSink(args.bt_serial)
    return RfcommServer(args.channel)


# --------------------------------------------------------------------------- #
# NMEA sources
# --------------------------------------------------------------------------- #
def _nmea_checksum(body: str) -> str:
    cs = 0
    for ch in body:
        cs ^= ord(ch)
    return f"{cs:02X}"


def _demo_sentences(lat: float, lon: float, course: float, speed_kn: float) -> bytes:
    t = time.gmtime()
    hhmmss = time.strftime("%H%M%S", t)
    ddmmyy = time.strftime("%d%m%y", t)

    def dm(deg, is_lat):
        hemi = ("N" if deg >= 0 else "S") if is_lat else ("E" if deg >= 0 else "W")
        ad = abs(deg)
        d = int(ad)
        m = (ad - d) * 60.0
        width = 2 if is_lat else 3
        return f"{d:0{width}d}{m:07.4f},{hemi}"

    gga_body = (
        f"GPGGA,{hhmmss}.00,{dm(lat, True)},{dm(lon, False)},"
        f"1,12,0.8,150.0,M,0.0,M,,"
    )
    rmc_body = (
        f"GPRMC,{hhmmss}.00,A,{dm(lat, True)},{dm(lon, False)},"
        f"{speed_kn:.1f},{course:.1f},{ddmmyy},,,A"
    )
    out = b""
    for body in (gga_body, rmc_body):
        out += f"${body}*{_nmea_checksum(body)}\r\n".encode("ascii")
    return out


def run_demo(sink, args):
    print("[demo] emitting synthetic motion (5 Hz)", flush=True)
    lat, lon = -33.8688, 151.2093  # arbitrary start
    course = 0.0
    speed_kn = 8.0  # ~15 km/h
    try:
        while True:
            sink.send(_demo_sentences(lat, lon, course, speed_kn))
            # advance ~ speed for 0.2 s along the current course
            dist_m = speed_kn * 0.514444 * 0.2
            lat += (dist_m * math.cos(math.radians(course))) / 111320.0
            lon += (dist_m * math.sin(math.radians(course))) / (
                111320.0 * math.cos(math.radians(lat))
            )
            course = (course + 1.0) % 360.0  # gentle curve so heading is visible
            time.sleep(0.2)
    except KeyboardInterrupt:
        print("\n[demo] stopped", flush=True)


def run_live_can(sink, args):
    try:
        import can  # python-can
    except ImportError:
        raise SystemExit("python-can required for live CAN: pip install python-can")
    from gps_bridge_lib import GpsBridge, nmea_bundle  # field-validated decoder

    channel = args.interface
    bustype = (
        "slcan"
        if channel.upper().startswith("COM") or "/dev/tty" in channel
        else "pcan"
    )
    kwargs = {"channel": channel, "bustype": bustype, "bitrate": args.bitrate}
    if bustype == "slcan":
        kwargs["ttyBaudrate"] = args.tty_baud
    print(f"[can] opening {bustype} {channel} @ {args.bitrate} bps", flush=True)
    bridge = GpsBridge(latlon_mode=args.latlon_mode, big_endian=args.be)
    bus = can.interface.Bus(**kwargs)
    last_log = 0.0
    try:
        for msg in bus:
            if not msg.is_extended_id:
                continue
            pgn = (msg.arbitration_id >> 8) & 0x3FFFF
            sa = msg.arbitration_id & 0xFF
            if pgn not in _JD_PGNS:
                continue
            if pgn in (0xFEF3, 0xFEE8, 0xFEE6) and sa != 0x1C:
                continue
            fix = bridge.update_from_can_id(msg.arbitration_id, bytes(msg.data))
            if fix and fix.valid:
                block = nmea_bundle(fix)
                if block:
                    sink.send(block)
                now = time.time()
                if now - last_log > 5.0:
                    print(
                        f"[gps] lat={fix.latitude:.7f} lon={fix.longitude:.7f} "
                        f"hdg={fix.heading_deg or 0:.0f}",
                        flush=True,
                    )
                    last_log = now
    except KeyboardInterrupt:
        print("\n[can] stopped", flush=True)
    finally:
        bus.shutdown()


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--interface", default="COM3", help="CANable: COMx (Win) or /dev/ttyACM0 (Pi)")
    ap.add_argument("--bitrate", type=int, default=250000, help="CAN bus bps (JD X119 = 250k)")
    ap.add_argument("--tty-baud", type=int, default=2000000, help="slcan USB-serial speed")
    ap.add_argument("--latlon-mode", choices=("jd_atx", "j1939", "raw"), default="jd_atx")
    ap.add_argument("--be", action="store_true", help="Big-endian FEF3 decode")
    ap.add_argument("--transport", choices=("auto", "rfcomm", "win-serial"), default="auto")
    ap.add_argument("--channel", type=int, default=1, help="RFCOMM channel (Linux/Pi)")
    ap.add_argument("--bt-serial", default="", help="Windows incoming Bluetooth COM port (e.g. COM5)")
    ap.add_argument("--demo", action="store_true", help="Emit synthetic motion (no CANable needed)")
    args = ap.parse_args()

    sink = make_sink(args)
    try:
        if args.demo:
            run_demo(sink, args)
        else:
            run_live_can(sink, args)
    finally:
        sink.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
