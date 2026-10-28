#pragma once
#include <Arduino.h>

// ---- HX711 ----
constexpr uint8_t PIN_HX_DOUT = 16;
constexpr uint8_t PIN_HX_SCK = 4;

// ---- Timing ----
constexpr uint32_t OUTPUT_INTERVAL_MS = 100;  // 10 Hz BLE + serial

// ---- Filter ----
constexpr float EMA_ALPHA = 0.35f;
constexpr uint32_t FLOW_WINDOW_MS = 500;

// ---- Settled / overload ----
constexpr float SETTLED_BAND_G = 0.5f;
constexpr uint32_t SETTLED_TIME_MS = 1000;
constexpr float OVERLOAD_G = 1000.0f;

// ---- BLE (SPEC 7) ----
#define BREW_UUID_SVC "0000C0FF-EE00-4000-8000-00DECAFE0010"
#define BREW_UUID_WEIGHT "0000C0FF-EE00-4000-8000-00DECAFE0011"
#define BREW_UUID_TARE "0000C0FF-EE00-4000-8000-00DECAFE0012"
#define BREW_UUID_CALIB "0000C0FF-EE00-4000-8000-00DECAFE0013"
#define BREW_UUID_CONTROL "0000C0FF-EE00-4000-8000-00DECAFE0014"
#define BREW_DEVICE_NAME "BrewPilot-Scale"
