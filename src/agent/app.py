"""Caldova line troubleshooting agent.

A small agent that calls MCP tools (plant signals + maintenance) and reasons with an
OpenAI-compatible model endpoint. On this lab the endpoint is Ollama running CPU models
on the inference AKS cluster; swap LLM_BASE_URL/LLM_API_KEY/LLM_MODEL to point at an
AKS AI Manager namespace endpoint or a Foundry deployment instead.
"""
import json
import os
import time

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client
from openai import AsyncOpenAI
from pydantic import BaseModel

LLM_BASE_URL = os.getenv("LLM_BASE_URL", "http://localhost:11434/v1")
LLM_API_KEY = os.getenv("LLM_API_KEY", "not-needed")
LLM_MODEL = os.getenv("LLM_MODEL", "qwen2.5:1.5b")
VISION_BASE_URL = os.getenv("VISION_BASE_URL", LLM_BASE_URL)
VISION_API_KEY = os.getenv("VISION_API_KEY", LLM_API_KEY)
VISION_MODEL = os.getenv("VISION_MODEL", "moondream")
MCP_SERVERS = {
    "plant-signals": os.getenv("MCP_PLANT_SIGNALS_URL", "http://mcp-plant-signals:8080/mcp"),
    "maintenance": os.getenv("MCP_MAINTENANCE_URL", "http://mcp-maintenance:8080/mcp"),
}
MAX_STEPS = int(os.getenv("AGENT_MAX_STEPS", "6"))

SYSTEM_PROMPT = (
    "You are the Caldova Pharmaceuticals line troubleshooting agent for Plant 2. "
    "Given telemetry, readiness checks, manual excerpts and maintenance history, produce a concise "
    "root-cause analysis: 1) most likely root cause, 2) evidence, 3) step-by-step fix, "
    "4) spare parts needed, 5) estimated time to restart. Be factual and only use the provided data. "
    "Never dispatch a technician yourself; recommend a work order for human approval."
)

llm = AsyncOpenAI(base_url=LLM_BASE_URL, api_key=LLM_API_KEY, timeout=600)
vision = AsyncOpenAI(base_url=VISION_BASE_URL, api_key=VISION_API_KEY, timeout=600)


async def call_tool(server: str, tool: str, args: dict):
    async with streamablehttp_client(MCP_SERVERS[server]) as (read, write, _):
        async with ClientSession(read, write) as session:
            await session.initialize()
            result = await session.call_tool(tool, args)
            if result.structuredContent is not None:
                data = result.structuredContent
                return data.get("result", data) if isinstance(data, dict) and len(data) == 1 else data
            texts = [c.text for c in result.content if getattr(c, "text", None)]
            try:
                return json.loads(texts[0]) if len(texts) == 1 else [json.loads(t) for t in texts]
            except (json.JSONDecodeError, IndexError):
                return "\n".join(texts)


async def list_tools() -> list[dict]:
    tools = []
    for server, url in MCP_SERVERS.items():
        async with streamablehttp_client(url) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                for t in (await session.list_tools()).tools:
                    tools.append({"server": server, "name": t.name, "description": t.description, "schema": t.inputSchema})
    return tools


if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    # Traces (incl. gen_ai spans for model calls) land in the App Insights connected to Foundry.
    os.environ.setdefault("OTEL_SERVICE_NAME", "caldova-agent")
    os.environ.setdefault("OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT", "true")
    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor()
    try:
        from opentelemetry.instrumentation.openai_v2 import OpenAIInstrumentor

        OpenAIInstrumentor().instrument()
    except Exception as exc:  # beta package; tracing of model calls is optional
        print(f"OpenAI instrumentation disabled: {exc}")

app = FastAPI(title="Caldova troubleshooting agent")
app.mount("/static", StaticFiles(directory=os.path.join(os.path.dirname(__file__), "static")), name="static")


class TroubleshootRequest(BaseModel):
    line_id: str = "line-7"
    mode: str = "guided"  # guided = fixed tool plan; autonomous = model chooses tools


@app.get("/")
async def index():
    return FileResponse(os.path.join(os.path.dirname(__file__), "static", "index.html"))


@app.get("/healthz")
async def healthz():
    return {"ok": True}


@app.get("/api/config")
async def config():
    return {"llm_base_url": LLM_BASE_URL, "llm_model": LLM_MODEL, "vision_model": VISION_MODEL,
            "mcp_servers": MCP_SERVERS, "sandbox": os.getenv("SANDBOX_RUNTIME", "unknown")}


@app.get("/api/lines")
async def lines():
    return await call_tool("plant-signals", "list_lines", {})


@app.get("/api/tools")
async def tools():
    return await list_tools()


