#pragma once
#include <Arduino.h>
#include <Preferences.h>

struct Settings {
  float offsetRaw = 0;
  float scaleFactor = 1;
};

class Store {
 public:
  Settings s;
  void begin();
  void save();

 private:
  Preferences _prefs;
};
