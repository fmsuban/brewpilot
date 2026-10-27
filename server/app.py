"""BrewPilot proxy: iOS app -> Meta Model API.

Holds META_API_KEY server-side; the iOS app never sees it.
Every endpoint returns strict JSON and falls back to deterministic
local data when the model is unreachable, so a brew never blocks on AI.
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
from enum import Enum
from typing import Callable, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field, ValidationError

from server.meta import (
    ModelError,
    complete_json,
    complete_json_with_image,
    load_settings,
    segment_image,
)

log = logging.getLogger("brewpilot")

app = FastAPI(title="BrewPilot proxy", version="0.1.0")


class Roast(str, Enum):
    light = "light"
    medium = "medium"
    dark = "dark"


class Strength(str, Enum):
    light = "light"  # tea-like
    medium = "medium"
    strong = "strong"


class RecipeRequest(BaseModel):
    roast: Roast = Roast.medium
    cups: int = Field(default=1, ge=1, le=2)
    strength: Strength = Strength.medium
    coffee_name: Optional[str] = None


class PourStep(BaseModel):
    id: str
    type: str = "pour"
    target_add_g: Optional[float] = None
    target_total_g: Optional[float] = None
    flow_ml_s: list[float] = Field(default_factory=lambda: [4, 6])
    duration_s: Optional[int] = None
    instruction: Optional[str] = None


class Recipe(BaseModel):
    name: str
    coffee_g: float
    water_g: float
    temp_c: int
    grind: str
    steps: list[PourStep]


class VisionContext(BaseModel):
    step: str
    elapsed_s: float = 0
    target_g: float = 0


class VisionResult(BaseModel):
    bloom_active: bool = False
    bubbles: str = "none"
    pour_position: str = "unknown"
    bed_even: bool = True
    channeling: bool = False
    coaching: str = ""
    severity: str = "info"


class ReportRequest(BaseModel):
    recipe_name: str = "Canned recipe"
    timeline: list[dict] = Field(default_factory=list)
    observations: list[str] = Field(default_factory=list)


CANNED_RECIPE = Recipe(
    name="House Pour-Over (offline)",
    coffee_g=22,
    water_g=350,
    temp_c=94,
    grind="medium-fine (table salt)",
    steps=[
        PourStep(
            id="bloom",
            target_add_g=50,
            flow_ml_s=[4, 6],
            duration_s=45,
            instruction="Saturate all grounds gently. Swirl once.",
        ),
        PourStep(
            id="p1",
            target_total_g=150,
            flow_ml_s=[5, 7],
            duration_s=30,
            instruction="Pour in slow spirals from the center out.",
        ),
        PourStep(id="p2", target_total_g=250, flow_ml_s=[5, 7]),
        PourStep(id="p3", target_total_g=350, flow_ml_s=[4, 6]),
    ],
)

CANNED_COACHING = {
    "bloom": "Bloom looks good. Keep the kettle ready for the first pulse.",
    "pulse": "Steady spiral, center out. Watch the flow bar.",
    "drawdown": "Let it drain. Don't top up the bed.",
    "final": "Brew complete. Check the bed: flat and even is the goal.",
}


# --- Recipe generation (SPEC 9.1) ---

RECIPE_SYSTEM_PROMPT = """You generate pour-over coffee recipes as strict JSON \
(temperature 0, no prose, no markdown).
Domain defaults (Melitta, 1 cup): 22 g coffee : 350 g water (1:16), 94 C \
(light roast 96 C), medium-fine grind, bloom ~2-2.5x coffee weight for 40-50 s, \
3-4 pulses at 4-7 ml/s.
Output schema:
{"name": str, "coffee_g": number, "water_g": number, "temp_c": int, \
"grind": str, "steps": [{"id": str, "type": "pour", \
"target_add_g"?: number, "target_total_g"?: number, \
"flow_ml_s": [min, max], "duration_s"?: int, "instruction"?: str}]}
Rules: 3-5 steps; first step id "bloom" with target_add_g; later steps use \
target_total_g; last target_total_g MUST equal water_g; \
ratio water/coffee 1:15-1:17."""

MAX_RECIPE_ATTEMPTS = 2


class RecipeInvalid(ModelError):
    """Model returned JSON that violates the recipe contract."""


def build_recipe_user_prompt(req: RecipeRequest) -> str:
    base = f"roast={req.roast.value} cups={req.cups} strength={req.strength.value}"
    if req.coffee_name:
        base += f" coffee={req.coffee_name}"
    return base + " -> strict JSON recipe only."


def validate_recipe(data: dict) -> Recipe:
    try:
        recipe = Recipe.model_validate(data)
    except ValidationError as e:
        raise RecipeInvalid(f"schema: {e.errors()[0]['loc']}") from e
    if not 3 <= len(recipe.steps) <= 5:
        raise RecipeInvalid(f"steps: want 3-5, got {len(recipe.steps)}")
    ratio = recipe.water_g / recipe.coffee_g if recipe.coffee_g else 0
    if not 15 <= ratio <= 17:
        raise RecipeInvalid(f"ratio 1:{ratio:.1f} outside 1:15-1:17")
    last = recipe.steps[-1].target_total_g
    if last is None or abs(last - recipe.water_g) > 1e-6:
        raise RecipeInvalid(f"last target_total_g ({last}) != water_g ({recipe.water_g})")
    return recipe


def generate_recipe(
    req: RecipeRequest,
    complete: Optional[Callable[[str, str], dict]] = None,
) -> Recipe:
    """Model recipe with regenerate-on-violation. Raises ModelError if unusable."""
    if complete is None:
        settings = load_settings()
        model = settings.spark_model

        def complete(system: str, user: str) -> dict:  # type: ignore[misc]
            return complete_json(settings, model, system, user)

    last_error = "no attempts"
    for attempt in range(1, MAX_RECIPE_ATTEMPTS + 1):
        try:
            data = complete(RECIPE_SYSTEM_PROMPT, build_recipe_user_prompt(req))
            return validate_recipe(data)
        except RecipeInvalid as e:
            last_error = str(e)
            log.warning("recipe attempt %d invalid: %s", attempt, e)
        except ModelError as e:
            raise ModelError(f"model call failed: {e}") from e
    raise RecipeInvalid(f"exhausted attempts: {last_error}")


# --- Vision checks (SPEC 9.2) ---

VISION_SYSTEM_PROMPT = """You watch a home pour-over coffee brew through a phone camera. \
Output strict JSON (temperature 0, no prose, no markdown):
{"bloom_active": bool, "bubbles": "none"|"weak"|"vigorous", \
"pour_position": "center"|"edge"|"off"|"unknown", "bed_even": bool, \
"channeling": bool, "coaching": str, "severity": "info"|"warning"}
Coaching is one short sentence, imperative, addressed to the brewer.
Defects you can actually see: dry grounds high on the filter wall, \
channels/tunnels in the spent bed, off-center pouring, way-too-fast pour, \
no bloom bubbles (stale coffee), bed mounded instead of flat. If the frame \
is unclear, say so in coaching with severity info and best-effort fields."""

MAX_FRAME_BYTES = 5 * 1024 * 1024


def build_vision_user_text(ctx: VisionContext) -> str:
    return (
        f"step={ctx.step} elapsed_s={ctx.elapsed_s:.0f} "
        f"target_g={ctx.target_g:.0f} -> strict JSON observation only."
    )


def canned_vision(ctx: VisionContext) -> VisionResult:
    key = ctx.step.split("_")[0]
    coaching = CANNED_COACHING.get(key, CANNED_COACHING["pulse"])
    return VisionResult(coaching=coaching)


def analyze_vision(
    ctx: VisionContext,
    image_bytes: bytes,
    complete: Optional[Callable[[str, str], dict]] = None,
) -> VisionResult:
    """Single-attempt model vision check. Raises ModelError if unusable."""
    if complete is None:
        settings = load_settings()
        model = settings.wonder_model
        b64 = base64.b64encode(image_bytes).decode()

        def complete(system: str, user: str) -> dict:  # type: ignore[misc]
            return complete_json_with_image(settings, model, system, user, b64)

    data = complete(VISION_SYSTEM_PROMPT, build_vision_user_text(ctx))
    try:
        return VisionResult.model_validate(data)
    except ValidationError as e:
        raise ModelError(f"vision schema: {e.errors()[0]['loc']}") from e


# --- Brew report (SPEC 9.4) ---

REPORT_SYSTEM_PROMPT = """You are a pour-over coffee coach writing an end-of-brew \
report card. Output strict JSON (temperature 0, no prose, no markdown):
{"bullets": [exactly 3 short strings], "tip": str}
Brew data follows as JSON: recipe name, downsampled weight timeline \
(seconds, grams), and vision observations from the brew. Bullet 1: what went \
well. Bullet 2: biggest objective deviation (timing/ratio/flow) with numbers. \
Bullet 3: bed/technique note from the observations. Tip: one concrete fix \
for the next brew."""

MAX_TIMELINE_POINTS = 20


class ReportResult(BaseModel):
    bullets: list[str]
    tip: str


def downsample_timeline(timeline: list[dict]) -> list[dict]:
    if len(timeline) <= MAX_TIMELINE_POINTS:
        return timeline
    step = len(timeline) / MAX_TIMELINE_POINTS
    return [timeline[int(i * step)] for i in range(MAX_TIMELINE_POINTS)]


def build_report_user_text(req: ReportRequest) -> str:
    payload = {
        "recipe": req.recipe_name,
        "timeline": downsample_timeline(req.timeline),
        "observations": req.observations,
    }
    return json.dumps(payload) + " -> strict JSON report only."


def canned_report(req: ReportRequest) -> ReportResult:
    return ReportResult(
        bullets=[
            f"Brewed {req.recipe_name} with {len(req.timeline)} logged samples.",
            "Offline report: connect the proxy for AI critique.",
        ],
        tip="Keep the pour spiral slow and the bed wet between pulses.",
    )


def generate_report(
    req: ReportRequest,
    complete: Optional[Callable[[str, str], dict]] = None,
) -> ReportResult:
    """Single-attempt model report. Raises ModelError if unusable."""
    if complete is None:
        settings = load_settings()
        model = settings.spark_model

        def complete(system: str, user: str) -> dict:  # type: ignore[misc]
            return complete_json(settings, model, system, user)

    data = complete(REPORT_SYSTEM_PROMPT, build_report_user_text(req))
    try:
        report = ReportResult.model_validate(data)
    except ValidationError as e:
        raise ModelError(f"report schema: {e.errors()[0]['loc']}") from e
    if not report.bullets or not report.tip.strip():
        raise ModelError("report empty")
    return report


# --- Bed segmentation (SPEC 9.3) ---

SEGMENT_PROMPT = "coffee bed"


class SegmentBox(BaseModel):
    x1: int
    y1: int
    x2: int
    y2: int


class SegmentMask(BaseModel):
    # bounds in original image px + row-major RLE bitmap (h rows × w cols)
    x: int
    y: int
    w: int
    h: int
    counts: str


class SegmentResult(BaseModel):
    prompt: str
    boxes: list[SegmentBox] = Field(default_factory=list)
    masks: list[SegmentMask]


def run_segmentation(
    image_bytes: bytes,
    prompt: str = SEGMENT_PROMPT,
    segment: Optional[Callable[[str, str], dict]] = None,
) -> SegmentResult:
    """Single-attempt SAM segmentation. Raises ModelError if unusable."""
    if segment is None:
        settings = load_settings()
        model = settings.sam_model
        b64 = base64.b64encode(image_bytes).decode()

        def segment(prompt: str, image_b64: str) -> dict:  # type: ignore[misc]
            return segment_image(settings, model, prompt, image_b64)

    data = segment(prompt, b64)
    try:
        result = SegmentResult.model_validate(data)
    except ValidationError as e:
        raise ModelError(f"segment schema: {e.errors()[0]['loc']}") from e
    if not result.masks:
        raise ModelError("segment empty")
    return result


# --- Routes ---


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "meta_configured": load_settings().configured}


@app.post("/recipe")
def create_recipe(req: RecipeRequest) -> dict:
    if load_settings().configured:
        try:
            return {"source": "model", "recipe": generate_recipe(req).model_dump()}
        except ModelError as e:
            log.warning("model recipe failed, using fallback: %s", e)
    return {"source": "fallback", "recipe": CANNED_RECIPE.model_dump()}


@app.post("/vision")
async def check_vision(
    context: str = Form(...),  # JSON-encoded VisionContext
    frame: UploadFile = File(...),
) -> dict:
    try:
        ctx = VisionContext.model_validate_json(context)
    except ValidationError as e:
        raise HTTPException(422, f"bad context: {e.errors()[0]['loc']}") from e
    image = await frame.read()
    if len(image) > MAX_FRAME_BYTES:
        raise HTTPException(413, "frame too large")
    if load_settings().configured and image:
        try:
            return {"source": "model", "vision": analyze_vision(ctx, image).model_dump()}
        except ModelError as e:
            log.warning("model vision failed, using fallback: %s", e)
    return {"source": "fallback", "vision": canned_vision(ctx).model_dump()}


@app.post("/segment")
async def segment_bed(
    frame: UploadFile = File(...),
    prompt: str = Form(SEGMENT_PROMPT),
) -> dict:
    prompt = (prompt or "").strip() or SEGMENT_PROMPT
    if len(prompt) > 200:
        raise HTTPException(422, "prompt too long")
    image = await frame.read()
    if len(image) > MAX_FRAME_BYTES:
        raise HTTPException(413, "frame too large")
    if load_settings().configured and image:
        try:
            # to_thread: run_segmentation drives the async SAM parser via
            # asyncio.run, which cannot run on this route's event loop.
            result = await asyncio.to_thread(run_segmentation, image, prompt)
            return {"source": "model", "segment": result.model_dump()}
        except ModelError as e:
            log.warning("model segment failed, using fallback: %s", e)
    return {"source": "fallback", "segment": None}


@app.post("/report")
def build_report(req: ReportRequest) -> dict:
    if load_settings().configured:
        try:
            return {"source": "model", "report": generate_report(req).model_dump()}
        except ModelError as e:
            log.warning("model report failed, using fallback: %s", e)
    return {"source": "fallback", "report": canned_report(req).model_dump()}
