import pytest
from fastapi.testclient import TestClient

import server.app as appmod
from server.app import (
    CANNED_RECIPE,
    MAX_FRAME_BYTES,
    MAX_TIMELINE_POINTS,
    RECIPE_SYSTEM_PROMPT,
    REPORT_SYSTEM_PROMPT,
    SEGMENT_PROMPT,
    VISION_SYSTEM_PROMPT,
    RecipeInvalid,
    RecipeRequest,
    ReportRequest,
    VisionContext,
    analyze_vision,
    app,
    build_recipe_user_prompt,
    build_report_user_text,
    build_vision_user_text,
    downsample_timeline,
    generate_recipe,
    generate_report,
    validate_recipe,
)
from server.meta import MetaSettings, ModelError

client = TestClient(app)

CONFIGURED = MetaSettings("https://example.invalid", "key", "s", "w", "sam", 25)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_recipe_fallback_is_schema_valid():
    r = client.post("/recipe", json={"roast": "medium", "cups": 1, "strength": "medium"})
    assert r.status_code == 200
    body = r.json()
    assert body["source"] == "fallback"
    recipe = body["recipe"]
    assert recipe["water_g"] == recipe["steps"][-1]["target_total_g"]
    assert 15 <= recipe["water_g"] / recipe["coffee_g"] <= 17


def test_vision_fallback():
    r = client.post(
        "/vision",
        data={"context": '{"step": "bloom", "elapsed_s": 12, "target_g": 50}'},
        files={"frame": ("frame.jpg", b"\xff\xd8fakejpeg", "image/jpeg")},
    )
    assert r.status_code == 200
    assert r.json()["vision"]["coaching"]


def test_segment_fallback():
    r = client.post(
        "/segment",
        files={"frame": ("frame.jpg", b"\xff\xd8fakejpeg", "image/jpeg")},
    )
    assert r.status_code == 200
    assert r.json()["source"] == "fallback"


def test_report_fallback():
    r = client.post("/report", json={"recipe_name": "Test", "timeline": [], "observations": []})
    assert r.status_code == 200
    assert r.json()["report"]["tip"]


def test_recipe_prompt_mentions_schema_and_ratio():
    assert "target_total_g" in RECIPE_SYSTEM_PROMPT
    assert "1:15-1:17" in RECIPE_SYSTEM_PROMPT
    user = build_recipe_user_prompt(
        RecipeRequest(roast="light", cups=2, strength="strong", coffee_name="Ethiopia")
    )
    assert "light" in user and "2" in user and "Ethiopia" in user


def test_validate_accepts_canned():
    assert validate_recipe(CANNED_RECIPE.model_dump()).water_g == 350


def _mutated(**overrides):
    data = CANNED_RECIPE.model_dump()
    data.update(overrides)
    return data


def test_validate_rejects_bad_ratio():
    with pytest.raises(RecipeInvalid):
        validate_recipe(_mutated(water_g=500))  # 1:22.7


def test_validate_rejects_mismatched_total():
    data = CANNED_RECIPE.model_dump()
    data["steps"][-1]["target_total_g"] = 300
    with pytest.raises(RecipeInvalid):
        validate_recipe(data)


def test_validate_rejects_wrong_step_count():
    data = CANNED_RECIPE.model_dump()
    data["steps"] = data["steps"][:2]
    with pytest.raises(RecipeInvalid):
        validate_recipe(data)


def test_generate_regenerates_on_violation():
    calls = []

    def fake(system, user):
        calls.append(user)
        if len(calls) == 1:
            return _mutated(water_g=500)  # invalid ratio
        return CANNED_RECIPE.model_dump()

    recipe = generate_recipe(RecipeRequest(), complete=fake)
    assert recipe.water_g == 350
    assert len(calls) == 2


def test_generate_raises_after_exhausted_attempts():
    with pytest.raises(ModelError):
        generate_recipe(RecipeRequest(), complete=lambda s, u: _mutated(water_g=500))


def test_endpoint_uses_model_when_client_works(monkeypatch):
    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(
        appmod, "complete_json", lambda settings, model, s, u: CANNED_RECIPE.model_dump()
    )
    r = client.post("/recipe", json={"roast": "medium", "cups": 1, "strength": "medium"})
    assert r.json()["source"] == "model"


def test_endpoint_falls_back_on_model_error(monkeypatch):
    def boom(settings, model, s, u):
        raise ModelError("down")

    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(appmod, "complete_json", boom)
    r = client.post("/recipe", json={"roast": "medium", "cups": 1, "strength": "medium"})
    body = r.json()
    assert body["source"] == "fallback"
    assert body["recipe"]["water_g"] == 350


def test_vision_prompt_mentions_schema():
    assert "bloom_active" in VISION_SYSTEM_PROMPT
    assert "coaching" in VISION_SYSTEM_PROMPT
    assert "bed_drained" in VISION_SYSTEM_PROMPT
    text = build_vision_user_text(VisionContext(step="bloom", elapsed_s=12, target_g=50))
    assert "bloom" in text and "12" in text


def test_analyze_vision_validates_schema():
    good = {
        "bloom_active": True, "bubbles": "vigorous", "pour_position": "center",
        "bed_even": True, "channeling": False, "coaching": "Keep going.",
        "severity": "info",
    }
    out = analyze_vision(VisionContext(step="bloom"), b"img", complete=lambda s, u: good)
    assert out.coaching == "Keep going."
    assert out.bed_drained is False  # older replies without the field still validate
    drained = analyze_vision(
        VisionContext(step="drawdown"), b"img", complete=lambda s, u: {**good, "bed_drained": True}
    )
    assert drained.bed_drained is True
    with pytest.raises(ModelError):
        analyze_vision(VisionContext(step="bloom"), b"img", complete=lambda s, u: ["not", "a", "dict"])


