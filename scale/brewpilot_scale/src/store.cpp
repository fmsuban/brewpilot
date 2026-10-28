#include "store.h"

void Store::begin() {
  _prefs.begin("brewpilot", false);
  s.offsetRaw = _prefs.getFloat("offset", 0);
  s.scaleFactor = _prefs.getFloat("scale", 1);
  float a = fabsf(s.scaleFactor);  // negative polarity is valid
  if (!(a >= 0.1f) || !(a <= 100000.0f)) s.scaleFactor = 1;
}

void Store::save() {
  _prefs.putFloat("offset", s.offsetRaw);
  _prefs.putFloat("scale", s.scaleFactor);
}
