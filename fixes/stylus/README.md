# Stylus & Digitizer Fixes for Lenovo Legion Y700 Gen 3 (TB321FU)

## Issues Resolved:
1. **Digitizer Resolution Mismatch:**
   - The Novatek NT36523 pen input was reporting improper axis units, causing the cursor to drift away from the stylus tip or map to only a portion of the screen.
2. **Screen Rotation Disconnect:**
   - In GNOME Wayland, the stylus was identified as an external standalone graphics tablet instead of an integrated on-screen digitizer. When the tablet was rotated into portrait/landscape, the display rotated but the stylus coordinate plane stayed fixed, leading to inverted or sideways pen strokes.

## Solution:
1. `70-y700-stylus.hwdb` overrides `EVDEV_ABS_00` and `EVDEV_ABS_01` axis resolutions to 136 and 135.
2. `70-y700-stylus.rules` sets `ID_INPUT_TABLET_INTEGRATED=1` and binds the device directly to display output `WL_OUTPUT=DSI-1`. GNOME Mutter automatically rotates the digitizer coordinate matrix whenever the screen orientation changes.

## Manual Installation:
```bash
sudo cp 70-y700-stylus.hwdb /etc/udev/hwdb.d/
sudo cp 70-y700-stylus.rules /etc/udev/rules.d/
sudo systemd-hwdb update
sudo udevadm control --reload
sudo udevadm trigger
```
