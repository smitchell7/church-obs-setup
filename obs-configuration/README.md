# OBS Configuration

This folder holds every OBS scene collection, one folder each, and the OBS window layout (`obs-layout.ini`). The setup scripts and the collections update install all of them, then ask which collection OBS opens on:

| # | Folder | Name in OBS | For |
|---|---|---|----|
| 1 | `sacrament-alkire-and-quail` | Sacrament - Alkire and Quail Building | Weekly sacrament meetings |
| 2 | `sacrament-independence` | Sacrament - Independence Building | Weekly sacrament meetings |
| 3 | `stake-meeting-alkire-and-quail` | Stake Meeting - Alkire and Quail Building | Stake broadcasts, run on its own |
| 4 | `stake-meeting-independence` | Stake Meeting - Independence Building | Stake broadcasts, with the control laptop |
| 5 | `stake-meeting-independence-control` | Stake Meeting - Independence Building - Control | The control laptop at a stake broadcast. Used in collaboration with the stake-meeting-independece scene collection to control the cameras |

Any of them can be opened later from OBS's **Scene Collection** menu. The Sacrament and Stake Meeting collections open on Full Room - P3 (Left Full Room - P3 in Independence).

## What every collection has

- **Preset scenes** are named with the camera preset they recall: Pulpit - P0, Chorister - P1, Rostrum - P2, Full Room - P3, Piano - P4, Speaker Close-up - P5, Piano and Pulpit - P6, Organ - P7, Choir - P8. Picking one moves the camera to that preset. The positions themselves are saved in the camera, not in these files.
- **Camera** scenes (Stake Meeting only) show the camera without recalling a preset, so it stays where it is and you steer it with the PTZ Controls dock.
- **Sacrament** plays the sacrament graphic and music, with no microphone. Changing to it switches the Zoom audio from the microphone to the music, and changing back switches it again.
- **Sound** comes from the "USB Audio" source (the Sound Blaster where there is one) in every scene except Sacrament. It starts at -8 dB with four notch filters (hum, squeal and two tones). The cameras' own audio isn't used.

## Alkire and Quail Building

One camera, at 192.168.111.245. Its video comes into OBS over NDI. Audio Comes in VIA USB Audio Card.

**Sacrament - Alkire and Quail Building**
- Scenes: P0 to P8, Sacrament.
- Multiview: Pulpit - P0 and Sacrament.

**Stake Meeting - Alkire and Quail Building**
- Scenes: Camera, P0 to P8, Sacrament, Lower Thirds - Lyrics, Lower Thirds - Speakers, Lower Thirds - Camera.
- Multiview: Camera, Sacrament and the three Lower Thirds.

## Independence Building (Stake Center)

Two cameras, House Left and House Right. Their video comes into the OBS computer through USB video capture devices, not NDI:

| Source | Device | Camera's PTZ address |
|---|---|---|
| **House Left - USB3.0 Video** | USB HDMI capture device (shows as "USB3.0 Video") | 192.168.111.246 |
| **House Right - ATEM Mini** | Blackmagic ATEM Mini (shows as "Blackmagic Design") | 192.168.111.245 |

The preset scenes come as a Left and a Right version ("Left Pulpit - P0", "Right Pulpit - P0", ...). PTZ presets still move the cameras over the network, so the cameras must stay on the network as well as being plugged into the capture devices.

**After setup, pick the capture devices.** The setup scripts can't choose them. On each computer, plug in both devices, open OBS, double-click each source above and pick its **Device**. Do it in each Independence collection. A collections update keeps the devices you picked.

**Sacrament - Independence Building**
- Scenes: Left and Right P0 to P8, Sacrament.
- Multiview: Left Pulpit - P0, Right Pulpit - P0 and Sacrament.

**Stake Meeting - Independence Building**
- Scenes: Left Camera, Right Camera, Left and Right Pulpit - P0, Left and Right Full Room - P3, Sacrament, Blackmagic, Lower Thirds - Lyrics, Lower Thirds - Speakers, Lower Thirds - Camera.
- **Blackmagic** shows the House Right - ATEM Mini source full screen with sound from "USB Audio". Use it for whatever the ATEM Mini is switched to, such as the Rostrum HDMI or video from the work room.
- Multiview: Left Camera, Right Camera, Sacrament, Blackmagic and the three Lower Thirds.
- This is the "main OBS" that the control laptop watches. 

