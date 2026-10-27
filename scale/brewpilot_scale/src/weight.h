#pragma once
#include <Arduino.h>
#include "HX711.h"

class WeightSensor {
 public:
  void begin(uint8_t dout, uint8_t sck);
  void setCalibration(float offsetRaw, float scaleFactor);
  float offsetRaw() const { return _offset; }
  float scaleFactor() const { return _scale; }
  bool poll();  // non-blocking; true when a new filtered sample is ready
  float grams() const { return _grams; }
  float flowMlS();  // g/s over FLOW_WINDOW_MS
  void tare();
  void calibrate(float knownG);

 private:
  HX711 _hx;
  long _win[5] = {0, 0, 0, 0, 0};
  uint8_t _wi = 0, _n = 0;
  float _ema = 0;
  bool _emaInit = false;
  float _offset = 0, _scale = 1;
  float _grams = 0;
  static constexpr uint8_t HIST_N = 12;
  uint32_t _ht[HIST_N] = {0};
  float _hg[HIST_N] = {0};
  uint8_t _hn = 0;
  static long median(long* v, uint8_t n);
};
