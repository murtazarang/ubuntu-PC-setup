import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from local_ai import engine


def gguf(path, tensors):
    def string(value):
        return struct.pack("<Q", len(value)) + value.encode()

    header = b"GGUF" + struct.pack("<IQQ", 3, len(tensors), 1)
    header += string("tokenizer.ggml.tokens") + struct.pack("<IIQ", 9, 8, 2) + string("a") + string("bc")
    total = 0
    for name, size in tensors:
        header += string(name) + struct.pack("<IQIQ", 1, size, 0, total)
        total += size
    padded = header + b"\0" * (-len(header) % 32)
    path.write_bytes(padded + b"\0" * total)


class EngineTests(unittest.TestCase):
    def test_fixed_launch_command(self):
        for hardware, profile in engine.PROFILES.items():
            with self.subTest(hardware=hardware):
                devices = ["CUDA0", "CUDA1"][:profile.gpu_count] if profile.backend == "cuda" else ["Vulkan1"]
                cmd = engine.command(Path("llama-server"), profile, Path("A path/model.gguf"), devices)
                self.assertEqual(cmd[cmd.index("--ctx-size") + 1], str(profile.context))
                self.assertEqual(cmd[cmd.index("--host") + 1], "127.0.0.1")
                self.assertEqual(cmd[cmd.index("--port") + 1], "8081")
                self.assertEqual(cmd[cmd.index("--alias") + 1], profile.alias)
                self.assertEqual(cmd[cmd.index("--load-mode") + 1], "none")
                self.assertEqual(cmd[cmd.index("--lazy-mode") + 1], "off")
                self.assertNotIn("--models-dir", cmd)
                self.assertNotIn("--spec-type", cmd)
                if hardware == "NvidiaDual":
                    self.assertEqual(cmd[cmd.index("--split-mode") + 1], "layer")
                    self.assertIn(r"^per_layer_token_embd\.weight$=CPU", cmd)
                    self.assertIn("--n-cpu-moe", cmd)
                    self.assertNotIn("--cpu-moe", cmd)
                else:
                    self.assertIn("--cpu-moe", cmd)
                    self.assertNotIn("--override-tensor", cmd)

    def test_tensor_span_and_detect_reserved_ram(self):
        profile = engine.PROFILES["NvidiaDual"]
        with tempfile.TemporaryDirectory() as dirname:
            base = Path(dirname)
            first, second = (base / Path(item[0]).name for item in profile.files)
            gguf(first, [("blk.0.ffn_gate_up_exps.weight", 128),
                         ("blk.40.ffn_down_exps.weight", 256),
                         ("blk.0.ffn_up.weight", 512)])
            gguf(second, [("per_layer_token_embd.weight", 1024)])
            self.assertEqual(engine.gguf_tensors(first)["blk.40.ffn_down_exps.weight"], 256)
            target = engine.HOST_RUNTIME_ALLOWANCE_GIB * engine.GIB + 1152
            with patch.object(engine.os, "name", "nt"):
                with patch.object(engine, "memory_bytes", return_value=(target + 12*engine.GIB, target)):
                    # Avoid patching os.name during pathlib construction on POSIX.
                    with patch.object(engine, "Path", wraps=type(first)):
                        engine.expect_ram(profile, first)
                with patch.object(engine, "memory_bytes", return_value=(target + 12*engine.GIB - 1, target)):
                    with patch.object(engine, "Path", wraps=type(first)), self.assertRaisesRegex(RuntimeError, "12 GiB"):
                        engine.expect_ram(profile, first)

    def test_foreign_pid_not_reported(self):
        with tempfile.TemporaryDirectory() as dirname:
            root = Path(dirname)
            state = root / "engine"
            state.mkdir()
            (state / "process.json").write_text(json.dumps({
                "pid": 1000, "binary": "/owned/llama-server", "born": "100"}))
            with patch.object(engine, "process_identity", return_value=("/other/llama-server", "100")):
                self.assertEqual(engine.status(root)["status"], "stopped")
                self.assertFalse(engine.stop(root))
            with patch.object(engine, "process_identity", return_value=("/owned/llama-server", "101")):
                self.assertFalse(engine.stop(root))

    def test_unverified_existing_file_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as dirname:
            path = Path(dirname) / "model.gguf"
            path.write_bytes(b"user file")
            with patch.object(engine.subprocess, "run") as run:
                with self.assertRaisesRegex(RuntimeError, "left intact"):
                    engine.checked_download("https://example.org/file", path, "0" * 64, 9)
                run.assert_not_called()
            self.assertEqual(path.read_bytes(), b"user file")

    def test_unsafe_archive_is_not_unpacked(self):
        with tempfile.TemporaryDirectory() as dirname:
            base = Path(dirname)
            file = base / "archive.zip"
            with zipfile.ZipFile(file, "w") as archive:
                archive.writestr("../outside.txt", "not safe")
            with self.assertRaisesRegex(RuntimeError, "Unsafe entry"):
                engine.unpack(file, base / "dest")
            self.assertFalse((base / "outside.txt").exists())


if __name__ == "__main__":
    unittest.main()
