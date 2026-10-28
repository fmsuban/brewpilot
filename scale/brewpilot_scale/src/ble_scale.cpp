#include "ble_scale.h"
#include "config.h"

class BleScale::ServerCb : public BLEServerCallbacks {
 public:
  explicit ServerCb(BleScale* o) : _o(o) {}
  void onConnect(BLEServer* s) override {
    (void)s;
    _o->onConnect();
  }
  void onDisconnect(BLEServer* s) override {
    (void)s;
    _o->onDisconnect();
  }

 private:
  BleScale* _o;
};

class BleScale::WriteCb : public BLECharacteristicCallbacks {
 public:
  WriteCb(BleScale* o, uint8_t id) : _o(o), _id(id) {}
  void onWrite(BLECharacteristic* c) override {
    String v = c->getValue();
    const uint8_t* d = reinterpret_cast<const uint8_t*>(v.c_str());
    if (_id == 0)
      _o->onTareWrite();
    else if (_id == 1)
      _o->onCalibWrite(d, v.length());
    else
      _o->onControlWrite(d, v.length());
  }

 private:
  BleScale* _o;
  uint8_t _id;
};

void BleScale::begin() {
  if (_started) return;
  BLEDevice::init(BREW_DEVICE_NAME);
  _server = BLEDevice::createServer();
  _server->setCallbacks(new ServerCb(this));
  BLEService* svc = _server->createService(BREW_UUID_SVC);
  _weightChar = svc->createCharacteristic(
      BREW_UUID_WEIGHT, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  // Note: NimBLE auto-adds the 2902 descriptor for NOTIFY characteristics.
  BLECharacteristic* tare = svc->createCharacteristic(BREW_UUID_TARE, BLECharacteristic::PROPERTY_WRITE);
  tare->setCallbacks(new WriteCb(this, 0));
  BLECharacteristic* calib = svc->createCharacteristic(BREW_UUID_CALIB, BLECharacteristic::PROPERTY_WRITE);
  calib->setCallbacks(new WriteCb(this, 1));
  BLECharacteristic* ctrl =
      svc->createCharacteristic(BREW_UUID_CONTROL, BLECharacteristic::PROPERTY_WRITE);
  ctrl->setCallbacks(new WriteCb(this, 2));
  svc->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(BREW_UUID_SVC);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  _started = true;
}

void BleScale::onConnect() { _connected = true; }

void BleScale::onDisconnect() {
  _connected = false;
  if (_started) BLEDevice::startAdvertising();
}

void BleScale::onTareWrite() { _tareReq = true; }

void BleScale::onCalibWrite(const uint8_t* data, size_t len) {
  if (len < 4 || !data) return;
  float g;
  memcpy(&g, data, 4);  // little-endian float, matches ESP32
  _calibG = g;
  _calibReq = true;
}

void BleScale::onControlWrite(const uint8_t* data, size_t len) {
  if (len < 1 || !data) return;
  if (data[0] == 0x01)
    _streaming = true;
  else if (data[0] == 0x00)
    _streaming = false;
  else if (data[0] == 0x02 && len >= 2) {
    uint8_t r = data[1];
    if (r < 1) r = 1;
    if (r > 20) r = 20;
    _rateHz = r;
  }
}

void BleScale::notifyWeight(uint32_t seq, int32_t cg, bool settled, bool overload, uint8_t batt) {
  if (!_started || !_connected || !_streaming || !_weightChar) return;
  uint8_t p[10];
  p[0] = seq & 0xFF;
  p[1] = (seq >> 8) & 0xFF;
  p[2] = (seq >> 16) & 0xFF;
  p[3] = (seq >> 24) & 0xFF;
  uint32_t u = (uint32_t)cg;
  p[4] = u & 0xFF;
  p[5] = (u >> 8) & 0xFF;
  p[6] = (u >> 16) & 0xFF;
  p[7] = (u >> 24) & 0xFF;
  p[8] = (settled ? 0x01 : 0) | (overload ? 0x02 : 0);
  p[9] = batt;
  _weightChar->setValue(p, 10);
  _weightChar->notify();
}

bool BleScale::takeTare() {
  if (!_tareReq) return false;
  _tareReq = false;
  return true;
}

bool BleScale::takeCalib(float& knownG) {
  if (!_calibReq) return false;
  _calibReq = false;
  knownG = _calibG;
  return true;
}