async def guided(line_id: str, trace: list) -> list[dict]:
    async def step(server, tool, args):
        t0 = time.perf_counter()
        out = await call_tool(server, tool, args)
        trace.append({"server": server, "tool": tool, "args": args, "ms": int((time.perf_counter() - t0) * 1000)})
        return out

    signals = await step("plant-signals", "get_line_signals", {"line_id": line_id})
    readiness = await step("plant-signals", "get_readiness_checks", {"line_id": line_id})
    codes = " ".join(a["code"] for a in signals.get("alarms", [])) if isinstance(signals, dict) else ""
    manual = await step("maintenance", "search_equipment_manual", {"query": codes or "restart micro-stop"})
    equipment = signals.get("equipment_id", "") if isinstance(signals, dict) else ""
    history = await step("maintenance", "get_maintenance_history", {"equipment_id": equipment}) if equipment else []
    spares = await step("maintenance", "check_spare_parts", {"part_number": "HC-650W"})
    context = {"signals": _summarize(signals), "readiness": readiness, "manual": manual,
               "maintenance_history": history, "spares": spares}
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": f"Line {line_id} has micro-stops. Data:\n{json.dumps(context, indent=1)}"},
    ]


def _summarize(signals):
    if not isinstance(signals, dict):
        return signals
    out = dict(signals)
    for k, v in signals.items():
        if isinstance(v, list) and v and isinstance(v[0], dict) and "value" in v[0]:
            out[k] = {"first": v[0]["value"], "last": v[-1]["value"], "points": len(v)}
    return out


async def autonomous(line_id: str, trace: list) -> list[dict]:
    available = await list_tools()
    owner = {t["name"]: t["server"] for t in available}
    oa_tools = [{"type": "function", "function": {"name": t["name"], "description": t["description"],
                                                  "parameters": t["schema"]}}
                for t in available if t["name"] not in ("get_camera_frame", "create_work_order")]
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT + " Use the tools to gather evidence before answering."},
        {"role": "user", "content": f"Troubleshoot micro-stops on {line_id}."},
    ]
    for _ in range(MAX_STEPS):
        resp = await llm.chat.completions.create(model=LLM_MODEL, messages=messages, tools=oa_tools, temperature=0)
        msg = resp.choices[0].message
        if not msg.tool_calls:
            break
        messages.append(msg.model_dump(exclude_none=True))
        for call in msg.tool_calls:
            args = json.loads(call.function.arguments or "{}")
            t0 = time.perf_counter()
            try:
                out = await call_tool(owner[call.function.name], call.function.name, args)
            except Exception as exc:  # surface tool errors to the model
                out = {"error": str(exc)}
            trace.append({"server": owner.get(call.function.name), "tool": call.function.name, "args": args,
                          "ms": int((time.perf_counter() - t0) * 1000)})
            messages.append({"role": "tool", "tool_call_id": call.id,
                             "content": json.dumps(_summarize(out) if isinstance(out, dict) else out)[:6000]})
    return messages


@app.post("/api/troubleshoot")
async def troubleshoot(req: TroubleshootRequest):
    trace: list = []
    t0 = time.perf_counter()
    try:
        messages = await (autonomous(req.line_id, trace) if req.mode == "autonomous" else guided(req.line_id, trace))
        resp = await llm.chat.completions.create(model=LLM_MODEL, messages=messages, temperature=0.2, max_tokens=600)
    except Exception as exc:
        raise HTTPException(502, f"{type(exc).__name__}: {exc}") from exc
    usage = resp.usage.model_dump() if resp.usage else {}
    return {"line_id": req.line_id, "mode": req.mode, "model": LLM_MODEL, "analysis": resp.choices[0].message.content,
            "tool_calls": trace, "usage": usage, "seconds": round(time.perf_counter() - t0, 1)}


@app.post("/api/inspect")
async def inspect(req: TroubleshootRequest):
    t0 = time.perf_counter()
    frame = await call_tool("plant-signals", "get_camera_frame", {"line_id": req.line_id})
    try:
        resp = await vision.chat.completions.create(
            model=VISION_MODEL,
            max_tokens=200,
            messages=[{"role": "user", "content": [
                {"type": "text", "text": "This is a camera image of blister packs at a heat-seal station. "
                                         "Describe any blisters that look damaged, torn or not sealed."},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{frame['image_base64']}"}},
            ]}],
        )
    except Exception as exc:
        raise HTTPException(502, f"{type(exc).__name__}: {exc}") from exc
    return {"line_id": req.line_id, "model": VISION_MODEL, "image_base64": frame["image_base64"],
            "description": resp.choices[0].message.content, "seconds": round(time.perf_counter() - t0, 1)}
