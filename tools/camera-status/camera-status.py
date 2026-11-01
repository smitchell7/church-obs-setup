#!/usr/bin/env python3
"""Ask each PTZ camera whether it is powered on.

Sends each camera the VISCA power inquiry (81 09 04 00 FF) over TCP and prints ON or STANDBY. The
cameras are the single or dual set in cameras.json, next to this script, or the ones given with
--host. OBS and its scene collections are not used. With --toggle, each camera in standby is
turned on and each one that is on is put in standby.

Exit status: 0 when every camera answered, 1 when any could not be reached or gave no answer.
"""
import argparse
import json
import os
import socket
import sys

CAMERAS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cameras.json")
DEFAULT_PORT = 5678
POWER_INQ = bytes.fromhex("81090400ff")
POWER_STATES = {0x02: "ON", 0x03: "STANDBY", 0x04: "POWER ERROR"}
POWER_SET = {  # with --toggle: the command for each state, which switches to the other one
    0x03: bytes.fromhex("8101040002ff"),  # in standby: power on
    0x02: bytes.fromhex("8101040003ff"),  # on: standby
}


def cameras(setup, path):
    """(name, host, port) for each camera of the single or dual set in cameras.json"""
    with open(path, encoding="utf-8-sig") as f:
        data = json.load(f)
    return [(c.get("name", c["host"]), c["host"], int(c.get("port", DEFAULT_PORT))) for c in data[setup]]


def host_camera(text):
    """(name, host, port) for a --host of HOST or HOST:PORT"""
    host, _, port = text.partition(":")
    return (host, host, int(port) if port else DEFAULT_PORT)


def packets(sock):
    """The camera's replies, one VISCA packet (ending in FF) at a time"""
    buf = b""
    while True:
        while b"\xff" not in buf:
            chunk = sock.recv(64)
            if not chunk:
                raise ConnectionError("the camera closed the connection")
            buf += chunk
        end = buf.index(b"\xff") + 1
        packet, buf = buf[:end], buf[end:]
        if len(packet) >= 3 and packet[1] & 0xf0 == 0x60:  # y0 6z ee FF: an error
            raise ConnectionError("the camera answered with VISCA error " + packet.hex(" "))
        yield packet


def power_state(host, port, timeout, toggle=False):
    """The camera's answer to the power inquiry, and with toggle, what was done about it:
    a camera in standby is turned on, and one that is on is put in standby."""
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(POWER_INQ)
        replies = packets(sock)
        for packet in replies:
            if len(packet) == 4 and packet[1] == 0x50:  # y0 50 0p FF: the inquiry's answer
                break
        state = POWER_STATES.get(packet[2], "UNKNOWN (%s)" % packet.hex(" "))
        if not toggle or packet[2] not in POWER_SET:
            return state, None
        sock.sendall(POWER_SET[packet[2]])
        action = "turned on" if packet[2] == 0x03 else "put in standby"
        # y0 4z FF says the camera took the command, y0 5z FF that it has carried it out. A camera
        # can take a while to power up, so a command it took but has not finished still counts.
        accepted = False
        try:
            for packet in replies:
                if len(packet) == 3 and packet[1] & 0xf0 == 0x40:
                    accepted = True
                elif len(packet) == 3 and packet[1] & 0xf0 == 0x50:
                    return state, action
        except socket.timeout:
            if not accepted:
                raise
        return state, action + " (still finishing)"


def main():
    ap = argparse.ArgumentParser(description="Show whether each PTZ camera is on or in standby.")
    ap.add_argument("setup", nargs="?", choices=["single", "dual", "single-camera", "dual-camera"],
                    help="which cameras in cameras.json to ask: single or dual")
    ap.add_argument("--host", action="append", default=[], metavar="HOST[:PORT]",
                    help="ask this camera instead (port %d unless given); can be given more than once"
                    % DEFAULT_PORT)
    ap.add_argument("--cameras", default=CAMERAS_FILE, help="read the cameras from this file instead")
    ap.add_argument("--timeout", type=float, default=3.0, help="seconds to wait for each camera (3)")
    ap.add_argument("--toggle", action="store_true",
                    help="turn on each camera that is in standby, and put each one that is on in standby")
    args = ap.parse_args()

    if args.host:
        found = [host_camera(h) for h in args.host]
    elif args.setup:
        found = cameras(args.setup.replace("-camera", ""), args.cameras)
        print("Cameras from " + args.cameras)
    else:
        ap.error("say which cameras to ask: single, dual, or --host")
    ok = True
    for source, host, port in found:
        try:
            state, action = power_state(host, port, args.timeout, args.toggle)
            if action:
                state += ", " + action
        except (OSError, ConnectionError) as e:
            state, ok = "NO ANSWER (%s)" % (str(e) or "timed out"), False
        print("  %s (%s:%d): %s" % (source, host, port, state))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
