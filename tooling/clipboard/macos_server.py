#!/usr/bin/env python3
"""Authenticated macOS PNG clipboard bridge for ClaudeBox."""

import argparse
import base64
import hmac
import http.server
import json
import os
import subprocess
import sys
import tempfile
import traceback
import threading


DEFAULT_MAX_PAYLOAD_BYTES = 20 * 1024 * 1024
DEFAULT_MAX_TEXT_BYTES = 1024 * 1024
DEFAULT_SOCKET_TIMEOUT = 7.0
DEFAULT_MAX_WORKERS = 4


class ClipboardHTTPServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 8

    def process_request(self, request, client_address):
        if not self.worker_semaphore.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.worker_semaphore.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.worker_semaphore.release()

    def get_request(self):
        request, client_address = super().get_request()
        request.settimeout(self.socket_timeout)
        return request, client_address

    def handle_error(self, request, client_address):
        exc_type, exc, tb = sys.exc_info()
        if isinstance(exc, (BrokenPipeError, ConnectionResetError, TimeoutError)):
            return
        print("-" * 40, file=sys.stderr)
        print("Exception occurred during processing of request from", client_address, file=sys.stderr)
        traceback.print_exception(exc_type, exc, tb)
        print("-" * 40, file=sys.stderr)


class ClipboardRequestHandler(http.server.BaseHTTPRequestHandler):
    server_version = "ClaudeBoxClipboard/1"
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        return

    def do_GET(self):
        if not self._authorized():
            self._send_empty(401)
            return

        if self.path == "/types":
            self._handle_types()
        elif self.path == "/image":
            self._handle_image()
        else:
            self._send_empty(404)

    def do_POST(self):
        if not self._authorized():
            self._send_empty(401)
            return

        if self.path != "/text":
            self._send_empty(404)
            return

        self._handle_text()

    def _authorized(self):
        auth = self.headers.get("Authorization", "")
        expected = "Bearer " + self.server.clipboard_token
        try:
            auth_bytes = auth.encode("utf-8")
            expected_bytes = expected.encode("utf-8")
        except UnicodeError:
            return False
        return hmac.compare_digest(auth_bytes, expected_bytes)

    def _handle_types(self):
        image = self._read_image()
        types = ["image/png"] if image else []
        body = json.dumps({"types": types}, separators=(",", ":")).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle_image(self):
        image = self._read_image()
        if not image:
            self._send_empty(204)
            return
        if len(image) > self.server.max_payload_bytes:
            self._send_empty(413)
            return

        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(image)))
        self.end_headers()
        self.wfile.write(image)

    def _handle_text(self):
        content_type = self.headers.get("Content-Type", "")
        if not content_type.lower().startswith("text/plain"):
            self._send_empty(415)
            return

        content_length = self.headers.get("Content-Length")
        if content_length is None:
            self._send_empty(411)
            return

        try:
            length = int(content_length)
        except ValueError:
            self._send_empty(400)
            return

        if length < 0:
            self._send_empty(400)
            return
        if length > self.server.max_text_bytes:
            self._send_empty(413)
            return

        body = self.rfile.read(length)
        if len(body) != length:
            self._send_empty(400)
            return

        try:
            text = body.decode("utf-8")
        except UnicodeDecodeError:
            self._send_empty(400)
            return

        try:
            self.server.text_writer(text)
        except Exception:
            self._send_empty(500)
            return

        self._send_empty(204)

    def _read_image(self):
        acquired = self.server.clipboard_semaphore.acquire(blocking=False)
        if not acquired:
            return None
        try:
            data = self.server.image_provider()
        except Exception:
            return None
        finally:
            self.server.clipboard_semaphore.release()

        if not data or not data.startswith(b"\x89PNG\r\n\x1a\n"):
            return None
        return data

    def _send_empty(self, status):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()


def read_macos_png(pasteboard_name=None, max_payload_bytes=DEFAULT_MAX_PAYLOAD_BYTES):
    script = _read_macos_png_script()
    env = os.environ.copy()
    if pasteboard_name:
        env["CLAUDEBOX_CLIPBOARD_PASTEBOARD"] = pasteboard_name
    else:
        env.pop("CLAUDEBOX_CLIPBOARD_PASTEBOARD", None)
    env["CLAUDEBOX_CLIPBOARD_MAX_BYTES"] = str(int(max_payload_bytes))

    proc = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=5,
        env=env,
        check=False,
    )
    if proc.returncode != 0:
        return None

    encoded = proc.stdout.strip()
    if not encoded:
        return None
    try:
        decoded = base64.b64decode(encoded, validate=True)
    except Exception:
        return None
    if len(decoded) > max_payload_bytes:
        return None
    return decoded


