# Ethernet hardware ID configuration

How to make an OBS computer get the same IP address every time, so the control laptop and other tools can always find it. Ubuntu only.

There are two parts:

1. **On the computer:** make its wired connection always use one fixed MAC address (its hardware ID), whichever USB network adapter is plugged in.
2. **In the router:** add a DHCP reservation, so that MAC address always gets the same IP.

Nothing else on the computer changes. It still gets its address from the router (DHCP), so there's no static IP to set up and nothing to clash.

---

## 1. On the computer

Plug in the wired network cable and open a terminal.

**Find the wired adapter and its MAC address:**

```bash
nmcli device status
```

The wired adapter is the `ethernet` line. USB adapters are named like `enx...` and the internal port like `enp...`. Note its name, then run:

```bash
DEV=enx...        # the name from the line above
ip link show "$DEV" | awk '/link\/ether/ {print $2}'
nmcli -g GENERAL.CONNECTION device show "$DEV"
```

The first command prints the MAC address (for example `6c:6e:07:52:3f:e0`). The second prints the connection's name (usually `Wired connection 1`).

**Make that connection always use that MAC, on any adapter:**

```bash
MAC=6C:6E:07:52:3F:E0           # the MAC from above
CON="Wired connection 1"        # the connection name from above
sudo nmcli connection modify "$CON" \
    802-3-ethernet.cloned-mac-address "$MAC" \
    802-3-ethernet.mac-address "" \
    connection.interface-name ""
sudo nmcli connection up "$CON"
```

What this does:
- `cloned-mac-address`: the connection always presents this MAC to the network.
- Clearing `mac-address` and `interface-name` means the connection isn't tied to one adapter. If the USB adapter is ever swapped, the new one uses the same MAC, so the reservation keeps working.

**Check it worked:**

```bash
nmcli -g 802-3-ethernet.cloned-mac-address,connection.interface-name connection show "$CON"
ip -4 addr show "$DEV" | grep inet
```

The first command should print the MAC, followed by an empty interface name. The second shows the IP the computer has now.

> Each computer needs its **own** MAC. Never put the same one on two computers. Using the adapter's own MAC, as above, makes sure of that.

---

## 2. In the router

Add a **DHCP reservation** (some routers call it a "static lease" or an "address reservation"):

- **MAC address:** the MAC from step 1.
- **IP address:** the address the computer has now (from the check above) is simplest. Otherwise pick a free one in the church network (192.168.108.0 – 192.168.111.255, gateway 192.168.108.1) that no other computer or camera uses.

Save it. Then unplug the network cable and plug it back in (or restart the computer), and check that the computer gets the reserved IP:

```bash
ip -4 addr show "$DEV" | grep inet
```

If the computer is the main OBS computer that a control laptop connects to, make sure the control laptop's OBS uses this IP.

---

## Wi-Fi

This covers the wired connection only. Wi-Fi is left automatic. A Wi-Fi reservation would need its own MAC and its own IP.
