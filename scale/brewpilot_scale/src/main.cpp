// BrewPilot scale firmware: HX711 + ST7735S UI + 2 buttons + BLE.
// SPEC.md section 7. Assumes HX711 RATE @ 80 SPS (works slower at 10 SPS).
#include <esp_sleep.h>

#include "ble_scale.h"
#include "buttons.h"
#include "config.h"
#include "display_ui.h"
#include "store.h"
#include "weight.h"

enum : uint8_t { MODE_MANUAL = 0, MODE_AUTO = 1, MODE_SET = 2 };
enum : uint8_t { SET_UNITS = 0, SET_CALIB, SET_BLE, SET_BRIGHT, SET_OFF, SET_N };

const char* MODE_NAMES[] = {"MANUAL", "AUTO", "SET"};
const char* SET_NAMES[] = {"Units", "Calibrate", "BLE", "Bright", "AutoOff"};
const float CAL_PRESETS[] = {100, 200, 500};

Store store;
WeightSensor weight;
Buttons buttons;
DisplayUi ui;
BleScale ble;

uint8_t mode = MODE_MANUAL;
uint8_t prevMode = MODE_MANUAL;
uint8_t setItem = 0;
uint8_t calStep = 0;  // 0 off, 1 empty-confirm, 2 place-mass
uint8_t calPresetIdx = 1;

bool timerRunning = false;
uint32_t timerStartMs = 0, timerAccumMs = 0;
float autoBaseG = 0;

uint32_t lastTickMs = 0, lastBleMs = 0, lastInteractionMs = 0;
uint32_t seq = 0;
uint32_t stableSinceMs = 0;
float lastStableG = 0;
bool settled = false;

char msg[24] = "";
uint32_t msgUntilMs = 0;

uint32_t timerMs() { return timerAccumMs + (timerRunning ? millis() - timerStartMs : 0); }

void say(const char* m, uint32_t ms = 2000) {
  strncpy(msg, m, sizeof(msg) - 1);
  msg[sizeof(msg) - 1] = 0;
  msgUntilMs = millis() + ms;
}

void doTare() {
  weight.tare();
  store.s.offsetRaw = weight.offsetRaw();
  store.save();
  say("TARE");
}

void toggleUnits() {
  store.s.units ^= 1;
  store.save();
  say(store.s.units ? "OZ" : "GRAMS");
}

void enterMode(uint8_t m) {
  if (mode != MODE_SET) prevMode = mode;
  mode = m;
  setItem = 0;
  calStep = 0;
  if (m != MODE_SET) {
    store.s.mode = m;
    store.save();
  }
  if (m == MODE_AUTO) {
    autoBaseG = weight.grams();
    say("TARE? POUR");
  } else {
    say(MODE_NAMES[m]);
  }
}

void exitSet() {
  mode = prevMode;
  calStep = 0;
  say(MODE_NAMES[mode]);
}

void goSleep() {
  store.save();
  ui.render(weight.grams(), store.s.units == 1, timerMs(), false, 0, "SLEEP", false, "");
  delay(400);
  ble.setEnabled(false);
  digitalWrite(PIN_TFT_BL, LOW);
  esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_BTN_TARE, 0);
  esp_deep_sleep_start();
}

void adjustSetItem() {
  switch (setItem) {
    case SET_UNITS:
      toggleUnits();
      break;
    case SET_CALIB:
      calStep = 1;
      say("EMPTY? TARE");
      break;
    case SET_BLE:
      store.s.bleEnabled = !store.s.bleEnabled;
      ble.setEnabled(store.s.bleEnabled);
      store.save();
      say(store.s.bleEnabled ? "BLE ON" : "BLE OFF");
      break;
    case SET_BRIGHT: {
      uint8_t b = store.s.brightness;
      b = (b < 140) ? 140 : (b < 200) ? 200 : (b < 255) ? 255 : 80;
      store.s.brightness = b;
      ui.setBrightness(b);
      store.save();
      break;
    }
    case SET_OFF:
      store.s.autoOffMin = (store.s.autoOffMin == 5) ? 10 : (store.s.autoOffMin == 10) ? 30 : 5;
      store.save();
      break;
  }
}

void setValueText(char* buf, size_t n) {
  switch (setItem) {
    case SET_UNITS:
      snprintf(buf, n, "%s", store.s.units ? "oz" : "g");
      break;
    case SET_CALIB:
      snprintf(buf, n, "go");
      break;
    case SET_BLE:
      snprintf(buf, n, "%s", store.s.bleEnabled ? "on" : "off");
      break;
    case SET_BRIGHT:
      snprintf(buf, n, "%u", store.s.brightness);
      break;
    case SET_OFF:
      snprintf(buf, n, "%u min", store.s.autoOffMin);
      break;
  }
}

