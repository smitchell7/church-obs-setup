#!/usr/bin/env python3
"""Ask each PTZ camera whether it is powered on, then offer to turn them all on or put them in standby.

Sends each camera the VISCA power inquiry (81 09 04 00 FF) over TCP and prints ON or STANDBY. The
cameras are the ones in cameras.json, next to this script, or the ones given with --host. OBS and
its scene collections are not used. When only the first camera (192.168.111.245) answers, the
church has one camera: it is shown as "PTZ Camera". Otherwise each camera that answers is shown by
its name, PTZ Left and PTZ Right, and each one that does not as "Error: PTZ Left not found". A menu
then asks whether to change nothing, set every camera on, or set every camera to standby; only the
cameras found are changed. --set on or --set standby does that without the menu. With no answer to
read (input that has run out), the menu changes nothing.

Exit status: 0 when every camera answered (or the one camera of a single-camera church did), 1 when
any was not found or gave no answer.
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
ON, STANDBY = 0x02, 0x03
POWER_SET = {  # the command that puts the camera in each state
    ON: bytes.fromhex("8101040002ff"),
    STANDBY: bytes.fromhex("8101040003ff"),
}
ACTIONS = {ON: "turned on", STANDBY: "put in standby"}
TARGETS = {"on": ON, "standby": STANDBY}
MENU = [("No change", None), ("Set on", "on"), ("Set standby", "standby")]
SINGLE_NAME = "PTZ Camera"  # the camera's name when it is the only one that answers


def cameras(path):
    """(name, host, port) for each camera in cameras.json"""
    with open(path, encoding="utf-8-sig") as f:
        data = json.load(f)
    return [(c.get("name", c["host"]), c["host"], int(c.get("port", DEFAULT_PORT))) for c in data]


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


def power_state(host, port, timeout, change=None):
    """The camera's answer to the power inquiry, and what was done about it. change is None to
    only ask, or "on" or "standby" to put the camera in that state whatever it was in."""
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(POWER_INQ)
        replies = packets(sock)
        for packet in replies:
            if len(packet) == 4 and packet[1] == 0x50:  # y0 50 0p FF: the inquiry's answer
                break
        code = packet[2]
        state = POWER_STATES.get(code, "UNKNOWN (%s)" % packet.hex(" "))
        target = TARGETS.get(change)
        if target is None:
            return state, None
        sock.sendall(POWER_SET[target])
        action = ACTIONS[target] + (" (it already was)" if code == target else "")
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


def report(found, timeout, change=None):
    """Print each camera's power state, and what was done about it; True if every camera answered"""
    ok = True
    for camera, (state, answered) in zip(found, ask(found, timeout, change)):
        show(camera, state)
        ok = ok and answered
    return ok


def ask(found, timeout, change=None):
    """(what the camera said, whether it answered) for each camera"""
    results = []
    for _, host, port in found:
        try:
            state, action = power_state(host, port, timeout, change)
            results.append((state + (", " + action if action else ""), True))
        except (OSError, ConnectionError) as e:
            results.append(("NO ANSWER (%s)" % (str(e) or "timed out"), False))
    return results


def show(camera, state):
    name, host, port = camera
    print("  %s (%s:%d): %s" % (name, host, port, state))


def present(found, results):
    """The cameras that answered, with what each said, and the ones that did not. A church with
    one camera has it at the first address: when that is the only one to answer, it is named PTZ
    Camera and the others are not missing. Any other camera that is the only one to answer keeps
    its name, PTZ Right, and the first one is missing."""
    answered = [(cam, r) for cam, r in zip(found, results) if r[1]]
    missing = [cam for cam, r in zip(found, results) if not r[1]]
    if len(answered) == 1 and answered[0][0] == found[0]:
        (_, host, port), result = answered[0]
        return [((SINGLE_NAME, host, port), result)], []
    return answered, missing


def show_missing(missing):
    for name, host, _ in missing:
        print("  Error: %s not found. Check that %s is plugged in, connected to the network and at its "
              "address (%s)" % (name, name, host))


def menu():
    """The change picked from the menu: None for no change, "on", or "standby"."""
    print()
    for number, (label, _) in enumerate(MENU, 1):
        print("  %d. %s" % (number, label))
    while True:
        try:
            choice = input("Choose 1-%d: " % len(MENU)).strip()
        except EOFError:
            return None
        if choice.isdigit() and 1 <= int(choice) <= len(MENU):
            return MENU[int(choice) - 1][1]
        print("Enter a number from 1 to %d." % len(MENU))


def main():
    ap = argparse.ArgumentParser(description="Show whether each PTZ camera is on or in standby, "
                                             "then offer to set them all on or to standby.")
    ap.add_argument("--host", action="append", default=[], metavar="HOST[:PORT]",
                    help="ask this camera instead (port %d unless given); can be given more than once"
                    % DEFAULT_PORT)
    ap.add_argument("--cameras", default=CAMERAS_FILE, help="read the cameras from this file instead")
    ap.add_argument("--timeout", type=float, default=3.0, help="seconds to wait for each camera (3)")
    ap.add_argument("--set", choices=["on", "standby"],
                    help="turn every camera on, or put every camera in standby, without the menu")
    args = ap.parse_args()

    if args.host:
        found = [host_camera(h) for h in args.host]
    else:
        found = cameras(args.cameras)
        print("Cameras from " + args.cameras)

    results = ask(found, args.timeout)
    answered, missing = present(found, results)
    if not answered:  # no camera to show or change
        for camera, (state, _) in zip(found, results):
            show(camera, state)
        return 1
    cams = [cam for cam, _ in answered]
    if args.set:
        ok = report(cams, args.timeout, args.set)
        show_missing(missing)
        return 0 if ok and not missing else 1
    for camera, (state, _) in answered:
        show(camera, state)
    show_missing(missing)
    change = menu()
    if change is None:
        return 0 if not missing else 1
    print()
    ok = report(cams, args.timeout, change)
    show_missing(missing)
    return 0 if ok and not missing else 1


if __name__ == "__main__":
    sys.exit(main())
