#include "buttons.h"
#include "config.h"

void Buttons::begin(uint8_t pinTare, uint8_t pinTimer) {
  _tare = pinTare;
  _timer = pinTimer;
  pinMode(_tare, INPUT_PULLUP);
  pinMode(_timer, INPUT_PULLUP);
}

BtnEvent Buttons::poll() {
  uint32_t now = millis();
  bool tRaw = digitalRead(_tare) == LOW;
  bool mRaw = digitalRead(_timer) == LOW;
  if (tRaw != _tRaw) {
    _tRaw = tRaw;
    _tChange = now;
  }
  if (mRaw != _mRaw) {
    _mRaw = mRaw;
    _mChange = now;
  }
  if (tRaw != _t && (now - _tChange) > DEBOUNCE_MS) {
    _t = tRaw;
    if (_t) {
      _tStart = now;
      _tLong = false;
    } else if (!_tLong && !_combo) {
      return BtnEvent::TARE_SHORT;
    }
  }
  if (mRaw != _m && (now - _mChange) > DEBOUNCE_MS) {
    _m = mRaw;
    if (_m) {
      _mStart = now;
      _mLong = false;
    } else if (!_mLong && !_combo) {
      return BtnEvent::TIMER_SHORT;
    }
  }
  if (!_t && !_m) _combo = false;
  uint32_t bothStart = _tStart > _mStart ? _tStart : _mStart;
  if (_t && _m && !_combo && (now - bothStart) > COMBO_MS) {
    _combo = true;
    _tLong = true;
    _mLong = true;
    return BtnEvent::COMBO_LONG;
  }
  if (_t && !_tLong && !_combo && (now - _tStart) > LONG_PRESS_MS) {
    _tLong = true;
    return BtnEvent::TARE_LONG;
  }
  if (_m && !_mLong && !_combo && (now - _mStart) > LONG_PRESS_MS) {
    _mLong = true;
    return BtnEvent::TIMER_LONG;
  }
  return BtnEvent::NONE;
}