void handleButton(BtnEvent e) {
  lastInteractionMs = millis();
  bool inSet = (mode == MODE_SET);
  switch (e) {
    case BtnEvent::TARE_SHORT:
      if (inSet && calStep == 0) {
        store.save();
        exitSet();
      } else if (inSet && calStep == 1) {
        weight.tare();
        store.s.offsetRaw = weight.offsetRaw();
        calStep = 2;
        say("PLACE MASS");
      } else if (inSet && calStep == 2) {
        weight.calibrate(CAL_PRESETS[calPresetIdx]);
        store.s.offsetRaw = weight.offsetRaw();
        store.s.scaleFactor = weight.scaleFactor();
        store.save();
        calStep = 0;
        say("CAL SAVED");
      } else {
        doTare();
      }
      break;
    case BtnEvent::TARE_LONG:
      if (inSet && calStep == 0)
        exitSet();
      else if (!inSet)
        toggleUnits();
      break;
    case BtnEvent::TIMER_SHORT:
      if (inSet && calStep == 0) {
        adjustSetItem();
      } else if (inSet && calStep == 2) {
        calPresetIdx = (calPresetIdx + 1) % 3;
      } else if (!inSet) {
        if (timerRunning) {
          timerAccumMs = timerMs();
          timerRunning = false;
        } else if (timerMs() > 0) {
          timerAccumMs = 0;
          autoBaseG = weight.grams();
        } else {
          timerRunning = true;
          timerStartMs = millis();
        }
      }
      break;
    case BtnEvent::TIMER_LONG:
      if (inSet && calStep == 0)
        setItem = (setItem + 1) % SET_N;
      else if (!inSet)
        enterMode((mode + 1) % 3);  // MANUAL -> AUTO -> SET
      break;
    case BtnEvent::COMBO_LONG:
      goSleep();
      break;
    default:
      break;
  }
}

void setup() {
  Serial.begin(115200);
  store.begin();
  mode = (store.s.mode > 1) ? (uint8_t)MODE_MANUAL : store.s.mode;
  prevMode = mode;
  weight.begin(PIN_HX_DOUT, PIN_HX_SCK);
  weight.setCalibration(store.s.offsetRaw, store.s.scaleFactor);
  buttons.begin(PIN_BTN_TARE, PIN_BTN_TIMER);
  ui.begin(store.s.brightness);
  ble.setEnabled(store.s.bleEnabled);
  lastInteractionMs = millis();
  stableSinceMs = millis();
  say("READY");
  Serial.println("BrewPilot scale ready (t=tare)");
}

void loop() {
  weight.poll();
  BtnEvent e;
  while ((e = buttons.poll()) != BtnEvent::NONE) handleButton(e);

  if (Serial.available()) {
    char c = Serial.read();
    while (Serial.available()) Serial.read();
    if (c == 't' || c == 'T') doTare();
  }

  uint32_t now = millis();
  if (now - lastTickMs < OUTPUT_INTERVAL_MS) return;
  lastTickMs = now;

  float g = weight.grams();
  float flow = weight.flowMlS();

  if (fabsf(g - lastStableG) > SETTLED_BAND_G) {
    lastStableG = g;
    stableSinceMs = now;
    settled = false;
  } else if (now - stableSinceMs > SETTLED_TIME_MS) {
    settled = true;
  }

  if (mode == MODE_AUTO && !timerRunning && timerMs() == 0 &&
      (g - autoBaseG) > AUTO_POUR_DELTA_G) {
    timerRunning = true;
    timerStartMs = now;
    say("TIMER AUTO");
  }

  if (ble.takeTare()) doTare();
  float calG;
  if (ble.takeCalib(calG)) {
    weight.calibrate(calG);
    store.s.offsetRaw = weight.offsetRaw();
    store.s.scaleFactor = weight.scaleFactor();
    store.save();
    say("CAL SAVED");
  }

  const char* m = (now < msgUntilMs) ? msg : "";
  if (mode == MODE_SET && calStep > 0) {
    ui.renderCalib(calStep, CAL_PRESETS[calPresetIdx]);
  } else if (mode == MODE_SET) {
    char vb[16];
    setValueText(vb, sizeof(vb));
    ui.renderSet(SET_NAMES[setItem], vb);
  } else {
    ui.render(g, store.s.units == 1, timerMs(), timerRunning, flow, MODE_NAMES[mode],
              ble.connected(), m);
  }

  uint8_t rate = ble.rateHz() ? ble.rateHz() : 10;
  if (ble.streaming() && now - lastBleMs >= 1000U / rate) {
    lastBleMs = now;
    ble.notifyWeight(seq++, (int32_t)(g * 100), settled, g > OVERLOAD_G, 100);
  }

  Serial.printf("weight_g=%.2f flow=%.2f t=%lu mode=%u\n", g, flow, (unsigned long)timerMs(),
                mode);

  if (store.s.autoOffMin > 0 && !timerRunning && !ble.connected() &&
      now - lastInteractionMs > (uint32_t)store.s.autoOffMin * 60000UL) {
    goSleep();
  }
}
