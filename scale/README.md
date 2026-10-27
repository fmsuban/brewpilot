# BrewPilot scale firmware

ESP32 + HX711 BLE scale. Full contract in `SPEC.md` §7 (wiring, GATT profile,
10-byte packet, signal chain, calibration).

## Projects

- `brewpilot_scale/` — full firmware: HX711 + median5/EMA @ 10 Hz, ST7735S UI
  (MANUAL/AUTO/SET), 2-button control, BLE GATT, NVM, deep sleep.
  Serial prints weight at 10 Hz for bring-up (send `t` to tare).

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
TFT ST7735S: `SCK→GPIO12, MOSI→GPIO11, CS→GPIO10, DC→GPIO9, RST→GPIO8, BL→GPIO15`.
Buttons (active-low): `TARE→GPIO5, TIMER→GPIO6`.
