# BrewPilot scale firmware

Headless ESP32 + HX711 BLE scale. Full contract in `SPEC.md` §7 (wiring,
GATT profile, 10-byte packet, signal chain, calibration).

All UI lives in the iOS app's Scale tab: live weight, tare, g/oz units,
timer with auto-start, and the calibration wizard.

## Projects

- `brewpilot_scale/` — firmware: HX711 + median5/EMA @ 10 Hz, BLE GATT,
  NVM calibration. Serial prints weight at 10 Hz for bring-up
  (send `t` to tare, `c` to clear a bad calibration).

## Quick commands

```bash
cd scale/brewpilot_scale
pio run            # build
pio run -t upload  # flash
pio device monitor # 115200 baud: t=tare
```

## Wiring reminder

HX711 `VCC→3V3, GND→GND, DT→GPIO16, SCK→GPIO4`, RATE pad to 3V3 (80 SPS).
Load cell red `E+`, black `E−`, green `A+`, white `A−` (verify if wild).
