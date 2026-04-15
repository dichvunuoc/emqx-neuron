#!/usr/bin/env python3
"""Minimal OPC UA server for functional tests (requires asyncua: pip install asyncua).

Usage:
  python3 opcua_asyncua_server.py <listen_port>

Prints:
  NEURON_OPCUA_ADDR=<namespace>!s=NeuronTestInt32
  NEURON_OPCUA_READY
"""

from __future__ import annotations

import asyncio
import logging
import sys


async def _main(port: int) -> None:
    try:
        from asyncua import Server, ua
    except ImportError:
        print("NEURON_OPCUA_ERROR=asyncua not installed", flush=True)
        sys.exit(1)

    logging.getLogger("asyncua").setLevel(logging.WARNING)

    server = Server()
    await server.init()
    server.set_endpoint(f"opc.tcp://0.0.0.0:{port}/freeopcua/server/")
    idx = await server.register_namespace("urn:neuron:opcua-ft")
    objects = server.nodes.objects
    nid = ua.NodeId("NeuronTestInt32", idx)
    v = await objects.add_variable(
        nid, "NeuronTestInt32", 42, varianttype=ua.VariantType.Int32
    )
    await v.set_writable(True)
    print(f"NEURON_OPCUA_ADDR={idx}!s=NeuronTestInt32", flush=True)
    # async with server calls start() in __aenter__; do not call start() again.
    async with server:
        print("NEURON_OPCUA_READY", flush=True)
        await asyncio.Future()


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: opcua_asyncua_server.py <port>", file=sys.stderr)
        sys.exit(2)
    port = int(sys.argv[1])
    asyncio.run(_main(port))


if __name__ == "__main__":
    main()
