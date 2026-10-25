# Audio Fixes for Lenovo Legion Y700 Gen 3 (TB321FU)

## Issues Resolved:
1. **Audio Loss on External USB-C Monitor (DP Alt Mode):**
   - **Root cause:** In Snapdragon 8 Gen 3 (SM8650) hardware, the DisplayPort Alt Mode AUX channel uses Type-C SBU pins, which share lines with the Qualcomm WCD939x analog audio MBHC (Multi-Button Headset Control) impedance detector.
   - When a Type-C monitor or dock was plugged in, MBHC falsely triggered a `Headphone Jack = on` event.
   - The stock ALSA UCM profile configured `JackHWMute "Speaker"`, immediately muting the tablet's internal speakers.
   - Simultaneously, the fallback `Headphones` profile looked for a non-existent mixer element `HP`, causing WirePlumber / PipeWire to fail activation and fall back to dummy output (`auto_null`), leaving 0 sound sinks.
2. **YouTube Video Playback Freezing / Endless Loading:**
   - Because PipeWire was hanging when waiting for an active audio sink, HTML5 video decoders in web browsers (Firefox / Chromium) blocked video rendering. Restoring the audio sink resolved video playback immediately.

## Fix Applied:
- Removed `JackHWMute "Speaker"` from [`HiFi.conf`](./LenovoY700TB321/HiFi.conf).
- Removed non-existent `PlaybackMixerElem "HP"`.
- Set `Speaker` playback priority to `200` and `Mic1` capture priority to `200`.
- Ensured internal stereo speakers and microphone remain active and available at all times.

## Manual Installation:
```bash
sudo cp -r LenovoY700TB321 /usr/share/alsa/ucm2/
sudo mkdir -p /usr/share/alsa/ucm2/conf.d/snd_soc_sc8280xp/
sudo cp conf.d/snd_soc_sc8280xp/Lenovo-Y700-TB321FU.conf /usr/share/alsa/ucm2/conf.d/snd_soc_sc8280xp/
systemctl --user restart pipewire wireplumber
```
