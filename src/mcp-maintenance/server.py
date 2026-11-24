"""Caldova maintenance MCP server (mock).

Equipment manuals, maintenance history and work orders for the Caldova demo.
"""
import os
import uuid
from datetime import datetime, timezone

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("caldova-maintenance", host="0.0.0.0", port=int(os.getenv("PORT", "8080")), stateless_http=True)

MANUAL = [
    {
        "section": "7.3 Seal station - low temperature (E-417)",
        "text": "If seal plate temperature drops more than 8C below setpoint while heater output is >90%, "
        "the most likely cause is a degraded heater cartridge (resistance > 48 ohm) or a loose thermocouple. "
        "Lock out the station, measure cartridge resistance (spec 40-44 ohm), re-seat thermocouple TC-2. "
        "Typical repair time: 25 minutes with spare cartridge HC-650W.",
    },
    {
        "section": "7.4 Incomplete seals detected by vision (W-122)",
        "text": "Incomplete seals are almost always a consequence of insufficient seal temperature or pressure. "
        "Resolve E-417 first. If temperature is in tolerance, check seal pressure (6.0 bar) and foil lot.",
    },
    {
        "section": "5.2 Forming vacuum (W-045)",
        "text": "Occasional low vacuum warnings are benign below 5/hour. Inspect vacuum pump filter monthly.",
    },
    {
        "section": "2.1 Restart after micro-stop",
        "text": "After corrective action, run 3 empty indexing cycles, verify 20 consecutive good blisters "
        "on vision, then release the line. QA sign-off required if >50 rejects were produced.",
    },
]

HISTORY = {
    "BLP-207": [
        {"date": "2026-10-02", "action": "Replaced heater cartridge (left)", "by": "tech-114"},
        {"date": "2026-11-03", "action": "Thermocouple TC-2 re-seated after E-417 alarms", "by": "tech-087"},
        {"date": "2026-11-18", "action": "Weekly heater resistance check skipped (no spare technician)", "by": "system"},
    ]
}

SPARES = {"HC-650W": {"description": "Heater cartridge 650W", "on_hand": 3, "location": "Plant 2 stores, bin C-14"}}


@mcp.tool()
def search_equipment_manual(query: str) -> list[dict]:
    """Search the blister packaging machine manual. Use alarm codes (e.g. E-417) or keywords."""
    words = [w.lower() for w in query.replace(",", " ").split() if len(w) > 2]
    scored = [(sum(w in (m["section"] + m["text"]).lower() for w in words), m) for m in MANUAL]
    hits = [m for s, m in sorted(scored, key=lambda x: -x[0]) if s > 0]
    return hits[:3] or MANUAL[:2]


@mcp.tool()
def get_maintenance_history(equipment_id: str) -> list[dict]:
    """Return recent maintenance history for a piece of equipment (e.g. BLP-207)."""
    return HISTORY.get(equipment_id, [])


@mcp.tool()
def check_spare_parts(part_number: str) -> dict:
    """Check on-hand inventory for a spare part number (e.g. HC-650W)."""
    return SPARES.get(part_number, {"error": f"unknown part {part_number}"})


@mcp.tool()
def create_work_order(equipment_id: str, summary: str, priority: str = "high") -> dict:
    """Create a maintenance work order. Requires human approval before a technician is dispatched."""
    return {
        "work_order": f"WO-{uuid.uuid4().hex[:6].upper()}",
        "equipment_id": equipment_id,
        "summary": summary,
        "priority": priority,
        "status": "pending-approval",
        "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
