# brewpilot_scale

Full BrewPilot scale firmware (SPEC §7): HX711 + median5/EMA @ 10 Hz,
ST7735S UI (MANUAL / AUTO POUR / SET), 2-button control, BLE GATT,
NVM settings, deep sleep.

## Build / flash

```bash
cd scale/brewpilot_scale
pio run
pio run -t upload
pio device monitor   # 115200: weight at 10 Hz, send `t` to tare
```

Board: `esp32-s3-devkitc-1` (change `board =` in platformio.ini if yours differs).
Wiring: SPEC §7 (HX711 DT16/SCK4 · TFT 8–12/15 · buttons 5/6).
Wake from deep sleep: TARE button (ESP32-S3 ext0, single pin).
If the TFT shows wrong colors, try `INITR_GREENTAB` in display_ui.cpp.
