# BrewPilot

BrewPilot is a hackathon-ready scaffold for a pour-over coaching rig that combines a BLE scale, iPhone camera, and Meta-model-backed vision/coaching pipeline.

## Structure

- `server/` — FastAPI proxy for recipe generation, vision checks, segmentation, and report generation with deterministic local fallbacks.
- `scale/` — ESP32/PlatformIO firmware for the HX711 BLE scale.
- `ios/` — SwiftUI app skeleton with a deterministic brew state machine and local guard rails.

## Quick start

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r server/requirements.txt -r server/requirements-dev.txt
uvicorn server.app:app --reload
```

Then hit:

- `GET /health`
- `POST /recipe`
- `POST /vision`
- `POST /segment`
- `POST /report`

## MVP principle

The AI is intentionally kept out of the timing-critical loop. The determinisitic state machine, flow-rate math, and safety checks live on-device; the model layer simply provides recipe suggestions, camera perception, and report text.

## Repo layout (monorepo)

```
hackathon/
├── SPEC.md            ← full spec, source of truth
├── server/            ← FastAPI proxy (uvicorn server.app:app)
│   ├── requirements.txt + requirements-dev.txt
│   ├── .env (local, gitignored) ← META_API_KEY vive aquí
│   └── tests/         ← pytest suite
├── ios/BrewPilot/     ← SwiftUI sources (create .xcodeproj after Xcode installs, see ios/README.md)
├── scale/             ← ESP32 + HX711 BLE scale firmware (PlatformIO)
└── docs/              ← demo script, submission checklist, decision log
```

## Run the proxy locally

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r server/requirements.txt -r server/requirements-dev.txt
cp server/.env.example server/.env  # fill in your Meta key, never commit
set -a; source server/.env; set +a
uvicorn server.app:app --reload
```

Deploy to Modal (needs `modal setup` login + `brewpilot-meta` secret,
see `server/modal_app.py`):

```bash
modal deploy server/modal_app.py
```
