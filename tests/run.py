"""Run with python3 tests/run.py; requires nvim, tmux, git, and network access."""

import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    run(["nvim", "--version"])
    run(["tmux", "-V"])
    run(["bash", "-n", str(ROOT / "scripts/release.sh")])
    with tempfile.TemporaryDirectory(prefix="ark tests ") as temporary:
        directory = Path(temporary)
        for repo in ("nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim"):
            run(["git", "clone", "--quiet", "--depth", "1", "https://github.com/" + repo,
                 str(directory / repo.split("/")[1])])
        env = os.environ.copy()
        env.pop("TMUX", None)
        env.pop("TMUX_PANE", None)
        env.update(ARK_TEST_ROOT=str(ROOT), ARK_TEST_DIR=str(directory),
                   ARK_TEST_PYTHON=sys.executable, XDG_STATE_HOME=str(directory / "state"),
                   XDG_CONFIG_HOME=str(directory / "config"), XDG_DATA_HOME=str(directory / "data"),
                   XDG_CACHE_HOME=str(directory / "cache"), NVIM_APPNAME="ark-test")
        socket = "ark-test-" + str(os.getpid())

        def tmux(*args, **kwargs):
            return run(["tmux", "-L", socket, *args], env=env, **kwargs)

        (directory / "sample.txt").write_text("first line\nsecond line\n")
        try:
            command = shlex.join(["nvim", "-u", str(ROOT / "tests/init.lua"), "sample.txt"])
            tmux("-f", "/dev/null", "new-session", "-d", "-s", "test", "-x", "180", "-y", "45",
                 "-c", str(directory), command)
            # Queue the command; Neovim consumes it after startup.
            tmux("send-keys", "-t", "test:0.0", "-l",
                 ":lua dofile(vim.env.ARK_TEST_ROOT .. '/tests/integration.lua')")
            tmux("send-keys", "-t", "test:0.0", "Enter")
            deadline = time.monotonic() + 60
            while not (directory / "result").exists():
                if time.monotonic() > deadline:
                    raise AssertionError("integration tests timed out")
                time.sleep(0.1)
            result = (directory / "result").read_text().strip()
            assert result == "PASS", result
            # Read the saved selection in a separate Neovim process.
            check = directory / "persist.lua"
            check.write_text('vim.opt.rtp:prepend(vim.env.ARK_TEST_ROOT)\n'
                             'local s=require("ark.state").load()\n'
                             'assert(s.harness=="pi" and s.model=="example/reasoning" and s.effort=="high")\n')
            run(["nvim", "--headless", "-u", "NONE", "-l", str(check)], env=env, timeout=10)
            print("PASS: all adapters, transport, focus, pane reuse, Telescope, Pi efforts, reloads, persisted state")
        except Exception:
            tmux("capture-pane", "-p", "-t", "test:0.0")
            if (directory / "stdin.bin").exists():
                print("Received bytes:", repr((directory / "stdin.bin").read_bytes()))
            raise
        finally:
            tmux("kill-server")


if __name__ == "__main__":
    main()
