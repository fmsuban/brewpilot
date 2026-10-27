#pragma once
#include <Arduino.h>

enum class BtnEvent : uint8_t { NONE, TARE_SHORT, TARE_LONG, TIMER_SHORT, TIMER_LONG, COMBO_LONG };

class Buttons {
 public:
  void begin(uint8_t pinTare, uint8_t pinTimer);
  BtnEvent poll();  // call every loop; at most one event per call

 private:
  uint8_t _tare = 0, _timer = 0;
  bool _tRaw = false, _mRaw = false;  // raw pressed state (active low)
  bool _t = false, _m = false;        // debounced pressed state
  uint32_t _tChange = 0, _mChange = 0;
  uint32_t _tStart = 0, _mStart = 0;
  bool _tLong = false, _mLong = false, _combo = false;
};
