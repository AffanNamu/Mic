"""Tiny WaveSpeedAI client for listening experiments (not used by the app or the backend).

The key is read from WAVESPEED_API_KEY and never written anywhere. `run()` submits ONCE and never retries the submit
request: a lost answer may still have created (and billed) a task, so check the WaveSpeedAI History page first.

    export WAVESPEED_API_KEY=...
    python3 -I -c "import sys; sys.path.insert(0, 'tool'); import wavespeed_client as ws; print(ws.balance())"

Used 2026-11-01 for the measurements in docs/PROVIDER_EVALUATION.md ("Live results with a funded account").
"""
import json, os, sys, time, urllib.request, urllib.error

KEY = os.environ["WAVESPEED_API_KEY"]
BASE = "https://api.wavespeed.ai"

def call(method, path, body=None, headers=None, raw=False):
    req = urllib.request.Request(BASE + path if path.startswith("/") else path, method=method,
        data=None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode()),
        headers={"Authorization": f"Bearer {KEY}", **({"Content-Type": "application/json"} if isinstance(body, dict) else {}), **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            data = r.read()
            return r.status, (data if raw else json.loads(data))
    except urllib.error.HTTPError as e:
        data = e.read()
        try: return e.code, json.loads(data)
        except Exception: return e.code, data[:300]

def run(model_path, payload, poll=3, limit=600):
    """Submit ONCE (never retried), then poll to a final status. Returns the prediction data object."""
    st, body = call("POST", f"/api/v3/{model_path}", payload)
    if st != 200: raise SystemExit(f"submit failed HTTP {st}: {json.dumps(body)[:400]}")
    task = body["data"]; pid = task["id"]; t0 = time.time()
    while time.time() - t0 < limit:
        time.sleep(poll)
        st, r = call("GET", f"/api/v3/predictions/{pid}/result")
        if st != 200: print("poll HTTP", st, str(r)[:200], file=sys.stderr); continue
        d = r["data"]
        if d["status"] in ("completed", "failed", "cancelled", "timeout", "deleted"):
            d["_seconds"] = round(time.time() - t0, 1); return d
    raise SystemExit(f"still running after {limit}s; task id {pid} (check History before resubmitting)")

def balance():
    return call("GET", "/api/v3/balance")[1]["data"]["balance"]
