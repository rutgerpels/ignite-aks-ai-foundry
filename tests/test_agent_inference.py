import asyncio
import importlib.util
import json
import re
import sys
from pathlib import Path
from unittest.mock import AsyncMock

import httpx
import pytest


def test_baseline_manifest_pins_vision_to_ollama():
    manifest = (Path(__file__).resolve().parents[1] / "k8s" / "agent" / "agent.yaml").read_text()
    config = dict(re.findall(r'^  (LLM_BASE_URL|VISION_BASE_URL|VISION_API_KEY): "([^"]+)"$', manifest, re.MULTILINE))
    assert config["VISION_BASE_URL"] == config["LLM_BASE_URL"] == "http://${LLM_IP}:11434/v1"
    assert config["VISION_API_KEY"] == "not-needed"


@pytest.mark.parametrize(
    ("chat_url", "chat_model", "chat_key", "chat_path"),
    [
        ("http://10.10.0.10:11434/v1", "qwen2.5:1.5b", "not-needed", "/v1/chat/completions"),
        ("https://example.openai.azure.com/openai/v1/", "caldova-chat", "test-key", "/openai/v1/chat/completions"),
    ],
)
def test_chat_and_vision_use_separate_endpoints(monkeypatch, chat_url, chat_model, chat_key, chat_path):
    monkeypatch.setenv("LLM_BASE_URL", chat_url)
    monkeypatch.setenv("LLM_MODEL", chat_model)
    monkeypatch.setenv("LLM_API_KEY", chat_key)
    monkeypatch.setenv("VISION_BASE_URL", "http://10.10.0.10:11434/v1")
    monkeypatch.setenv("VISION_API_KEY", "not-needed")
    monkeypatch.setenv("VISION_MODEL", "moondream")
    monkeypatch.delenv("APPLICATIONINSIGHTS_CONNECTION_STRING", raising=False)

    spec = importlib.util.spec_from_file_location(
        "caldova_test_app", Path(__file__).resolve().parents[1] / "src" / "agent" / "app.py"
    )
    module = importlib.util.module_from_spec(spec)
    monkeypatch.setitem(sys.modules, spec.name, module)
    spec.loader.exec_module(module)
    requests = []

    def respond(request):
        body = json.loads(request.content)
        requests.append((request, body))
        if body.get("tools") and len([r for r, b in requests if b.get("tools")]) == 1:
            message = {
                "role": "assistant",
                "content": None,
                "tool_calls": [{"id": "call-1", "type": "function",
                                "function": {"name": "get_line_signals", "arguments": '{"line_id":"line-7"}'}}],
            }
        else:
            message = {"role": "assistant", "content": "test response"}
        return httpx.Response(200, json={"id": "test", "object": "chat.completion",
                                         "created": 1, "model": body["model"],
                                         "choices": [{"index": 0, "message": message, "finish_reason": "stop"}]})

    async def tool(server, name, args):
        if name == "get_camera_frame":
            return {"image_base64": "aW1hZ2U="}
        if name == "get_line_signals":
            return {"alarms": [], "equipment_id": "equipment"}
        return {}

    module.call_tool = AsyncMock(side_effect=tool)
    module.list_tools = AsyncMock(return_value=[{
        "server": "plant-signals", "name": "get_line_signals", "description": "Get signals",
        "schema": {"type": "object", "properties": {"line_id": {"type": "string"}}},
    }])

    async def exercise():
        await module.llm._client.aclose()
        await module.vision._client.aclose()
        module.llm._client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
        module.vision._client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
        try:
            guided = await module.troubleshoot(module.TroubleshootRequest(mode="guided"))
            autonomous = await module.troubleshoot(module.TroubleshootRequest(mode="autonomous"))
            inspected = await module.inspect(module.TroubleshootRequest())
            config = await module.config()
        finally:
            await module.llm.close()
            await module.vision.close()
        return guided, autonomous, inspected, config

    guided, autonomous, inspected, config = asyncio.run(exercise())
    assert guided["analysis"] == autonomous["analysis"] == "test response"
    assert autonomous["tool_calls"][0]["tool"] == "get_line_signals"
    assert inspected["model"] == "moondream"
    assert inspected["description"] == "test response"
    assert config["llm_model"] == chat_model
    assert chat_key not in json.dumps(config)
    assert len(requests) == 5
    for request, body in requests[:-1]:
        assert str(request.url).startswith(chat_url.rstrip("/"))
        assert request.url.path == chat_path
        assert request.headers["authorization"] == f"Bearer {chat_key}"
        assert body["model"] == chat_model
    request, body = requests[-1]
    assert str(request.url) == "http://10.10.0.10:11434/v1/chat/completions"
    assert request.headers["authorization"] == "Bearer not-needed"
    assert body["model"] == "moondream"
    assert body["messages"][0]["content"][1]["image_url"]["url"].startswith("data:image/png;base64,")
