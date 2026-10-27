#include "weight.h"
#include "config.h"

void WeightSensor::begin(uint8_t dout, uint8_t sck) { _hx.begin(dout, sck); }

void WeightSensor::setCalibration(float offsetRaw, float scaleFactor) {
  _offset = offsetRaw;
  if (scaleFactor != 0) _scale = scaleFactor;
}

long WeightSensor::median(long* v, uint8_t n) {
  for (uint8_t i = 1; i < n; i++) {
    long key = v[i];
    int8_t j = i - 1;
    while (j >= 0 && v[j] > key) {
      v[j + 1] = v[j];
      j--;
    }
    v[j + 1] = key;
  }
  return v[n / 2];
}

bool WeightSensor::poll() {
  if (!_hx.is_ready()) return false;
  long raw = _hx.read();
  _win[_wi] = raw;
  _wi = (_wi + 1) % 5;
  if (_n < 5) _n++;
  long tmp[5];
  for (uint8_t i = 0; i < _n; i++) tmp[i] = _win[i];
  float med = (float)median(tmp, _n);
  if (!_emaInit) {
    _ema = med;
    _emaInit = true;
  } else {
    _ema += EMA_ALPHA * (med - _ema);
  }
  _grams = (_ema - _offset) / _scale;
  if (_hn < HIST_N) {
    _ht[_hn] = millis();
    _hg[_hn] = _grams;
    _hn++;
  } else {
    for (uint8_t i = 0; i < HIST_N - 1; i++) {
      _ht[i] = _ht[i + 1];
      _hg[i] = _hg[i + 1];
    }
    _ht[HIST_N - 1] = millis();
    _hg[HIST_N - 1] = _grams;
  }
  return true;
}

float WeightSensor::flowMlS() {
  if (_hn < 2) return 0;
  uint32_t now = millis();
  uint8_t first = 0;
  while (first + 1 < _hn && now - _ht[first] > FLOW_WINDOW_MS) first++;
  float dt = (_ht[_hn - 1] - _ht[first]) / 1000.0f;
  if (dt <= 0) return 0;
  return (_hg[_hn - 1] - _hg[first]) / dt;
}

void WeightSensor::tare() { _offset = _ema; }

void WeightSensor::calibrate(float knownG) {
  if (knownG > 0) _scale = (_ema - _offset) / knownG;
}
