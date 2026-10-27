#pragma once
#include <Arduino.h>
#include <Preferences.h>

struct Settings {
  float offsetRaw = 0;
  float scaleFactor = 1;
  uint8_t mode = 0;         // 0 MANUAL, 1 AUTO (SET never persisted)
  uint8_t units = 0;        // 0 g, 1 oz
  uint8_t brightness = 200;
  uint8_t autoOffMin = 10;  // 5/10/30
  bool bleEnabled = true;
};

class Store {
 public:
  Settings s;
  void begin();
  void save();

 private:
  Preferences _prefs;
};
