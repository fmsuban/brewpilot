# brewpilot_scale

Headless BrewPilot scale firmware (SPEC §7): HX711 + median5/EMA @ 10 Hz,
BLE GATT, NVM calibration. No display or buttons — the iOS Scale tab is
the UI (live weight, tare, units, timer, calibration).

## Build / flash

```bash
cd scale/brewpilot_scale
pio run
pio run -t upload
pio device monitor   # 115200: weight at 10 Hz, `t`=tare `c`=clear-cal
```

Board: `esp32dev` (classic ESP32; use `esp32-s3-devkitc-1` if you have an S3).
Wiring: SPEC §7 (HX711 DT16/SCK4).
