"""Exercise native downloads, validation, cache repair, and offline reuse."""
import functools
import hashlib
import http.server
import json
from pathlib import Path
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
BUILD.mkdir(exist_ok=True)
binary = BUILD / "asset-store-tests"
subprocess.run([
    "xcrun", "swiftc", "-swift-version", "5",
    "-module-cache-path", str(BUILD / "module-cache"),
    "App/Catalog.swift", "App/AssetStore.swift", "Tests/AssetStoreTests.swift",
    "-o", str(binary),
], cwd=ROOT, check=True)

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

with tempfile.TemporaryDirectory(prefix="breakwater-assets-test-") as temporary:
    root = Path(temporary)
    objects = root / "server" / "objects"
    objects.mkdir(parents=True)
    data = b"fixture audio data; the store validates hashes independently of audio decoding"
    path = "objects/" + hashlib.sha256(data).hexdigest() + ".wav"
    (objects / Path(path).name).write_bytes(data)
    song = json.loads((ROOT / "Tests/Fixtures/catalog.json").read_text())[0]
    song["loops"] = song["loops"][:1]
    song["loops"][0]["sourceFile"] = song["loops"][0]["file"]
    song["loops"][0]["file"] = path
    if song["loops"][0].get("parts"):
        song["loops"][0]["parts"]["sourceFiles"] = song["loops"][0]["parts"]["files"]
        song["loops"][0]["parts"]["files"] = [path] * 4
    (root / "server/catalog.json").write_text(json.dumps([song]))

    handler = functools.partial(QuietHandler, directory=str(root / "server"))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_port}/"
    cache = str(root / "cache")
    try:
        subprocess.run([binary, "online", base, cache], check=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    subprocess.run([binary, "offline", base, cache], check=True)
