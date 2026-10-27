#include "store.h"

void Store::begin() {
  _prefs.begin("brewpilot", false);
  s.offsetRaw = _prefs.getFloat("offset", 0);
  s.scaleFactor = _prefs.getFloat("scale", 1);
  if (s.scaleFactor == 0) s.scaleFactor = 1;
  s.mode = _prefs.getUChar("mode", 0);
  if (s.mode > 1) s.mode = 0;
  s.units = _prefs.getUChar("units", 0);
  if (s.units > 1) s.units = 0;
  s.brightness = _prefs.getUChar("bright", 200);
  s.autoOffMin = _prefs.getUChar("autooff", 10);
  if (s.autoOffMin != 5 && s.autoOffMin != 10 && s.autoOffMin != 30) s.autoOffMin = 10;
  s.bleEnabled = _prefs.getBool("ble", true);
}

void Store::save() {
  _prefs.putFloat("offset", s.offsetRaw);
  _prefs.putFloat("scale", s.scaleFactor);
  _prefs.putUChar("mode", s.mode > 1 ? 0 : s.mode);
  _prefs.putUChar("units", s.units);
  _prefs.putUChar("bright", s.brightness);
  _prefs.putUChar("autooff", s.autoOffMin);
  _prefs.putBool("ble", s.bleEnabled);
}
