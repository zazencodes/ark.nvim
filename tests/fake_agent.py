"""A terminal agent that records transport and exposes deterministic catalogs."""

import json
import os
from pathlib import Path
import sys
import tty

kind, *args = sys.argv[1:]
if args == ["debug", "models"]:
    print(json.dumps({"models": [
        {"slug": "example", "visibility": "list",
         "supported_reasoning_levels": [{"effort": "high"}]},
        {"slug": "hidden", "visibility": "hide", "supported_reasoning_levels": []},
    ]}))
    sys.exit(0)
if args == ["models"]:
    print("example-high\tExample (High)")
    sys.exit(0)
if args == ["--list-models"]:
    print("provider model context max reasoning")
    print("example plain 100 20 no")
    print("example reasoning 100 20 yes")
    sys.exit(0)

directory = Path(os.environ["ARK_TEST_DIR"])
# Raw input preserves tmux's bracketed-paste delimiters and submit key.
tty.setraw(sys.stdin.fileno())
sys.stdout.write("\033[?2004h")
sys.stdout.flush()
(directory / "argv.json").write_text(json.dumps(args))
(directory / "saved.txt").write_bytes(Path("sample.txt").read_bytes())
(directory / "ready").write_text(kind)
received = b""
edited = False
while True:
    chunk = os.read(sys.stdin.fileno(), 65536)
    if not chunk:
        break
    received += chunk
    (directory / "stdin.bin").write_bytes(received)
    if not edited and b"ARK_TEST_EDIT_FILE" in received and received.endswith(b"\033[201~\r"):
        Path("sample.tmp").write_text("agent edit\nsecond line\n")
        Path("sample.tmp").replace("sample.txt")
        edited = True
