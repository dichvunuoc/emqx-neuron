import os
import select
import socket
import subprocess
import sys
import time
import uuid

import pytest

import neuron.api as api
import neuron.config as config
from neuron.common import description
from neuron.error import NEU_ERR_SUCCESS


def _has_asyncua():
    try:
        import asyncua  # noqa: F401

        return True
    except ImportError:
        return False


def _pick_free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _wait_opcua_sim_ready(proc, deadline_sec=25.0):
    """Read stdout until NEURON_OPCUA_READY; return address string or raise."""
    addr = None
    deadline = time.time() + deadline_sec
    while time.time() < deadline:
        if proc.poll() is not None:
            rest = proc.stdout.read() if proc.stdout else ""
            raise RuntimeError(
                "OPC UA simulator exited early: %s\n%s" % (proc.returncode, rest)
            )
        ready, _, _ = select.select([proc.stdout], [], [], 0.5)
        if not ready:
            continue
        line = proc.stdout.readline()
        if not line:
            continue
        line = line.strip()
        if line.startswith("NEURON_OPCUA_ADDR="):
            addr = line.split("=", 1)[1]
        if line == "NEURON_OPCUA_READY":
            break
    else:
        raise RuntimeError("timeout waiting for NEURON_OPCUA_READY from simulator")
    if addr is None:
        raise RuntimeError("simulator did not print NEURON_OPCUA_ADDR")
    return addr


@pytest.fixture
def opcua_sim():
    """Starts asyncua simulator; yields dict with proc, addr, port, endpoint."""
    ft_root = os.path.dirname(os.path.dirname(__file__))
    script = os.path.join(ft_root, "simulator", "opcua_asyncua_server.py")
    port = _pick_free_port()
    proc = subprocess.Popen(
        [sys.executable, script, str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    try:
        addr = _wait_opcua_sim_ready(proc)
        endpoint = "opc.tcp://127.0.0.1:%d/freeopcua/server/" % port
        yield {"proc": proc, "addr": addr, "port": port, "endpoint": endpoint}
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=8)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)


opcua_e2e = pytest.mark.skipif(
    os.environ.get("OPCUA_E2E", "") != "1" or not _has_asyncua(),
    reason="set OPCUA_E2E=1 and pip install asyncua to run OPC UA simulator E2E",
)


class TestOpcUaPlugin:
    @description(given="opc ua plugin is available", when="add opcua node", then="success")
    def test_add_opcua_node(self):
        resp = api.add_node(node="opcua-ft", plugin=config.PLUGIN_OPCUA)
        assert resp.status_code == 200
        assert resp.json()["error"] == NEU_ERR_SUCCESS

    @description(given="opc ua node exists", when="set node params", then="success")
    def test_opcua_setting(self):
        resp = api.opcua_node_setting(
            node="opcua-ft",
            endpoint="opc.tcp://127.0.0.1:4840/",
            timeout=3000,
            enable_auth=False,
        )
        assert resp.status_code == 200
        assert resp.json()["error"] == NEU_ERR_SUCCESS


