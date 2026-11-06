"""Exercise the real broker with fake unprivileged upgrade commands; never call sudo."""
import os
import pathlib
import struct
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="orbit-update-test-") as folder:
    broker = pathlib.Path(folder) / "broker"
    fake = pathlib.Path(folder) / "brew"
    subprocess.run(["xcrun", "clang", "-Wall", "-Wextra", "-Werror", "-DORBIT_SESSION_TEST",
                    str(root / "Helpers/UpdateSession.c"), "-o", str(broker)], check=True)
    fake.write_text('#!/bin/sh\n/usr/bin/tty </dev/tty\nprintf "%s\\n" "$@"\n'
                    'for last do :; done\n[ "$last" != failure ] || exit 7\n')
    fake.chmod(0o700)

    def run(data):
        result = subprocess.run([str(broker), str(fake)], input=data, capture_output=True, timeout=10)
        frames = []
        offset = 0
        while offset < len(result.stdout):
            kind, value = struct.unpack_from("=Ii", result.stdout, offset)
            offset += 8
            payload = result.stdout[offset:offset+value] if kind == 1 else b""
            offset += len(payload)
            frames.append((kind, value, payload))
        return result.returncode, frames

    status, frames = run(b"c\tfirst-app\nf\tfailure\nf\tlast-app\n")
    assert status == 0 and frames[0][:2] == (0, 0)
    assert [value for kind, value, _ in frames if kind == 2] == [0, 7, 0]
    lines = b"".join(payload for _, _, payload in frames).decode().splitlines()
    terminals = [line for line in lines if line.startswith("/dev/tty")]
    assert len(terminals) == 3 and len(set(terminals)) == 1, lines
    assert lines[1:5] == ["upgrade", "--cask", "--greedy-auto-updates", "first-app"], lines
    assert "failure" in lines and "last-app" in lines
    status, frames = run(b"c\t--all\n")
    assert status == 125 and len(frames) == 1
    print("PASS: one controlling terminal across cask/formula updates, exit codes, literal arguments, invalid token rejection")
