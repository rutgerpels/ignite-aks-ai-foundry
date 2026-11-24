"""Caldova plant signals MCP server (mock).

Exposes production-line telemetry, readiness checks and a camera frame for the
Caldova Pharmaceuticals demo from Ignite BRK420.
"""
import base64
import io
import os
import random
from datetime import datetime, timedelta, timezone

from mcp.server.fastmcp import FastMCP
from PIL import Image, ImageDraw

mcp = FastMCP("caldova-plant-signals", host="0.0.0.0", port=int(os.getenv("PORT", "8080")), stateless_http=True)

PLANTS = {"plant-1": "Basel", "plant-2": "Cork", "plant-3": "Singapore", "plant-4": "Indianapolis"}

LINES = {
    f"line-{i}": {
        "line_id": f"line-{i}",
        "plant": "plant-2",
        "product": ["Amoxicillin 500mg", "Metformin 850mg", "Atorvastatin 20mg", "Ibuprofen 400mg"][i % 4],
        "equipment_id": f"BLP-{200 + i}",
        "equipment": "Blister packaging machine (thermoform + heat seal)",
        "status": "running",
        "oee": round(random.uniform(0.78, 0.9), 2),
    }
    for i in range(1, 13)
}
LINES["line-7"].update(status="micro-stops", oee=0.61)


def _series(base: float, drift: float, noise: float, n: int = 12) -> list[dict]:
    now = datetime.now(timezone.utc)
    return [
        {
            "ts": (now - timedelta(minutes=5 * (n - k))).strftime("%H:%M"),
            "value": round(base + drift * k + random.uniform(-noise, noise), 2),
        }
        for k in range(n)
    ]


@mcp.tool()
def list_lines() -> list[dict]:
    """List all production lines in Plant 2 with status and OEE."""
    return list(LINES.values())


@mcp.tool()
def get_line_signals(line_id: str) -> dict:
    """Return the last hour of key sensor signals and alarms for a production line."""
    line = LINES.get(line_id)
    if not line:
        return {"error": f"unknown line {line_id}"}
    if line_id != "line-7":
        return {
            "line_id": line_id,
            "sealing_temp_c": _series(165, 0, 0.6),
            "vacuum_kpa": _series(-78, 0, 0.5),
            "reject_rate_pct": _series(0.4, 0, 0.1),
            "alarms": [],
        }
    return {
        "line_id": line_id,
        "equipment_id": line["equipment_id"],
        "sealing_temp_c": _series(165, -1.4, 0.4),
        "sealing_temp_setpoint_c": 165,
        "vacuum_kpa": _series(-78, 0.2, 0.3),
        "reject_rate_pct": _series(0.4, 0.55, 0.15),
        "micro_stops_last_hour": 14,
        "alarms": [
            {"code": "E-417", "text": "Seal station temperature below tolerance (-10C)", "count": 9},
            {"code": "W-122", "text": "Vision inspection: incomplete seal on blister cavity", "count": 31},
            {"code": "W-045", "text": "Forming vacuum low", "count": 2},
        ],
    }


@mcp.tool()
def get_readiness_checks(line_id: str) -> list[dict]:
    """Return the start-up readiness checklist state for a production line."""
    checks = [
        {"check": "Line clearance completed", "ok": True},
        {"check": "Foil and PVC lot verified", "ok": True},
        {"check": "Seal plate temperature within +/-3C", "ok": line_id != "line-7"},
        {"check": "Vision system calibrated today", "ok": True},
        {"check": "Heater cartridge resistance check (weekly)", "ok": line_id != "line-7"},
    ]
    return checks


def _frame(defect: bool) -> str:
    img = Image.new("RGB", (480, 320), (210, 214, 220))
    d = ImageDraw.Draw(img)
    for r in range(2):
        for c in range(5):
            x, y = 40 + c * 85, 60 + r * 120
            d.rounded_rectangle([x, y, x + 60, y + 90], 18, fill=(245, 245, 245), outline=(120, 120, 120), width=3)
            d.ellipse([x + 15, y + 25, x + 45, y + 65], fill=(240, 200, 60))
            if defect and (r, c) in {(0, 3), (1, 1), (1, 4)}:
                d.line([x + 2, y + 10, x + 58, y + 30], fill=(40, 40, 40), width=4)
                d.polygon([(x + 5, y + 5), (x + 30, y + 2), (x + 10, y + 25)], fill=(90, 90, 90))
    d.text((10, 10), "LINE-7 SEAL STATION CAM 2" if defect else "SEAL STATION CAM", fill=(0, 0, 0))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


@mcp.tool()
def get_camera_frame(line_id: str) -> dict:
    """Return the latest seal-station camera frame (base64 PNG) for a production line."""
    return {"line_id": line_id, "mime_type": "image/png", "image_base64": _frame(line_id == "line-7")}


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
