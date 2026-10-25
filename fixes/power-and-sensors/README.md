# Power & Sensors Configuration for Lenovo Legion Y700 Gen 3 (TB321FU)

## Features:
- Enables ambient light sensor (ALS) auto-brightness in GNOME (`org.gnome.settings-daemon.plugins.power ambient-enabled true`).
- Configures smooth screen dimming on idle.
- Disables aggressive blanking/suspend to prevent deep sleep wake issues on early kernels.

## Manual Installation:
```bash
sudo cp 01-power /etc/dconf/db/local.d/
sudo dconf update
```
