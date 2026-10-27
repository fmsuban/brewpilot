#include "display_ui.h"
#include "config.h"

DisplayUi::DisplayUi() : _tft(PIN_TFT_CS, PIN_TFT_DC, PIN_TFT_RST) {}

void DisplayUi::begin(uint8_t brightness) {
  pinMode(PIN_TFT_BL, OUTPUT);
  setBrightness(brightness);
  _tft.initR(INITR_BLACKTAB);
  _tft.setRotation(0);  // 128x160 portrait; use 2 if upside-down
  _tft.fillScreen(ST77XX_BLACK);
}

void DisplayUi::setBrightness(uint8_t v) { analogWrite(PIN_TFT_BL, v); }

void DisplayUi::render(float weightG, bool oz, uint32_t timerMs, bool timerRunning, float flow,
                       const char* modeName, bool ble, const char* msg) {
  float v = oz ? weightG * G_TO_OZ : weightG;
  // Weight zone
  _tft.fillRect(0, 0, 128, 54, ST77XX_BLACK);
  _tft.setCursor(4, 8);
  _tft.setTextColor(ST77XX_WHITE);
  _tft.setTextSize((v < -99.9f || v > 999.9f) ? 3 : 4);
  _tft.print(v, 1);
  _tft.setTextSize(2);
  _tft.print(oz ? " oz" : " g");
  // Timer zone
  _tft.fillRect(0, 56, 128, 28, ST77XX_BLACK);
  _tft.setCursor(4, 60);
  _tft.setTextSize(3);
  _tft.setTextColor(timerRunning ? ST77XX_GREEN : ST77XX_WHITE);
  uint32_t s = timerMs / 1000;
  char tbuf[8];
  snprintf(tbuf, sizeof(tbuf), "%lu:%02lu", (unsigned long)(s / 60), (unsigned long)(s % 60));
  _tft.print(tbuf);
  // Flow zone
  _tft.fillRect(0, 86, 128, 24, ST77XX_BLACK);
  _tft.setCursor(4, 90);
  _tft.setTextSize(2);
  _tft.setTextColor(ST77XX_CYAN);
  _tft.print(flow, 1);
  float f = flow < 0 ? 0 : flow;
  if (f > 12) f = 12;
  _tft.drawRect(64, 90, 60, 10, ST77XX_CYAN);
  _tft.fillRect(66, 92, (int)(56 * f / 12), 6, ST77XX_CYAN);
  // Status row
  _tft.fillRect(0, 112, 128, 14, ST77XX_BLACK);
  _tft.setCursor(4, 114);
  _tft.setTextSize(1);
  _tft.setTextColor(ST77XX_YELLOW);
  _tft.print(modeName);
  _tft.setCursor(64, 114);
  _tft.setTextColor(ble ? ST77XX_GREEN : ST77XX_BLUE);
  _tft.print(ble ? "BLE" : "---");
  _tft.setCursor(100, 114);
  _tft.setTextColor(ST77XX_WHITE);
  _tft.print("USB");
  // Message line
  _tft.fillRect(0, 128, 128, 32, ST77XX_BLACK);
  if (msg && msg[0]) {
    _tft.setCursor(4, 134);
    _tft.setTextSize(2);
    _tft.setTextColor(ST77XX_ORANGE);
    _tft.print(msg);
  }
}

void DisplayUi::renderSet(const char* item, const char* value) {
  _tft.fillScreen(ST77XX_BLACK);
  _tft.setCursor(4, 8);
  _tft.setTextSize(1);
  _tft.setTextColor(ST77XX_YELLOW);
  _tft.print("SET");
  _tft.setCursor(4, 30);
  _tft.setTextSize(2);
  _tft.setTextColor(ST77XX_WHITE);
  _tft.print(item);
  _tft.setCursor(4, 70);
  _tft.setTextSize(3);
  _tft.setTextColor(ST77XX_CYAN);
  _tft.print(value);
  _tft.setCursor(4, 130);
  _tft.setTextSize(1);
  _tft.setTextColor(ST77XX_BLUE);
  _tft.print("TIMER:chg/lng:nxt");
  _tft.setCursor(4, 142);
  _tft.print("TARE:save");
}

void DisplayUi::renderCalib(uint8_t step, float presetG) {
  _tft.fillScreen(ST77XX_BLACK);
  _tft.setCursor(4, 8);
  _tft.setTextSize(1);
  _tft.setTextColor(ST77XX_YELLOW);
  _tft.print("CALIBRATE");
  _tft.setCursor(4, 30);
  _tft.setTextSize(2);
  _tft.setTextColor(ST77XX_WHITE);
  if (step == 1) {
    _tft.print("Empty scale");
    _tft.setCursor(4, 70);
    _tft.print("TARE=ok");
  } else {
    _tft.print("Put mass:");
    _tft.setCursor(4, 60);
    _tft.setTextSize(3);
    _tft.setTextColor(ST77XX_CYAN);
    _tft.print(presetG, 0);
    _tft.print(" g");
    _tft.setCursor(4, 110);
    _tft.setTextSize(1);
    _tft.setTextColor(ST77XX_WHITE);
    _tft.print("TIMER=cycle");
    _tft.setCursor(4, 122);
    _tft.print("TARE=save");
  }
}

void DisplayUi::blank() { _tft.fillScreen(ST77XX_BLACK); }
