import importlib.util
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import threading
import unittest
import urllib.error
import urllib.request
import socket
import uuid
import zlib
from pathlib import Path


SERVER_PATH = Path(__file__).resolve().parents[1] / "tooling" / "clipboard" / "macos_server.py"
PNG_BYTES = b"\x89PNG\r\n\x1a\nfixture-png"


def load_server_module():
    spec = importlib.util.spec_from_file_location("macos_clipboard_server", SERVER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def tiny_valid_png():
    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff"))
        + chunk(b"IEND", b"")
    )


def run_jxa(script, env):
    return subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=5,
        check=True,
    )


def put_tiff_on_private_pasteboard(pasteboard_name, tiff_path):
    env = os.environ.copy()
    env["CLAUDEBOX_TEST_PASTEBOARD"] = pasteboard_name
    env["CLAUDEBOX_TEST_TIFF_PATH"] = str(tiff_path)
    run_jxa(
        """
ObjC.import('AppKit');
ObjC.import('Foundation');
const env = $.NSProcessInfo.processInfo.environment;
const pb = $.NSPasteboard.pasteboardWithName(env.objectForKey('CLAUDEBOX_TEST_PASTEBOARD'));
pb.clearContents;
const data = $.NSData.dataWithContentsOfFile(env.objectForKey('CLAUDEBOX_TEST_TIFF_PATH'));
pb.setDataForType(data, $.NSPasteboardTypeTIFF);
""",
        env,
    )


def clear_private_pasteboard(pasteboard_name):
    env = os.environ.copy()
    env["CLAUDEBOX_TEST_PASTEBOARD"] = pasteboard_name
    run_jxa(
        """
ObjC.import('AppKit');
ObjC.import('Foundation');
const env = $.NSProcessInfo.processInfo.environment;
const pb = $.NSPasteboard.pasteboardWithName(env.objectForKey('CLAUDEBOX_TEST_PASTEBOARD'));
pb.clearContents;
""",
        env,
    )


class FixtureProvider:
    def __init__(self, payload):
        self.payload = payload
        self.calls = 0

    def __call__(self):
        self.calls += 1
        return self.payload


class FixtureTextWriter:
    def __init__(self):
        self.values = []

    def __call__(self, value):
        self.values.append(value)


class RunningServer:
    def __init__(self, module, provider, token="secret-token", text_writer=None):
        self.module = module
        self.provider = provider
        self.token = token
        self.text_writer = text_writer or FixtureTextWriter()

    def __enter__(self):
        self.httpd = self.module.create_server(
            "127.0.0.1",
            0,
            self.token,
            self.provider,
            max_payload_bytes=64,
            text_writer=self.text_writer,
            max_text_bytes=16,
            socket_timeout=0.5,
        )
        self.thread = threading.Thread(target=self.httpd.serve_forever)
        self.thread.start()
        self.url = "http://127.0.0.1:%d" % self.httpd.server_address[1]
        return self

    def __exit__(self, exc_type, exc, tb):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)

    def request(self, path, token=None):
        req = urllib.request.Request(self.url + path)
        if token is not None:
            req.add_header("Authorization", "Bearer " + token)
        return urllib.request.urlopen(req, timeout=5)

    def post_text(self, body, token=None, content_type="text/plain; charset=utf-8"):
        req = urllib.request.Request(self.url + "/text", data=body, method="POST")
        req.add_header("Content-Type", content_type)
        if token is not None:
            req.add_header("Authorization", "Bearer " + token)
        return urllib.request.urlopen(req, timeout=5)


