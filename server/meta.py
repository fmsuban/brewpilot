"""Meta Model API client (https://api.meta.ai/v1, OpenAI-compatible).

Uses the Responses API: POST {base_url}/responses with Bearer auth.
Shapes per https://dev.meta.ai/docs (Responses + image-understanding).
"""

from __future__ import annotations

import asyncio
import json
import os
from dataclasses import dataclass
from typing import Optional

import httpx
from meta_sam_parser import (
    SegmentationBoxRecord,
    SegmentationMaskRecord,
    decode_mask_to_rle,
    image_segmentation_format,
    parse_responses_stream,
)

DEFAULT_BASE_URL = "https://api.meta.ai/v1"
DEFAULT_SPARK_MODEL = "muse-spark-1.3"
DEFAULT_WONDER_MODEL = "muse-wonder-1.0"
DEFAULT_SAM_MODEL = "sam-3.1"


class ModelError(Exception):
    """Any model failure: not configured, transport, timeout, bad JSON."""


@dataclass(frozen=True)
class MetaSettings:
    base_url: str
    api_key: str
    spark_model: str
    wonder_model: str
    sam_model: str
    timeout_s: float

    @property
    def configured(self) -> bool:
        return bool(self.base_url and self.api_key)


def load_settings() -> MetaSettings:
    return MetaSettings(
        base_url=os.environ.get("META_API_BASE_URL", DEFAULT_BASE_URL),
        # META_API_KEY wins; MODEL_API_KEY matches the official docs' convention.
        api_key=os.environ.get("META_API_KEY", "") or os.environ.get("MODEL_API_KEY", ""),
        spark_model=os.environ.get("META_SPARK_MODEL", DEFAULT_SPARK_MODEL),
        wonder_model=os.environ.get("META_WONDER_MODEL", DEFAULT_WONDER_MODEL),
        sam_model=os.environ.get("META_SAM_MODEL", DEFAULT_SAM_MODEL),
        timeout_s=float(os.environ.get("META_TIMEOUT_S", "25")),
    )


def _extract_text(data: dict) -> str:
    """Pull assistant text out of a Responses (or Chat Completions) reply."""
    chunks: list[str] = []
    output = data.get("output")
    if isinstance(output, list):
        for item in output:
            if not isinstance(item, dict) or item.get("type") != "message":
                continue
            content = item.get("content")
            if not isinstance(content, list):
                continue
            for part in content:
                if (
                    isinstance(part, dict)
                    and part.get("type") in ("output_text", "text")
                    and isinstance(part.get("text"), str)
                ):
                    chunks.append(part["text"])
    if chunks:
        return "\n".join(chunks)
    choices = data.get("choices")
    if isinstance(choices, list) and choices and isinstance(choices[0], dict):
        msg = choices[0].get("message", {})
        if isinstance(msg, dict) and isinstance(msg.get("content"), str):
            return msg["content"]
    if isinstance(data.get("output_text"), str):
        return data["output_text"]
    raise ModelError(f"no text in model reply: {str(data)[:200]}")


def _parse_strict_json(text: str) -> dict:
    candidate = text.strip()
    if candidate.startswith("```"):
        lines = candidate.splitlines()
        lines = lines[1:]  # drop opening fence (``` or ```json)
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        candidate = "\n".join(lines).strip()
    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError as e:
        raise ModelError(f"model reply is not JSON: {e} ({text[:120]!r})") from e
    if not isinstance(parsed, dict):
        raise ModelError(f"model reply JSON is not an object: {text[:120]!r}")
    return parsed


def _post_responses(
    settings: MetaSettings,
    model: str,
    input_blocks: list,
    client: Optional[httpx.Client],
) -> dict:
    if not settings.configured:
        raise ModelError("META_API_KEY (or MODEL_API_KEY) not set")
    body = {"model": model, "temperature": 0, "input": input_blocks}
    headers = {
        "Authorization": f"Bearer {settings.api_key}",
        "Content-Type": "application/json",
    }
    owned = client is None
    if owned:
        client = httpx.Client(timeout=settings.timeout_s)
    assert client is not None
    try:
        try:
            resp = client.post(f"{settings.base_url}/responses", headers=headers, json=body)
        except httpx.HTTPError as e:
            raise ModelError(f"transport: {e}") from e
    finally:
        if owned:
            client.close()
    if resp.status_code != 200:
        raise ModelError(f"HTTP {resp.status_code}: {resp.text[:200]}")
    try:
        data = resp.json()
    except ValueError as e:
        raise ModelError(f"non-JSON HTTP reply: {e}") from e
    if not isinstance(data, dict):
        raise ModelError(f"HTTP reply JSON is not an object: {resp.text[:120]!r}")
    return _parse_strict_json(_extract_text(data))