def test_vision_endpoint_model_path(monkeypatch):
    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(
        appmod,
        "complete_json_with_image",
        lambda settings, model, s, u, b64, mime="image/jpeg", client=None: {
            "bloom_active": False, "bubbles": "none", "pour_position": "unknown",
            "bed_even": True, "channeling": False, "coaching": "Model says hi.",
            "severity": "info",
        },
    )
    r = client.post(
        "/vision",
        data={"context": '{"step": "bloom"}'},
        files={"frame": ("f.jpg", b"\xff\xd8x", "image/jpeg")},
    )
    body = r.json()
    assert body["source"] == "model"
    assert body["vision"]["coaching"] == "Model says hi."


def test_vision_endpoint_falls_back(monkeypatch):
    def boom(*a, **k):
        raise ModelError("down")

    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(appmod, "complete_json_with_image", boom)
    r = client.post(
        "/vision",
        data={"context": '{"step": "bloom"}'},
        files={"frame": ("f.jpg", b"\xff\xd8x", "image/jpeg")},
    )
    assert r.json()["source"] == "fallback"


def test_vision_rejects_bad_context():
    r = client.post(
        "/vision",
        data={"context": "not json"},
        files={"frame": ("f.jpg", b"x", "image/jpeg")},
    )
    assert r.status_code == 422


def test_vision_rejects_huge_frame():
    big = b"x" * (MAX_FRAME_BYTES + 1)
    r = client.post(
        "/vision",
        data={"context": '{"step": "bloom"}'},
        files={"frame": ("f.jpg", big, "image/jpeg")},
    )
    assert r.status_code == 413


def test_report_prompt_mentions_schema():
    assert "bullets" in REPORT_SYSTEM_PROMPT and "tip" in REPORT_SYSTEM_PROMPT
    text = build_report_user_text(ReportRequest(recipe_name="R", timeline=[], observations=["o"]))
    assert "R" in text and "o" in text


def test_downsample_timeline():
    long = [{"t": i} for i in range(100)]
    assert len(downsample_timeline(long)) == MAX_TIMELINE_POINTS
    short = [{"t": i} for i in range(5)]
    assert downsample_timeline(short) == short
    assert downsample_timeline([]) == []


def test_generate_report_validates():
    req = ReportRequest(recipe_name="R", timeline=[], observations=[])
    good = {"bullets": ["a", "b", "c"], "tip": "t"}
    assert generate_report(req, complete=lambda s, u: good).tip == "t"
    with pytest.raises(ModelError):
        generate_report(req, complete=lambda s, u: {"bullets": [], "tip": " "})
    with pytest.raises(ModelError):
        generate_report(req, complete=lambda s, u: ["x"])


def test_report_endpoint_model_path(monkeypatch):
    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(
        appmod, "complete_json", lambda settings, model, s, u: {"bullets": ["a"], "tip": "t"}
    )
    r = client.post("/report", json={"recipe_name": "R", "timeline": [], "observations": []})
    assert r.json()["source"] == "model"


def test_report_endpoint_falls_back(monkeypatch):
    def boom(*a, **k):
        raise ModelError("down")

    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(appmod, "complete_json", boom)
    r = client.post("/report", json={"recipe_name": "R", "timeline": [], "observations": []})
    body = r.json()
    assert body["source"] == "fallback" and body["report"]["tip"]


def _fake_segment(captured):
    def fake(settings, model, prompt, b64, mime="image/jpeg", client=None):
        captured["prompt"] = prompt
        captured["model"] = model
        return {
            "prompt": prompt,
            "boxes": [],
            "masks": [{"x": 0, "y": 0, "w": 4, "h": 4, "counts": "abc"}],
        }

    return fake


def test_segment_endpoint_model_path(monkeypatch):
    captured = {}
    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(appmod, "segment_image", _fake_segment(captured))
    r = client.post(
        "/segment",
        data={"prompt": "avocado"},
        files={"frame": ("f.jpg", b"\xff\xd8x", "image/jpeg")},
    )
    body = r.json()
    assert body["source"] == "model"
    assert body["segment"]["masks"][0]["w"] == 4
    assert captured["prompt"] == "avocado"


def test_segment_endpoint_default_prompt(monkeypatch):
    captured = {}
    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(appmod, "segment_image", _fake_segment(captured))
    r = client.post("/segment", files={"frame": ("f.jpg", b"\xff\xd8x", "image/jpeg")})
    assert r.json()["source"] == "model"
    assert captured["prompt"] == SEGMENT_PROMPT


def test_segment_endpoint_falls_back(monkeypatch):
    def boom(*a, **k):
        raise ModelError("down")

    monkeypatch.setattr(appmod, "load_settings", lambda: CONFIGURED)
    monkeypatch.setattr(appmod, "segment_image", boom)
    r = client.post("/segment", files={"frame": ("f.jpg", b"\xff\xd8x", "image/jpeg")})
    body = r.json()
    assert body["source"] == "fallback" and body["segment"] is None


def test_segment_rejects_huge_frame():
    big = b"x" * (MAX_FRAME_BYTES + 1)
    r = client.post("/segment", files={"frame": ("f.jpg", big, "image/jpeg")})
    assert r.status_code == 413


def test_segment_rejects_long_prompt():
    r = client.post(
        "/segment",
        data={"prompt": "x" * 201},
        files={"frame": ("f.jpg", b"x", "image/jpeg")},
    )
    assert r.status_code == 422
