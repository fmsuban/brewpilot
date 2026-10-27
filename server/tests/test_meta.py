import json
from pathlib import Path

import httpx
import pytest

from server.meta import (
    MetaSettings,
    ModelError,
    complete_json,
    complete_json_with_image,
    load_settings,
    parse_sam_events,
    segment_image,
    snapshot_to_segment,
)

FIXTURES = Path(__file__).parent / "fixtures"


def _sse_events(name: str) -> list:
    events = []
    for chunk in (FIXTURES / name).read_text().split("\n\n"):
        for line in chunk.splitlines():
            if line.startswith("data: "):
                text = line[6:].strip()
                if text == "[DONE]" or not text:
                    continue
                events.append(json.loads(text))
    return events

SETTINGS = MetaSettings("https://api.meta.ai/v1", "test-key", "s", "w", "sam", 25)


def _responses_payload(text: str) -> dict:
    return {
        "output": [
            {
                "type": "message",
                "content": [{"type": "output_text", "text": text}],
            }
        ]
    }


def _client_for(handler) -> httpx.Client:
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_complete_json_success():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/responses"
        assert request.headers["authorization"] == "Bearer test-key"
        body = json.loads(request.content)
        assert body["model"] == "muse-spark-1.3"
        assert body["temperature"] == 0
        return httpx.Response(200, json=_responses_payload('{"a": 1}'))

    out = complete_json(SETTINGS, "muse-spark-1.3", "sys", "hi", _client_for(handler))
    assert out == {"a": 1}


def test_complete_json_strips_fences():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_responses_payload('```json\n{"a": 1}\n```'))

    out = complete_json(SETTINGS, "m", "s", "u", _client_for(handler))
    assert out == {"a": 1}


def test_complete_json_http_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, text="boom")

    with pytest.raises(ModelError, match="HTTP 500"):
        complete_json(SETTINGS, "m", "s", "u", _client_for(handler))


def test_complete_json_transport_error():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    with pytest.raises(ModelError, match="transport"):
        complete_json(SETTINGS, "m", "s", "u", _client_for(handler))


def test_complete_json_no_text():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"output": [{"type": "reasoning"}]})

    with pytest.raises(ModelError, match="no text"):
        complete_json(SETTINGS, "m", "s", "u", _client_for(handler))


def test_complete_json_not_json():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json=_responses_payload("just prose"))

    with pytest.raises(ModelError, match="not JSON"):
        complete_json(SETTINGS, "m", "s", "u", _client_for(handler))


def test_complete_json_unconfigured():
    with pytest.raises(ModelError, match="not set"):
        complete_json(MetaSettings("", "", "s", "w", "sam", 25), "m", "s", "u")


def test_load_settings_prefers_meta_key(monkeypatch):
    monkeypatch.setenv("META_API_KEY", "meta")
    monkeypatch.setenv("MODEL_API_KEY", "docs")
    assert load_settings().api_key == "meta"


def test_load_settings_falls_back_to_docs_key(monkeypatch):
    monkeypatch.delenv("META_API_KEY", raising=False)
    monkeypatch.setenv("MODEL_API_KEY", "docs")
    assert load_settings().api_key == "docs"


def test_complete_json_with_image_body():
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert body["model"] == "muse-wonder-1.0"
        user = body["input"][1]
        kinds = [p["type"] for p in user["content"]]
        assert kinds == ["input_text", "input_image"]
        assert user["content"][1]["image_url"].startswith("data:image/jpeg;base64,")
        return httpx.Response(200, json=_responses_payload('{"ok": true}'))

    out = complete_json_with_image(
        SETTINGS, "muse-wonder-1.0", "s", "u", "QUJD", client=_client_for(handler)
    )
    assert out == {"ok": True}


def test_sam_fixture_parses_to_boxes_and_masks():
    snap = parse_sam_events(_sse_events("sam_avocado.sse"))
    seg = snapshot_to_segment(snap, "avocado")
    assert len(seg["boxes"]) == 2
    assert seg["boxes"][0] == {"x1": 662, "y1": 228, "x2": 1174, "y2": 644}
    assert len(seg["masks"]) == 2
    assert seg["masks"][0]["w"] == 512 and seg["masks"][0]["h"] == 416
    assert seg["masks"][0]["counts"]


def test_sam_empty_fixture_raises():
    snap = parse_sam_events(_sse_events("sam_empty.sse"))
    with pytest.raises(ModelError, match="no masks"):
        snapshot_to_segment(snap, "coffee bed")


def test_segment_image_posts_sam_body():
    sse = (FIXTURES / "sam_avocado.sse").read_bytes()

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert body["model"] == "sam-3.1"
        assert body["stream"] is True
        assert body["metadata"] == {"mask_encoding": "one_bit"}
        content = body["input"][0]["content"]
        assert content[0] == {"type": "input_text", "text": "avocado"}
        assert content[1]["image_url"].startswith("data:image/jpeg;base64,")
        return httpx.Response(200, content=sse)

    out = segment_image(SETTINGS, "sam-3.1", "avocado", "QUJD", client=_client_for(handler))
    assert len(out["masks"]) == 2
