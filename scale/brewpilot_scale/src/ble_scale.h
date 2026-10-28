#pragma once
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

class BleScale {
 public:
  void begin();  // call once from setup; always advertises
  bool connected() const { return _connected; }
  bool streaming() const { return _streaming; }
  uint8_t rateHz() const { return _rateHz; }
  void notifyWeight(uint32_t seq, int32_t cg, bool settled, bool overload, uint8_t batt);
  bool takeTare();
  bool takeCalib(float& knownG);

 private:
  class ServerCb;
  class WriteCb;
  friend class ServerCb;
  friend class WriteCb;
  void onConnect();
  void onDisconnect();
  void onTareWrite();
  void onCalibWrite(const uint8_t* data, size_t len);
  void onControlWrite(const uint8_t* data, size_t len);

  bool _started = false;
  bool _connected = false;
  bool _streaming = true;
  uint8_t _rateHz = 10;
  bool _tareReq = false;
  bool _calibReq = false;
  float _calibG = 0;
  BLEServer* _server = nullptr;
  BLECharacteristic* _weightChar = nullptr;
};
