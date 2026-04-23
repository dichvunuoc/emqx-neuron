#!/usr/bin/env python3
import asyncio
import json
import os
import ssl
from datetime import datetime, timezone

import websockets

HOST = os.environ.get("MOCK_ROUTER_HOST", "0.0.0.0")
PORT = int(os.environ.get("MOCK_ROUTER_PORT", "9001"))
USE_TLS = os.environ.get("MOCK_ROUTER_TLS", "1") == "1"
CERT_PATH = os.environ.get("MOCK_ROUTER_CERT", "/app/certs/server.crt")
KEY_PATH = os.environ.get("MOCK_ROUTER_KEY", "/app/certs/server.key")


async def handler(websocket):
    async for raw in websocket:
        try:
            frame = json.loads(raw)
        except Exception:
            continue

        frame_type = frame.get("type")
        if frame_type == "HELLO":
            await websocket.send(
                json.dumps(
                    {
                        "type": "HELLO_ACK",
                        "payload": {
                            "serverTime": datetime.now(timezone.utc)
                            .isoformat()
                            .replace("+00:00", "Z")
                        },
                    }
                )
            )
        elif frame_type == "HEARTBEAT":
            await websocket.send(json.dumps({"type": "PING_ACK", "payload": {}}))


async def main():
    ssl_ctx = None
    scheme = "ws"
    if USE_TLS:
        ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_ctx.load_cert_chain(CERT_PATH, KEY_PATH)
        scheme = "wss"

    async with websockets.serve(handler, HOST, PORT, ssl=ssl_ctx):
        print(f"mock-router listening on {scheme}://{HOST}:{PORT}")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