def _read_macos_png_script():
    return """
ObjC.import('AppKit');
ObjC.import('Foundation');
ObjC.import('stdlib');

const env = $.NSProcessInfo.processInfo.environment;
const pbNameValue = env.objectForKey('CLAUDEBOX_CLIPBOARD_PASTEBOARD');
const pbName = pbNameValue && !pbNameValue.isNil() ? ObjC.unwrap(pbNameValue) : '';
const maxBytesValue = env.objectForKey('CLAUDEBOX_CLIPBOARD_MAX_BYTES');
const maxBytes = maxBytesValue && !maxBytesValue.isNil() ? Number(ObjC.unwrap(maxBytesValue)) : 20971520;
const pasteboard = pbName
  ? $.NSPasteboard.pasteboardWithName(pbName)
  : $.NSPasteboard.generalPasteboard;

function encodedPNG(data) {
  if (!data) {
    return "";
  }
  const nsData = typeof data.base64EncodedStringWithOptions === 'function'
    ? data
    : $.NSData.dataWithData(data);
  if (!nsData || Number(nsData.length) > maxBytes) {
    $.exit(3);
  }
  return ObjC.unwrap(nsData.base64EncodedStringWithOptions(0));
}

let result = "";
const pngData = pasteboard.dataForType($.NSPasteboardTypePNG);
result = encodedPNG(pngData);
if (!result) {
  const tiffData = pasteboard.dataForType($.NSPasteboardTypeTIFF);
  if (tiffData && Number(tiffData.length) > maxBytes) {
    $.exit(3);
  }
  const bitmap = tiffData ? $.NSBitmapImageRep.imageRepWithData(tiffData) : null;
  const converted = bitmap && typeof bitmap.representationUsingTypeProperties === 'function'
    ? bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $())
    : null;
  result = encodedPNG(converted);
}

if (result) {
  result;
} else {
  $.exit(2);
}
"""


def write_macos_text(text, pasteboard_name=None):
    script = _write_macos_text_script()
    env = os.environ.copy()
    if pasteboard_name:
        env["CLAUDEBOX_CLIPBOARD_PASTEBOARD"] = pasteboard_name
    else:
        env.pop("CLAUDEBOX_CLIPBOARD_PASTEBOARD", None)

    proc = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        input=text.encode("utf-8"),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
        env=env,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError("failed to write macOS clipboard text")


def _write_macos_text_script():
    return """
ObjC.import('AppKit');
ObjC.import('Foundation');

const env = $.NSProcessInfo.processInfo.environment;
const pbNameValue = env.objectForKey('CLAUDEBOX_CLIPBOARD_PASTEBOARD');
const pbName = pbNameValue && !pbNameValue.isNil() ? ObjC.unwrap(pbNameValue) : '';
const input = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
const value = $.NSString.alloc.initWithDataEncoding(input, $.NSUTF8StringEncoding);
const pasteboard = pbName
  ? $.NSPasteboard.pasteboardWithName(pbName)
  : $.NSPasteboard.generalPasteboard;

pasteboard.clearContents;
pasteboard.setStringForType(value, $.NSPasteboardTypeString);
"""


def create_server(
    host,
    port,
    token,
    image_provider,
    max_payload_bytes=DEFAULT_MAX_PAYLOAD_BYTES,
    text_writer=None,
    max_text_bytes=DEFAULT_MAX_TEXT_BYTES,
    max_workers=DEFAULT_MAX_WORKERS,
    socket_timeout=DEFAULT_SOCKET_TIMEOUT,
):
    if not token:
        raise ValueError("clipboard token is required")

    server = ClipboardHTTPServer((host, int(port)), ClipboardRequestHandler)
    server.clipboard_token = token
    server.image_provider = image_provider
    server.text_writer = text_writer or write_macos_text
    server.max_payload_bytes = int(max_payload_bytes)
    server.max_text_bytes = int(max_text_bytes)
    server.max_workers = int(max_workers)
    server.socket_timeout = float(socket_timeout)
    server.worker_semaphore = threading.BoundedSemaphore(value=server.max_workers)
    server.clipboard_semaphore = threading.BoundedSemaphore(value=2)
    return server


def write_ready_file(path, port):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".clipboard-ready.", dir=directory, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp:
            json.dump({"port": int(port)}, tmp, separators=(",", ":"))
            tmp.write("\n")
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def start_parent_watchdog(server, parent_pid, interval):
    if parent_pid <= 1:
        raise RuntimeError("refusing to run as an orphaned clipboard server")

    def watch():
        while True:
            server.shutdown_requested.wait(interval)
            if server.shutdown_requested.is_set():
                return
            if os.getppid() != parent_pid or os.getppid() <= 1:
                server.shutdown()
                return

    thread = threading.Thread(target=watch, daemon=True)
    thread.start()
    return thread


def parse_args(argv):
    parser = argparse.ArgumentParser(description="ClaudeBox macOS clipboard bridge")
    parser.add_argument("--ready-file", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--pasteboard", default=None)
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_PAYLOAD_BYTES)
    parser.add_argument("--max-text-bytes", type=int, default=DEFAULT_MAX_TEXT_BYTES)
    parser.add_argument("--max-workers", type=int, default=DEFAULT_MAX_WORKERS)
    parser.add_argument("--socket-timeout", type=float, default=DEFAULT_SOCKET_TIMEOUT)
    parser.add_argument("--watchdog-interval", type=float, default=1.0, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    parent_pid = os.getppid()
    if parent_pid <= 1:
        print("clipboard server refusing to run without a live parent", file=sys.stderr)
        return 1
    token = os.environ.get("CLAUDEBOX_CLIPBOARD_TOKEN", "")
    provider = lambda: read_macos_png(args.pasteboard, args.max_bytes)
    text_writer = lambda text: write_macos_text(text, args.pasteboard)
    server = create_server(
        args.host,
        args.port,
        token,
        provider,
        args.max_bytes,
        text_writer,
        args.max_text_bytes,
        args.max_workers,
        args.socket_timeout,
    )
    server.shutdown_requested = threading.Event()
    start_parent_watchdog(server, parent_pid, args.watchdog_interval)
    write_ready_file(args.ready_file, server.server_address[1])
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown_requested.set()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