## Lower thirds (Stake Meeting collections)

- **Lower Thirds - Lyrics** and **Lower Thirds - Speakers** are for FreeShow lower thirds snet to OBS over NDI. Pick the FreeShow output on each "Freeshow Lower Thirds" source in OBS. The **Lyrics** and **Speaker Names** downstream keyers show them over the program. Speaker Names hides itself after 20 seconds.
- **Lower Thirds - Camera** puts the camera (Left Camera in Independence) at 25% in the bottom-right corner, shown by the **Video Overlay** keyer.
- The Lower thirds scenes aren't meant for weekly use, but they're ready in the stake meeting collections if a meeting needs them. NDI feeds from FreeShow only works from a Windows or Mac computer on the same network (or the same Windows computer) if the meeiting is being run from a windows computer. FreeShow isn't installed by the setup scripts. Using these scenes needs the Downstream Keyer dock.

## The control laptop (Stake Meeting - Independence Building - Control)

The control laptop shows both cameras and steers them, without being plugged into them. Use it with a 1920x1080 canvas and Studio Mode.

- **Camera Monitor** is a browser source holding `stake-meeting-independence-control/monitor.html` (embedded in the collection, so there is nothing else to install). It connects to the main OBS over its WebSocket and, about 10 times a second, asks for a 960x540 picture of its **Left Camera** and **Right Camera** scenes (or **Joystick Left** and **Joystick Right** on an older collection). The cameras' video is already decoded on the main OBS, so this is quicker than pulling RTSP from the cameras. It's a stream of still pictures, not full-motion video.
- Each camera's panel is outlined **green with PREVIEW** when the main OBS has a Left (or Right) scene in Preview, and **red with LIVE** when one is in Program. The scene names are listed under the pictures. The side comes from the word "Left" or "Right" in the scene name, so preset scenes count too. Scenes with neither word (Sacrament, Blackmagic, Lower Thirds) light up neither panel.
- **Control Left Camera** and **Control Right Camera** (this collection's own two scenes) both show the Camera Monitor. Each has a hidden PTZ control source for its camera (192.168.111.246 for Left, 192.168.111.245 for Right), so the scene you select decides which camera the PTZ dock steers.

**Changing the main OBS's address.** Right-click **Camera Monitor**, choose **Properties**, and edit the **Custom CSS** box:

```css
:root { --main-obs: "192.168.108.4"; --main-obs-port: "4455"; --main-obs-password: "2ne2-14"; }
```

Keep the quotes and click **OK**. The monitor reconnects, and the line under the pictures shows the address it's using. Anything left out of the box falls back to these defaults. The password is the default the setup scripts give the main OBS (Ubuntu or Windows). A collections update puts the defaults back, so set the address again afterwards.

The camera addresses are ordinary PTZ device settings and can be changed in OBS. The scene names, picture rate (`FPS`), size and JPEG quality are at the top of the script in `monitor.html`. Changing those means re-embedding the page in the collection.

**Load on the main OBS:** about 20 pictures a second, each about 60 KB (roughly 10 Mbit/s), and about 13 ms of OBS time. Lower `FPS` to 5 if the main OBS drops frames.

## Window layout (`obs-layout.ini`)

The OBS window layout that setup and the collections update install, captured from the Ubuntu test VM (the same screen size as the church laptops): Scenes, Sources, Audio Mixer, PTZ Controls, Controls and Transitions docked, side docks and the vertical mixer. Downstream Keyer and Stats are closed; open Downstream Keyer from the **Docks** menu to use the lower thirds.

Every setup and update puts the layout back, so docks closed or moved by accident are fixed. Both also turn Studio Mode on every time. To change the layout: arrange OBS, close it, and copy the same lines from `[BasicWindow]` in OBS's `user.ini` into this file.