class ClipboardServerTest(unittest.TestCase):
    def test_create_server_does_not_reverse_lookup_bound_host(self):
        module = load_server_module()
        import socket

        original_getfqdn = socket.getfqdn
        httpd = None

        def forbidden_getfqdn(_host):
            raise AssertionError("server startup must not depend on reverse DNS")

        socket.getfqdn = forbidden_getfqdn
        try:
            httpd = module.create_server(
                "127.0.0.1",
                0,
                "secret-token",
                FixtureProvider(None),
            )
            self.assertEqual(httpd.server_name, "127.0.0.1")
            self.assertEqual(httpd.server_port, httpd.server_address[1])
        finally:
            socket.getfqdn = original_getfqdn
            if httpd is not None:
                httpd.server_close()

    def test_bad_token_does_not_read_clipboard_provider(self):
        module = load_server_module()
        provider = FixtureProvider(PNG_BYTES)

        with RunningServer(module, provider) as server:
            with self.assertRaises(urllib.error.HTTPError) as caught:
                server.request("/types", token="wrong-token")

            self.assertEqual(caught.exception.code, 401)
            caught.exception.close()

        self.assertEqual(provider.calls, 0)

    def test_health_requires_auth_without_accessing_clipboard(self):
        module = load_server_module()
        provider = FixtureProvider(PNG_BYTES)
        with RunningServer(module, provider) as server:
            with self.assertRaises(urllib.error.HTTPError) as caught:
                server.request("/health", token="wrong-token")
            self.assertEqual(caught.exception.code, 401)
            caught.exception.close()
            with server.request("/health", token=server.token) as response:
                self.assertEqual(response.status, 204)
                self.assertEqual(response.read(), b"")
            self.assertEqual(server.text_writer.values, [])
        self.assertEqual(provider.calls, 0)

    def test_types_advertises_png_only_when_provider_has_image(self):
        module = load_server_module()
        provider = FixtureProvider(PNG_BYTES)

        with RunningServer(module, provider) as server:
            with server.request("/types", token=server.token) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers["Content-Type"], "application/json")
                self.assertEqual(
                    json.loads(response.read().decode("utf-8")),
                    {"types": ["image/png"]},
                )

        self.assertEqual(provider.calls, 1)

    def test_types_returns_empty_list_without_readable_image(self):
        module = load_server_module()
        provider = FixtureProvider(None)

        with RunningServer(module, provider) as server:
            with server.request("/types", token=server.token) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(json.loads(response.read().decode("utf-8")), {"types": []})

    def test_image_returns_204_when_no_image_is_available(self):
        module = load_server_module()
        provider = FixtureProvider(None)

        with RunningServer(module, provider) as server:
            with server.request("/image", token=server.token) as response:
                self.assertEqual(response.status, 204)
                self.assertEqual(response.read(), b"")

    def test_image_streams_exact_png_bytes(self):
        module = load_server_module()
        provider = FixtureProvider(PNG_BYTES)

        with RunningServer(module, provider) as server:
            with server.request("/image", token=server.token) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers["Content-Type"], "image/png")
                self.assertEqual(response.read(), PNG_BYTES)

    def test_oversized_image_is_rejected_without_leaking_body(self):
        module = load_server_module()
        provider = FixtureProvider(PNG_BYTES + (b"x" * 100))

        with RunningServer(module, provider) as server:
            with self.assertRaises(urllib.error.HTTPError) as caught:
                server.request("/image", token=server.token)

            self.assertEqual(caught.exception.code, 413)
            self.assertEqual(caught.exception.read(), b"")
            caught.exception.close()

    def test_unknown_endpoint_is_controlled_404(self):
        module = load_server_module()
        provider = FixtureProvider(PNG_BYTES)

        with RunningServer(module, provider) as server:
            with self.assertRaises(urllib.error.HTTPError) as caught:
                server.request("/clipboard", token=server.token)

            self.assertEqual(caught.exception.code, 404)
            caught.exception.close()

    def test_post_text_writes_utf8_text(self):
        module = load_server_module()
        writer = FixtureTextWriter()

        with RunningServer(module, FixtureProvider(None), text_writer=writer) as server:
            with server.post_text("hello \u2603".encode("utf-8"), token=server.token) as response:
                self.assertEqual(response.status, 204)
                self.assertEqual(response.read(), b"")

        self.assertEqual(writer.values, ["hello \u2603"])

    def test_post_text_rejects_bad_token_before_waiting_for_body(self):
        module = load_server_module()
        writer = FixtureTextWriter()

        with RunningServer(module, FixtureProvider(None), text_writer=writer) as server:
            raw = (
                "POST /text HTTP/1.1\r\n"
                "Host: 127.0.0.1\r\n"
                "Authorization: Bearer wrong-token\r\n"
                "Content-Type: text/plain; charset=utf-8\r\n"
                "Content-Length: 1000000\r\n"
                "Connection: close\r\n"
                "\r\n"
            ).encode("ascii")
            import socket

            with socket.create_connection(("127.0.0.1", server.httpd.server_address[1]), timeout=5) as sock:
                sock.sendall(raw)
                response = sock.recv(128)

        self.assertIn(b" 401 ", response)
        self.assertEqual(writer.values, [])

    def test_post_text_rejects_oversized_body_before_writing(self):
        module = load_server_module()
        writer = FixtureTextWriter()

        with RunningServer(module, FixtureProvider(None), text_writer=writer) as server:
            with self.assertRaises(urllib.error.HTTPError) as caught:
                server.post_text(b"x" * 17, token=server.token)

            self.assertEqual(caught.exception.code, 413)
            caught.exception.close()

        self.assertEqual(writer.values, [])

    def test_post_text_rejects_invalid_utf8(self):
        module = load_server_module()
        writer = FixtureTextWriter()

        with RunningServer(module, FixtureProvider(None), text_writer=writer) as server:
            with self.assertRaises(urllib.error.HTTPError) as caught:
                server.post_text(b"\xff", token=server.token)

            self.assertEqual(caught.exception.code, 400)
            caught.exception.close()

        self.assertEqual(writer.values, [])

    def test_post_text_rejects_short_body_without_writing(self):
        module = load_server_module()
        writer = FixtureTextWriter()

        with RunningServer(module, FixtureProvider(None), text_writer=writer) as server:
            raw = (
                "POST /text HTTP/1.1\r\n"
                "Host: 127.0.0.1\r\n"
                "Authorization: Bearer secret-token\r\n"
                "Content-Type: text/plain; charset=utf-8\r\n"
                "Content-Length: 12\r\n"
                "Connection: close\r\n"
                "\r\n"
                "short"
            ).encode("ascii")

            with socket.create_connection(("127.0.0.1", server.httpd.server_address[1]), timeout=5) as sock:
                sock.sendall(raw)
                sock.shutdown(socket.SHUT_WR)
                response = sock.recv(256)

        self.assertIn(b" 400 ", response)
        self.assertEqual(writer.values, [])

    def test_non_ascii_authorization_is_rejected_without_type_error(self):
        module = load_server_module()
        provider = FixtureProvider(PNG_BYTES)

        with RunningServer(module, provider) as server:
            raw = (
                b"GET /types HTTP/1.1\r\n"
                b"Host: 127.0.0.1\r\n"
                b"Authorization: Bearer bad-\xff\r\n"
                b"Connection: close\r\n"
                b"\r\n"
            )
            with socket.create_connection(("127.0.0.1", server.httpd.server_address[1]), timeout=5) as sock:
                sock.sendall(raw)
                response = sock.recv(256)

            self.assertIn(b" 401 ", response)

        self.assertEqual(provider.calls, 0)

    def test_partial_request_does_not_block_normal_traffic_or_shutdown(self):
        module = load_server_module()
        provider = FixtureProvider(PNG_BYTES)
        writer = FixtureTextWriter()
        httpd = module.create_server(
            "127.0.0.1",
            0,
            "secret-token",
            provider,
            text_writer=writer,
            max_workers=2,
            socket_timeout=0.2,
        )
        thread = threading.Thread(target=httpd.serve_forever)
        thread.start()
        url = "http://127.0.0.1:%d" % httpd.server_address[1]
        partial = socket.create_connection(("127.0.0.1", httpd.server_address[1]), timeout=5)
        partial.sendall(b"GET /types HTTP/1.1\r\nHost: 127.0.0.1\r\n")
        try:
            req = urllib.request.Request(url + "/types")
            req.add_header("Authorization", "Bearer secret-token")
            with urllib.request.urlopen(req, timeout=5) as response:
                self.assertEqual(json.loads(response.read().decode("utf-8")), {"types": ["image/png"]})

            shutdown_thread = threading.Thread(target=httpd.shutdown)
            shutdown_thread.start()
            shutdown_thread.join(timeout=1)
            self.assertFalse(shutdown_thread.is_alive(), "server shutdown stalled behind partial request")
        finally:
            partial.close()
            httpd.server_close()
            thread.join(timeout=5)

    def test_over_capacity_connection_is_closed_without_blocking_shutdown(self):
        module = load_server_module()
        httpd = module.create_server(
            "127.0.0.1",
            0,
            "secret-token",
            FixtureProvider(PNG_BYTES),
            max_workers=1,
            socket_timeout=1.0,
        )
        thread = threading.Thread(target=httpd.serve_forever)
        thread.start()
        partial = socket.create_connection(("127.0.0.1", httpd.server_address[1]), timeout=5)
        partial.sendall(b"GET /types HTTP/1.1\r\nHost: 127.0.0.1\r\n")
        rejected = socket.create_connection(("127.0.0.1", httpd.server_address[1]), timeout=5)
        rejected.settimeout(1)
        try:
            rejected.sendall(
                b"GET /types HTTP/1.1\r\n"
                b"Host: 127.0.0.1\r\n"
                b"Authorization: Bearer secret-token\r\n"
                b"Connection: close\r\n"
                b"\r\n"
            )
            try:
                response = rejected.recv(256)
            except ConnectionResetError:
                response = b""
            self.assertEqual(response, b"")

            shutdown_thread = threading.Thread(target=httpd.shutdown)
            shutdown_thread.start()
            shutdown_thread.join(timeout=1)
            self.assertFalse(shutdown_thread.is_alive(), "shutdown blocked behind worker capacity")
        finally:
            partial.close()
            rejected.close()
            httpd.shutdown()
            httpd.server_close()
            thread.join(timeout=5)

    def test_ready_file_contains_only_selected_port(self):
        module = load_server_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            ready_file = Path(tmpdir) / "ready.json"
            module.write_ready_file(str(ready_file), 49152)

            self.assertEqual(json.loads(ready_file.read_text(encoding="utf-8")), {"port": 49152})

    def test_parser_defaults_to_loopback_host(self):
        module = load_server_module()

        args = module.parse_args(["--ready-file", "/tmp/ready.json"])

        self.assertEqual(args.host, "127.0.0.1")

    def test_cli_server_exits_when_launching_parent_disappears(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            ready_file = Path(tmpdir) / "ready.json"
            launcher = (
                "import os, subprocess, sys\n"
                "env = os.environ.copy()\n"
                "env['CLAUDEBOX_CLIPBOARD_TOKEN'] = 'orphan-token'\n"
                "proc = subprocess.Popen([\n"
                "    sys.executable, 'tooling/clipboard/macos_server.py',\n"
                "    '--ready-file', sys.argv[1],\n"
                "    '--host', '127.0.0.1',\n"
                "    '--port', '0',\n"
                "    '--pasteboard', 'claudebox-orphan-test',\n"
                "    '--watchdog-interval', '0.05',\n"
                "], cwd=sys.argv[2], env=env)\n"
                "print(proc.pid, flush=True)\n"
                "import pathlib, time\n"
                "ready = pathlib.Path(sys.argv[1])\n"
                "deadline = time.time() + 5\n"
                "while time.time() < deadline and not ready.exists() and proc.poll() is None:\n"
                "    time.sleep(0.05)\n"
                "if not ready.exists():\n"
                "    raise SystemExit('server did not become ready')\n"
            )
            parent = subprocess.run(
                [sys.executable, "-c", launcher, str(ready_file), str(SERVER_PATH.parents[2])],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5,
                check=True,
            )
            child_pid = int(parent.stdout.strip())

            deadline = time.time() + 5
            while time.time() < deadline and not ready_file.exists():
                time.sleep(0.05)
            self.assertTrue(ready_file.exists(), "clipboard server did not reach ready state")

            deadline = time.time() + 5
            while time.time() < deadline:
                try:
                    os.kill(child_pid, 0)
                except OSError:
                    break
                time.sleep(0.05)
            else:
                try:
                    os.kill(child_pid, 15)
                except OSError:
                    pass
                self.fail("orphaned clipboard server stayed alive")

    @unittest.skipUnless(sys.platform == "darwin", "macOS pasteboard smoke")
    @unittest.skipUnless(shutil.which("osascript") and shutil.which("sips"), "requires osascript and sips")
    def test_native_private_tiff_pasteboard_converts_to_png(self):
        module = load_server_module()
        pasteboard = None

        with tempfile.TemporaryDirectory() as tmpdir:
            png_path = Path(tmpdir) / "source.png"
            tiff_path = Path(tmpdir) / "source.tiff"
            png_path.write_bytes(tiny_valid_png())
            subprocess.run(
                ["sips", "-s", "format", "tiff", str(png_path), "--out", str(tiff_path)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            pasteboard = "claudebox-test-tiff-" + uuid.uuid4().hex
            try:
                put_tiff_on_private_pasteboard(pasteboard, tiff_path)

                converted = module.read_macos_png(pasteboard)
            finally:
                clear_private_pasteboard(pasteboard)

        self.assertTrue(converted.startswith(b"\x89PNG\r\n\x1a\n"))

    @unittest.skipUnless(sys.platform == "darwin", "macOS pasteboard smoke")
    @unittest.skipUnless(shutil.which("osascript") and shutil.which("sips"), "requires osascript and sips")
    def test_native_private_tiff_over_payload_limit_returns_no_image(self):
        module = load_server_module()
        pasteboard = None

        with tempfile.TemporaryDirectory() as tmpdir:
            png_path = Path(tmpdir) / "source.png"
            tiff_path = Path(tmpdir) / "source.tiff"
            png_path.write_bytes(tiny_valid_png())
            subprocess.run(
                ["sips", "-s", "format", "tiff", str(png_path), "--out", str(tiff_path)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            pasteboard = "claudebox-test-large-tiff-" + uuid.uuid4().hex
            try:
                put_tiff_on_private_pasteboard(pasteboard, tiff_path)

                converted = module.read_macos_png(pasteboard, max_payload_bytes=1)
            finally:
                clear_private_pasteboard(pasteboard)

        self.assertIsNone(converted)

    @unittest.skipUnless(sys.platform == "darwin", "macOS pasteboard smoke")
    @unittest.skipUnless(shutil.which("osascript"), "requires osascript")
    def test_native_missing_pasteboard_env_selects_general_without_accessing_contents(self):
        module = load_server_module()
        env = os.environ.copy()
        env.pop("CLAUDEBOX_CLIPBOARD_PASTEBOARD", None)
        for script in (module._read_macos_png_script(), module._write_macos_text_script()):
            # Execute the production selection prefix only. All clipboard content
            # access occurs after this boundary and must not run in this test.
            prefix, boundary, _ = script.partition(": $.NSPasteboard.generalPasteboard;")
            self.assertTrue(boundary)
            result = run_jxa(prefix + boundary + "\nObjC.unwrap(pasteboard.name);", env)
            self.assertEqual(result.stdout.decode().strip(), "Apple CFPasteboard general")


if __name__ == "__main__":
    unittest.main()
