"""Modal deployment for the BrewPilot proxy.

One-time setup (needs YOUR Modal account + browser login):
  pip install modal
  modal setup
  modal secret create brewpilot-meta \\
      META_API_BASE_URL=https://api.meta.ai/v1 \\
      MODEL_API_KEY=<tu key> \\
      META_SPARK_MODEL=muse-spark-1.3 \\
      META_WONDER_MODEL=muse-wonder-1.0 \\
      META_SAM_MODEL=sam-3.1

Deploy (from repo root):
  modal deploy server/modal_app.py

Then point ProxyClient.baseURL at the printed https URL.
"""

import modal

app = modal.App("brewpilot-proxy")
image = (
    modal.Image.debian_slim(python_version="3.12")
    .pip_install(
        "fastapi==0.115.0",
        "uvicorn==0.30.6",
        "pydantic==2.9.2",
        "httpx==0.27.2",
        "python-multipart==0.0.12",
        "meta-sam-parser==0.1.0",
    )
    # The key comes from the brewpilot-meta secret; keep local .env out of the image.
    .add_local_dir(
        "server",
        "/root/server",
        ignore=["**/.env", "**/.env.*", "**/__pycache__", "tests"],
    )
)


@app.function(image=image, secrets=[modal.Secret.from_name("brewpilot-meta")])
@modal.asgi_app()
def web():
    import sys

    sys.path.insert(0, "/root")
    from server.app import app as fastapi_app

    return fastapi_app
