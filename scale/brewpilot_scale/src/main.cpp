// BrewPilot scale firmware: ESP32 + HX711 BLE scale, headless.
// SPEC.md section 7. Assumes HX711 RATE @ 80 SPS (works slower at 10 SPS).
// All UI lives in the iOS app: tare / calibration / units / timer over BLE.
#include "ble_scale.h"
#include "config.h"
#include "store.h"
#include "weight.h"

Store store;
WeightSensor weight;
BleScale ble;

uint32_t lastTickMs = 0, lastBleMs = 0;
uint32_t seq = 0;
uint32_t stableSinceMs = 0;
float lastStableG = 0;
bool settled = false;

void doTare() {
  weight.tare();
  store.s.offsetRaw = weight.offsetRaw();
  store.save();
  Serial.println("tare");
}

void setup() {
  Serial.begin(115200);
  store.begin();
  weight.begin(PIN_HX_DOUT, PIN_HX_SCK);
  weight.setCalibration(store.s.offsetRaw, store.s.scaleFactor);
  ble.begin();
  stableSinceMs = millis();
  Serial.println("BrewPilot scale ready (t=tare c=clear-cal)");
}

void loop() {
  weight.poll();

  if (Serial.available()) {
    char c = Serial.read();
    while (Serial.available()) Serial.read();
    if (c == 't' || c == 'T')
      doTare();
    else if (c == 'c' || c == 'C') {
      weight.setCalibration(0, 1);
      store.s.offsetRaw = 0;
      store.s.scaleFactor = 1;
      store.save();
      Serial.println("calibration cleared");
    }
  }

  uint32_t now = millis();
  if (now - lastTickMs < OUTPUT_INTERVAL_MS) return;
  lastTickMs = now;

  float g = weight.grams();

  static uint32_t lastWarnMs = 0;
  if (now - weight.lastSampleMs() > 2000 && now - lastWarnMs > 2000) {
    lastWarnMs = now;
    Serial.println("WARN: no HX711 data - check DT->GPIO16 SCK->GPIO4 VCC->3V3 GND");
  }

  if (fabsf(g - lastStableG) > SETTLED_BAND_G) {
    lastStableG = g;
    stableSinceMs = now;
    settled = false;
  } else if (now - stableSinceMs > SETTLED_TIME_MS) {
    settled = true;
  }

  if (ble.takeTare()) doTare();
  float calG;
  if (ble.takeCalib(calG)) {
    if (weight.calibrate(calG) == CalResult::OK) {
      store.s.offsetRaw = weight.offsetRaw();
      store.s.scaleFactor = weight.scaleFactor();
      store.save();
      Serial.printf("calibrated with %.1f g (scale=%.1f counts/g)\n", calG, weight.scaleFactor());
    } else {
      Serial.println("calibration rejected: put the mass on the scale first");
    }
  }

  uint8_t rate = ble.rateHz() ? ble.rateHz() : 10;
  if (ble.streaming() && now - lastBleMs >= 1000U / rate) {
    lastBleMs = now;
    float cgF = constrain(g * 100.0f, -2000000000.0f, 2000000000.0f);
    ble.notifyWeight(seq++, (int32_t)cgF, settled, g > OVERLOAD_G, 100);
  }

  Serial.printf("weight_g=%.2f raw=%.0f flow=%.2f\n", g, weight.rawFiltered(), weight.flowMlS());
}
