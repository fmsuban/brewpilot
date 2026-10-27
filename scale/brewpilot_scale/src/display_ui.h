#pragma once
#include <Arduino.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>

class DisplayUi {
 public:
  DisplayUi();
  void begin(uint8_t brightness);
  void setBrightness(uint8_t v);
  void render(float weightG, bool oz, uint32_t timerMs, bool timerRunning, float flow,
              const char* modeName, bool ble, const char* msg);
  void renderSet(const char* item, const char* value);
  void renderCalib(uint8_t step, float presetG);
  void blank();

 private:
  Adafruit_ST7735 _tft;
};