def complete_json(
    settings: MetaSettings,
    model: str,
    system: str,
    user: str,
    client: Optional[httpx.Client] = None,
) -> dict:
    """One strict-JSON text completion. Raises ModelError on any failure."""
    return _post_responses(
        settings,
        model,
        [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        client,
    )


def complete_json_with_image(
    settings: MetaSettings,
    model: str,
    system: str,
    user_text: str,
    image_b64: str,
    mime: str = "image/jpeg",
    client: Optional[httpx.Client] = None,
) -> dict:
    """One strict-JSON completion over text + one image. Raises ModelError."""
    return _post_responses(
        settings,
        model,
        [
            {"role": "system", "content": system},
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": user_text},
                    {"type": "input_image", "image_url": f"data:{mime};base64,{image_b64}"},
                ],
            },
        ],
        client,
    )


# --- SAM 3.1 segmentation (Responses stream + meta-sam-parser) ---


def parse_sam_events(events: list) -> object:
    """Run the SAM stream parser over buffered SSE payloads (sync wrapper)."""

    async def _run():
        async def _gen():
            for e in events:
                yield e

        snap = None
        async for s in parse_responses_stream(_gen(), image_segmentation_format()):
            snap = s
        return snap

    return asyncio.run(_run())


def snapshot_to_segment(snapshot, prompt: str) -> dict:
    """Boxes + RLE masks from a parsed snapshot. Raises ModelError if empty."""
    if snapshot is None:
        raise ModelError("SAM returned no masks")
    boxes: list[dict] = []
    masks: list[dict] = []
    for r in snapshot.records:
        if isinstance(r, SegmentationBoxRecord):
            boxes.append({"x1": r.left, "y1": r.top, "x2": r.right, "y2": r.bottom})
        elif isinstance(r, SegmentationMaskRecord):
            rle = decode_mask_to_rle(r.mask)
            h, w = rle.size  # (h, w): verified against box dims on live data
            masks.append(
                {
                    "x": r.bounds.left,
                    "y": r.bounds.top,
                    "w": int(w),
                    "h": int(h),
                    "counts": rle.counts,
                }
            )
    if not masks:
        raise ModelError("SAM returned no masks")
    return {"prompt": prompt, "boxes": boxes, "masks": masks}


def segment_image(
    settings: MetaSettings,
    model: str,
    prompt: str,
    image_b64: str,
    mime: str = "image/jpeg",
    client: Optional[httpx.Client] = None,
) -> dict:
    """One SAM text-prompted segmentation. Returns boxes + RLE masks."""
    if not settings.configured:
        raise ModelError("META_API_KEY (or MODEL_API_KEY) not set")
    body = {
        "model": model,
        "input": [
            {
                "type": "message",
                "role": "user",
                "content": [
                    {"type": "input_text", "text": prompt},
                    {"type": "input_image", "image_url": f"data:{mime};base64,{image_b64}"},
                ],
            }
        ],
        "stream": True,
        "metadata": {"mask_encoding": "one_bit"},
    }
    headers = {
        "Authorization": f"Bearer {settings.api_key}",
        "Content-Type": "application/json",
    }
    owned = client is None
    if owned:
        client = httpx.Client(timeout=settings.timeout_s)
    assert client is not None
    try:
        try:
            with client.stream(
                "POST", f"{settings.base_url}/responses", headers=headers, json=body
            ) as resp:
                if resp.status_code != 200:
                    resp.read()
                    raise ModelError(f"HTTP {resp.status_code}: {resp.text[:200]}")
                events: list = []
                for line in resp.iter_lines():
                    if not line.startswith("data: "):
                        continue
                    text = line[6:].strip()
                    if text == "[DONE]" or not text:
                        break
                    try:
                        events.append(json.loads(text))
                    except ValueError:
                        continue
        except httpx.HTTPError as e:
            raise ModelError(f"transport: {e}") from e
    finally:
        if owned:
            client.close()
    try:
        snapshot = parse_sam_events(events)
    except Exception as e:
        raise ModelError(f"SAM parse: {e}") from e
    return snapshot_to_segment(snapshot, prompt)