@opcua_e2e
class TestOpcUaPluginE2e:
    @description(
        given="asyncua simulator and neuron with OPC UA (open62541)",
        when="poll read and scan Objects folder",
        then="read Int32 tag and browse returns references",
    )
    def test_opcua_asyncua_read_and_scan(self, opcua_sim):
        node = None
        try:
            node = "opcua-e2e-" + uuid.uuid4().hex[:8]
            resp = api.add_node(node=node, plugin=config.PLUGIN_OPCUA)
            assert resp.status_code == 200
            assert resp.json()["error"] == NEU_ERR_SUCCESS

            resp = api.opcua_node_setting(
                node=node,
                endpoint=opcua_sim["endpoint"],
                timeout=8000,
                enable_auth=False,
                read_mode=0,
                publish_interval=500,
            )
            assert resp.status_code == 200
            assert resp.json()["error"] == NEU_ERR_SUCCESS

            resp = api.add_group(node=node, group="g1", interval=200)
            assert resp.status_code == 200

            tags = [
                {
                    "name": "v1",
                    "address": opcua_sim["addr"],
                    "attribute": config.NEU_TAG_ATTRIBUTE_READ,
                    "type": config.NEU_TYPE_INT32,
                }
            ]
            resp = api.add_tags(node=node, group="g1", tags=tags)
            assert resp.status_code == 200

            # First successful node setting already transitions INIT -> RUNNING
            # (neu_adapter_set_setting calls neu_adapter_start).

            time.sleep(0.8)

            body = {
                "driver": node,
                "group": "g1",
                "tag": "v1",
                "address": opcua_sim["addr"],
                "attribute": config.NEU_TAG_ATTRIBUTE_READ,
                "type": config.NEU_TYPE_INT32,
                "precision": 0,
                "decimal": 0,
                "bias": 0.0,
            }
            resp = api.test_read_tag(json=body)
            assert resp.status_code == 200
            j = resp.json()
            # /api/v2/read/test JSON is either {"value": ...} on success or {"error": code} on failure
            assert j.get("value") == 42

            val = api.read_tag(node=node, group="g1", tag="v1", sync=True)
            assert val == 42

            resp = api.scan_tags(node=node, id="", ctx="", load_index=0)
            assert resp.status_code == 200
            sj = resp.json()
            assert sj["error"] == NEU_ERR_SUCCESS
            assert sj.get("total", 0) >= 1
        finally:
            if node is not None:
                try:
                    api.del_node(node=node)
                except Exception:
                    pass

    @description(
        given="asyncua simulator",
        when="write Int32 then read",
        then="value matches",
    )
    def test_opcua_asyncua_write_then_read(self, opcua_sim):
        node = None
        try:
            node = "opcua-e2e-w-" + uuid.uuid4().hex[:8]
            resp = api.add_node(node=node, plugin=config.PLUGIN_OPCUA)
            assert resp.status_code == 200
            assert resp.json()["error"] == NEU_ERR_SUCCESS

            resp = api.opcua_node_setting(
                node=node,
                endpoint=opcua_sim["endpoint"],
                timeout=8000,
                enable_auth=False,
                read_mode=0,
                publish_interval=500,
            )
            assert resp.status_code == 200
            assert resp.json()["error"] == NEU_ERR_SUCCESS

            api.add_group(node=node, group="g1", interval=200)
            tags = [
                {
                    "name": "v1",
                    "address": opcua_sim["addr"],
                    "attribute": config.NEU_TAG_ATTRIBUTE_RW,
                    "type": config.NEU_TYPE_INT32,
                }
            ]
            api.add_tags(node=node, group="g1", tags=tags)

            time.sleep(0.8)
            api.write_tag(node=node, group="g1", tag="v1", value=7)
            time.sleep(0.5)
            assert api.read_tag(node=node, group="g1", tag="v1", sync=True) == 7
        finally:
            if node is not None:
                try:
                    api.del_node(node=node)
                except Exception:
                    pass

    @description(
        given="asyncua simulator",
        when="subscription mode and group timer",
        then="last value is delivered to read",
    )
    def test_opcua_asyncua_subscription_read(self, opcua_sim):
        node = None
        try:
            node = "opcua-e2e-s-" + uuid.uuid4().hex[:8]
            resp = api.add_node(node=node, plugin=config.PLUGIN_OPCUA)
            assert resp.status_code == 200
            assert resp.json()["error"] == NEU_ERR_SUCCESS

            resp = api.opcua_node_setting(
                node=node,
                endpoint=opcua_sim["endpoint"],
                timeout=8000,
                enable_auth=False,
                read_mode=1,
                publish_interval=300,
            )
            assert resp.status_code == 200
            assert resp.json()["error"] == NEU_ERR_SUCCESS

            api.add_group(node=node, group="g1", interval=300)
            tags = [
                {
                    "name": "v1",
                    "address": opcua_sim["addr"],
                    "attribute": config.NEU_TAG_ATTRIBUTE_READ_SUBSCRIBE,
                    "type": config.NEU_TYPE_INT32,
                }
            ]
            api.add_tags(node=node, group="g1", tags=tags)

            time.sleep(2.5)
            val = api.read_tag(node=node, group="g1", tag="v1", sync=True)
            assert val == 42
        finally:
            if node is not None:
                try:
                    api.del_node(node=node)
                except Exception:
                    pass
