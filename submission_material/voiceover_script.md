# BrewPilot voiceover script (2:14)

Read each block while its section is on screen. Times match `BrewPilot_demo_no_voice.mp4`. It's fine to run a little short. Just don't run past the next timecode.

**0:00 – 0:13 · Title**
This is BrewPilot. Your phone becomes a barista looking over your shoulder. It weighs your pour-over ten times a second, watches it through the camera, and Meta's models coach you while you brew.

**0:13 – 0:32 · The rig (photo)**
Here's the real rig. A home-built scale: two acrylic plates around a load cell, an HX711 amplifier, and an ESP32 that streams weight over Bluetooth Low Energy at ten hertz. The dripper and mug sit right on top, and the iPhone watches from the side.

**0:32 – 0:45 · Step 1, Connect the scale**
In the app, the Scale tab connects to the ESP32, shows live grams and flow rate, and tares with one tap. If Bluetooth drops, it reconnects on its own.

**0:45 – 0:56 · Step 2, Prep & bloom**
When the brew starts, a deterministic state machine takes over. It walks you through rinsing the filter, adding twenty-two grams of coffee, and a fifty-gram bloom.

**0:56 – 1:24 · Step 3, Pulse pours**
Then three pulse pours: to 150, 250, and 350 grams. The big number is live weight, the coach keeps your flow in range, and the moment you hit target, it flashes STOP. Between pours, the app grabs one camera frame and sends it to Muse Wonder, Meta's vision model. Its coaching shows up in the feed and is spoken aloud: slow down, pour in centered spirals, wait for the drawdown.

**1:24 – 1:34 · Step 4, Drawdown**
During drawdown, the camera keeps watching the coffee bed until it's dry. Final weight: 352 grams, just two over target.

**1:34 – 2:08 · Under the hood (diagram)**
Under the hood: the ESP32 talks Bluetooth to a SwiftUI app. The app calls a small FastAPI proxy that holds the Meta key. Muse Spark generates the recipe and the brew report as strict JSON, Muse Wonder does the vision coaching, and SAM 3.1 segments the final coffee bed. The key design choice: the AI never sits in the timing loop. Vision calls take about seven seconds, so they happen between pours. And if any model call fails, the app falls back to local logic and still brews a good cup.

**2:08 – 2:14 · End card**
BrewPilot. A better cup, coached by Meta's models.
