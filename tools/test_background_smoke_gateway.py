"""Contract tests for the emulator-only, controllable stock Gateway fixture."""
import asyncio
import importlib.util
from pathlib import Path
import unittest

from aiohttp import ClientSession, web

SPEC = importlib.util.spec_from_file_location(
    "background_smoke_gateway", Path(__file__).with_name("background_smoke_gateway.py")
)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SmokeGatewayContractTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.state = MODULE.SmokeState()
        self.runner = web.AppRunner(MODULE.create_app(self.state))
        await self.runner.setup()
        self.site = web.TCPSite(self.runner, "127.0.0.1", 0)
        await self.site.start()
        self.origin = f"http://127.0.0.1:{self.runner.addresses[0][1]}"
        self.client = ClientSession(headers={"Authorization": f"Bearer {MODULE.TEST_KEY}"})

    async def asyncTearDown(self):
        await self.client.close()
        await self.runner.cleanup()

    async def open_socket(self):
        ws = await self.client.ws_connect(self.origin + "/api/ws?ticket=smoke-ticket")
        ready = await ws.receive_json(timeout=2)
        self.assertEqual(ready["params"]["type"], "gateway.ready")
        return ws

    async def rpc_result(self, ws, rpc_id):
        for _ in range(20):
            frame = await ws.receive_json(timeout=2)
            if frame.get("id") == rpc_id:
                return frame["result"]
        self.fail("RPC response not received")

    async def test_submitted_turn_survives_socket_loss_and_resume_never_submits(self):
        ws = await self.open_socket()
        await ws.send_json({"jsonrpc":"2.0","id":1,"method":"session.resume","params":{"session_id":"smoke-chat-a"}})
        bound = await self.rpc_result(ws, 1)
        self.assertFalse(bound["running"])
        await ws.send_json({"jsonrpc":"2.0","id":2,"method":"prompt.submit","params":{"session_id":bound["session_id"],"prompt":"fixture request"}})
        await asyncio.wait_for(self.state.started.wait(), 2)
        await ws.close()
        self.assertTrue(self.state.chats["smoke-chat-a"]["running"])
        ws2 = await self.open_socket()
        await ws2.send_json({"jsonrpc":"2.0","id":3,"method":"session.resume","params":{"session_id":"smoke-chat-a"}})
        rebound = await self.rpc_result(ws2, 3)
        self.assertTrue(rebound["running"])
        self.assertEqual(self.state.submit_count, 1)
        for _ in range(2):
            response = await self.client.post(self.origin+"/test/advance", json={"session_id":"smoke-chat-a"})
            self.assertEqual(response.status, 200)
        self.assertFalse(self.state.chats["smoke-chat-a"]["running"])
        response = await self.client.get(self.origin+"/api/sessions/smoke-chat-a/messages")
        rows = (await response.json())["data"]
        self.assertEqual(rows[-1]["content"], "Fixture final answer C.")
        self.assertGreater(rows[-1]["id"], rows[0]["id"])
        self.assertEqual(self.state.submit_count, 1)
        await ws2.close()

    async def test_protected_reads_reject_missing_key(self):
        async with ClientSession() as client:
            response = await client.get(self.origin+"/api/sessions")
            self.assertEqual(response.status, 401)
            response = await client.get(self.origin+"/health")
            self.assertEqual(response.status, 200)


if __name__ == "__main__":
    unittest.main()
