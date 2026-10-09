#!/usr/bin/env python3
"""Offline regressions for the Kienzlefon backend installer 2.6.

The suite renders the installer into a temporary tree and imports only those
rendered Python payloads.  It never contacts or mutates real services.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import tomllib
import unittest
from unittest.mock import patch
import wave


ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("KIENZLEFON_TEST_BASH") or shutil.which("bash") or "bash"
INSTALLER = ROOT / "installer/kienzlefon-installer-asterisk-backend-v2.6.sh"


def run(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(argument) for argument in arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=check,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )


def write_wav(path: Path, marker: int = 100) -> bytes:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(16_000)
        audio.writeframes(marker.to_bytes(2, "little", signed=True) * 320)
    return path.read_bytes()


def sourceable_installer(target: Path, install_root: Path | None = None) -> Path:
    source = INSTALLER.read_text(encoding="utf-8")
    trailer = '\nmain "$@"\n'
    if not source.endswith(trailer):
        raise AssertionError("unexpected installer trailer")
    source = source[: -len(trailer)] + "\n"
    if install_root is not None:
        source = source.replace(
            'readonly INSTALL_ROOT="/opt/kienzlefon-ai-asterisk-backend"',
            f'readonly INSTALL_ROOT="{install_root}"',
            1,
        )
    target.write_text(source, encoding="utf-8")
    return target


def import_payload(name: str, path: Path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    if spec is None:
        raise AssertionError("payload import spec unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    loader.exec_module(module)
    return module


class RenderedInstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="backend-v26-tests-")
        cls.root = Path(cls.temporary.name)
        cls.render = cls.root / "render"
        result = run(BASH, INSTALLER, "--render-only", cls.render)
        if result.returncode != 0:
            raise AssertionError(result.stderr)
        cls.config = cls.render / "etc/kienzlefon-ai-asterisk-backend/backend.toml"
        cls.apply_path = (
            cls.render
            / "opt/kienzlefon-ai-asterisk-backend/bin/kienzlefon_ai_tts_apply.py"
        )
        cls.switcher = import_payload("backend_v26_tts_apply", cls.apply_path)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_fresh_defaults_and_kokoro_round_trip(self) -> None:
        raw = tomllib.loads(self.config.read_text(encoding="utf-8"))
        self.assertEqual(raw["dialog"]["tts_backend"], "kokoro")
        self.assertEqual(raw["vad"]["speech_end_ms"], 1000)
        original = raw["kokoro"]
        source = sourceable_installer(self.root / "roundtrip-source.sh")
        rerender = self.root / "roundtrip-render"
        script = f'''
source "{source}"
load_existing_config "{self.config}"
render_tree "{rerender}"
'''
        result = run(BASH, "-c", script)
        self.assertEqual(result.returncode, 0, result.stderr)
        repeated = tomllib.loads(
            (rerender / "etc/kienzlefon-ai-asterisk-backend/backend.toml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(repeated["kokoro"], original)

    def test_existing_custom_wav_upgrade_stages_exact_bytes(self) -> None:
        custom = self.root / "administrator/custom-greeting.wav"
        expected = write_wav(custom, 321)
        config = self.root / "custom-wav.toml"
        body = self.config.read_text(encoding="utf-8")
        body = body.replace('greeting_mode = "tts"', 'greeting_mode = "wav"', 1)
        body = body.replace('greeting_wav = ""', f'greeting_wav = "{custom}"', 1)
        config.write_text(body, encoding="utf-8")
        source = sourceable_installer(self.root / "wav-upgrade-source.sh")
        stage = self.root / "wav-upgrade-stage"
        script = f'''
source "{source}"
load_existing_config "{config}"
validate_configuration
render_tree "{stage}"
'''
        result = run(BASH, "-c", script)
        self.assertEqual(result.returncode, 0, result.stderr)
        staged = stage / custom.relative_to("/")
        self.assertEqual(staged.read_bytes(), expected)
        rendered = tomllib.loads(
            (stage / "etc/kienzlefon-ai-asterisk-backend/backend.toml").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(rendered["dialog"]["greeting_wav"], str(custom))
        self.assertEqual(custom.read_bytes(), expected)

    def test_greeting_wav_cli_wins_over_existing_tts_mode(self) -> None:
        supplied = self.root / "supplied.wav"
        write_wav(supplied)
        source = sourceable_installer(self.root / "cli-wav-source.sh")
        script = f'''
source "{source}"
parse_args --greeting-wav "{supplied}"
load_existing_config "{self.config}"
[[ "$GREETING_MODE" == "wav" ]]
[[ "$GREETING_MODE_SET" == "y" ]]
[[ "$GREETING_WAV" == "$MANAGED_GREETING_WAV" ]]
'''
        result = run(BASH, "-c", script)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_repeated_identical_managed_wav_is_reused_without_publication(self) -> None:
        install_root = self.root / "managed-install"
        managed = install_root / "audio/begruessung_karl.wav"
        expected = write_wav(managed, 222)
        supplied = self.root / "same-managed.wav"
        supplied.write_bytes(expected)
        source = sourceable_installer(
            self.root / "managed-wav-source.sh", install_root=install_root
        )
        script = f'''
source "{source}"
parse_args --greeting-wav "{supplied}"
prepare_greeting_wav_import
[[ -z "$GREETING_WAV_SOURCE" ]]
[[ "$GREETING_MODE" == "wav" ]]
'''
        result = run(BASH, "-c", script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(managed.read_bytes(), expected)

    def make_operations(self, selection: str, states: dict[str, object]):
        switcher = self.switcher
        root = self.root / f"ops-{selection}-{len(list(self.root.glob('ops-*')))}"
        root.mkdir()
        desired = (
            f'[dialog]\ntts_backend="{selection}"\n'
            '[services]\n'
            'kokoro_url="http://127.0.0.1:8184/v1/tts/stream"\n'
            'qwen_url="http://127.0.0.1:8182/v1/tts/stream"\n'
            'piper_url="http://127.0.0.1:8181/v1/audio/speech"\n'
        ).encode()
        backend = root / "backend.toml"
        backend.write_bytes(desired)
        runtime = root / "kokoro.toml"
        runtime.write_text('[kokoro]\ndevice="cuda"\n', encoding="utf-8")
        events: list[tuple[str, ...]] = []

        def atomic_write(path, body, mode, _uid, _gid):
            Path(path).write_bytes(body)
            os.chmod(path, mode)

        module = SimpleNamespace(CONFIG=backend, atomic_write=atomic_write)
        ops = switcher.Operations.__new__(switcher.Operations)
        ops.m = module
        ops.desired = desired
        ops.cfg = switcher.Config()
        ops.rendered = b'[kokoro]\ndevice="cuda"\n'
        ops.selection = selection
        ops.runtime_config = runtime
        ops.update = None
        ops.stage = None
        ops.original_runtime = switcher.FileState.capture(runtime)
        ops.runtime_owned = None
        ops.runtime_changed = False
        ops.original_services = dict(states)
        ops.service_owned = dict(states)
        ops.services_changed = set()
        ops.wait_health = lambda *_args: None

        def command(*arguments: str) -> None:
            events.append(tuple(arguments))
            if arguments[0] != "systemctl":
                return
            service = arguments[-1]
            old = states[service]
            action = arguments[1]
            active = old.active
            enabled = old.enabled
            if action in {"start", "restart"}:
                active = "active"
            elif action == "stop":
                active = "inactive"
            elif action == "enable":
                enabled = "enabled-runtime" if "--runtime" in arguments else "enabled"
            elif action == "disable":
                enabled = "disabled"
            states[service] = switcher.UnitState(old.load, active, enabled)

        ops.command = command
        return ops, events, runtime, backend

    def test_kokoro_without_qwen_never_mutates_missing_alternative(self) -> None:
        s = self.switcher
        states = {
            s.KOKORO: s.UnitState("loaded", "inactive", "disabled"),
            s.QWEN: s.UnitState("not-found", "inactive", "not-found"),
        }
        ops, events, _runtime, _backend = self.make_operations("kokoro", states)
        with patch.object(s, "unit_state", side_effect=lambda unit: states[unit]), patch.object(
            s.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=os.getgid())
        ):
            ops.prepare_engine()
            ops.set_boot_policy()
        self.assertTrue(any(event[-1] == s.KOKORO for event in events))
        self.assertFalse(any(event[-1] == s.QWEN for event in events))

    def test_piper_without_generative_units_mutates_no_service(self) -> None:
        s = self.switcher
        states = {
            s.KOKORO: s.UnitState("not-found", "inactive", "not-found"),
            s.QWEN: s.UnitState("not-found", "inactive", "not-found"),
        }
        ops, events, _runtime, _backend = self.make_operations("piper", states)
        with patch.object(s, "unit_state", side_effect=lambda unit: states[unit]):
            ops.prepare_engine()
            ops.set_boot_policy()
        self.assertEqual(events, [])

    def test_masked_alternative_is_not_touched_or_unmasked(self) -> None:
        s = self.switcher
        states = {
            s.KOKORO: s.UnitState("loaded", "inactive", "disabled"),
            s.QWEN: s.UnitState("masked", "inactive", "masked"),
        }
        ops, events, _runtime, _backend = self.make_operations("kokoro", states)
        with patch.object(s, "unit_state", side_effect=lambda unit: states[unit]), patch.object(
            s.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=os.getgid())
        ):
            ops.prepare_engine()
            ops.set_boot_policy()
        self.assertFalse(any(event[-1] == s.QWEN for event in events))
        self.assertEqual(states[s.QWEN].load, "masked")

    def test_selected_missing_unit_is_rejected_before_mutation(self) -> None:
        s = self.switcher
        missing = s.UnitState("not-found", "inactive", "not-found")
        with patch.object(s, "unit_state", return_value=missing):
            with self.assertRaisesRegex(s.ServiceError, "local_qwen_service_missing"):
                s.ensure_local_installation("qwen")

    def test_selected_masked_unit_is_rejected_without_unmasking(self) -> None:
        s = self.switcher
        masked = s.UnitState("masked", "inactive", "masked")
        with patch.object(s, "unit_state", return_value=masked):
            with self.assertRaisesRegex(s.ServiceError, "local_qwen_service_masked"):
                s.ensure_local_installation("qwen")

    def test_concurrent_runtime_edit_blocks_rollback_and_service_changes(self) -> None:
        s = self.switcher
        states = {
            s.KOKORO: s.UnitState("loaded", "active", "enabled"),
            s.QWEN: s.UnitState("loaded", "inactive", "disabled"),
        }
        ops, events, runtime, _backend = self.make_operations("kokoro", states)
        owned = s.FileState.capture(runtime)
        ops.runtime_changed = True
        ops.runtime_owned = owned
        ops.services_changed = {s.KOKORO}
        ops.update = SimpleNamespace(rollback=lambda: events.append(("asset-rollback",)))
        snapshot = {
            "previous": b'[dialog]\ntts_backend="qwen"\n',
            "runtime": owned,
            "services": dict(states),
        }
        foreign = b"# concurrent administrator edit\n"
        runtime.write_bytes(foreign)
        with patch.object(s, "unit_state", side_effect=lambda unit: states[unit]):
            with self.assertRaisesRegex(
                s.ServiceError, "rollback_ownership_conflict_manual_review"
            ):
                ops.restore(snapshot)
        self.assertEqual(runtime.read_bytes(), foreign)
        self.assertEqual(events, [])

    def test_service_conflict_blocks_rollback_before_any_mutation(self) -> None:
        s = self.switcher
        expected = s.UnitState("loaded", "active", "enabled")
        states = {
            s.KOKORO: s.UnitState("loaded", "inactive", "enabled"),
            s.QWEN: s.UnitState("not-found", "inactive", "not-found"),
        }
        ops, events, _runtime, _backend = self.make_operations("kokoro", states)
        ops.service_owned = {s.KOKORO: expected, s.QWEN: states[s.QWEN]}
        ops.services_changed = {s.KOKORO}
        ops.update = SimpleNamespace(rollback=lambda: events.append(("asset-rollback",)))
        snapshot = {
            "previous": b'[dialog]\ntts_backend="qwen"\n',
            "runtime": ops.original_runtime,
            "services": {s.KOKORO: expected, s.QWEN: states[s.QWEN]},
        }
        with patch.object(s, "unit_state", side_effect=lambda unit: states[unit]):
            with self.assertRaisesRegex(
                s.ServiceError, "rollback_ownership_conflict_manual_review"
            ):
                ops.restore(snapshot)
        self.assertEqual(events, [])

    def test_rollback_restores_enabled_runtime_exactly(self) -> None:
        s = self.switcher
        states = {
            s.KOKORO: s.UnitState("loaded", "active", "enabled"),
            s.QWEN: s.UnitState("not-found", "inactive", "not-found"),
        }
        ops, events, _runtime, _backend = self.make_operations("kokoro", states)
        current = states[s.KOKORO]
        previous = s.UnitState("loaded", "active", "enabled-runtime")
        ops.service_owned = {s.KOKORO: current, s.QWEN: states[s.QWEN]}
        ops.services_changed = {s.KOKORO}
        ops.update = SimpleNamespace(rollback=lambda: None)
        snapshot = {
            "previous": b'[dialog]\ntts_backend="qwen"\n',
            "runtime": ops.original_runtime,
            "services": {s.KOKORO: previous, s.QWEN: states[s.QWEN]},
        }
        with patch.object(s, "unit_state", side_effect=lambda unit: states[unit]):
            ops.restore(snapshot)
        self.assertEqual(states[s.KOKORO], previous)
        self.assertIn(("systemctl", "enable", "--runtime", s.KOKORO), events)

    def test_rollback_restarts_kokoro_with_previous_device_configuration(self) -> None:
        s = self.switcher
        states = {s.KOKORO: s.UnitState("loaded", "active", "enabled"),
                  s.QWEN: s.UnitState("not-found", "inactive", "not-found")}
        ops, events, runtime, _backend = self.make_operations("kokoro", states)
        runtime.write_bytes(b'[kokoro]\ndevice="cpu"\n')
        previous = s.FileState.capture(runtime)
        runtime.write_bytes(ops.rendered)
        ops.runtime_changed = True
        ops.runtime_owned = s.FileState.capture(runtime)
        ops.services_changed = {s.KOKORO}
        health = []
        ops.wait_health = lambda *_: health.append(ops.cfg.device)
        snapshot = {"previous": b'[dialog]\ntts_backend="kokoro"\n',
                    "runtime": previous, "services": dict(states)}
        with patch.object(s, "unit_state", side_effect=lambda unit: states[unit]):
            ops.restore(snapshot)
        self.assertIn(("systemctl", "restart", s.KOKORO), events)
        self.assertEqual(health, ["cpu"])

    def test_failed_rollback_keeps_clients_stopped(self) -> None:
        s = self.switcher
        events = []
        class Failing:
            def __getattr__(self, name):
                def call(*_):
                    events.append(name)
                    if name in {"prepare_engine", "restore"}:
                        raise s.ServiceError("manual_review")
                return call
        with self.assertRaisesRegex(s.ServiceError, "manual_review"):
            s.switch(Failing())
        self.assertIn("restore", events)
        self.assertNotIn("start_clients", events)

    def test_failed_write_does_not_claim_foreign_bytes_for_rollback(self) -> None:
        s = self.switcher
        states = {s.KOKORO: s.UnitState("loaded", "active", "enabled"),
                  s.QWEN: s.UnitState("not-found", "inactive", "not-found")}
        ops, events, runtime, _backend = self.make_operations("kokoro", states)
        def interrupted(path, *_):
            Path(path).write_bytes(b"# administrator change\n")
            raise OSError("interrupted")
        ops.m.atomic_write = interrupted
        with patch.object(s, "unit_state", side_effect=lambda unit: states[unit]), \
                patch.object(s.grp, "getgrnam", return_value=SimpleNamespace(gr_gid=os.getgid())):
            with self.assertRaisesRegex(s.ServiceError, "ownership_conflict"):
                ops.prepare_engine()
            with self.assertRaisesRegex(s.ServiceError, "ownership_conflict"):
                ops.restore({})
        self.assertEqual(runtime.read_bytes(), b"# administrator change\n")
        self.assertEqual(events, [])

    def test_wav_parent_traversal_is_rejected_before_staging(self) -> None:
        directory = self.root / "traversal"
        directory.mkdir()
        wav = self.root / "parent.wav"
        write_wav(wav)
        config = self.root / "traversal.toml"
        body = self.config.read_text().replace('greeting_mode = "tts"', 'greeting_mode = "wav"', 1)
        body = body.replace('greeting_wav = ""', f'greeting_wav = "{directory}/../parent.wav"', 1)
        config.write_text(body)
        source = sourceable_installer(self.root / "traversal-source.sh")
        result = run(BASH, "-c", f'source "{source}"\nload_existing_config "{config}"\nvalidate_configuration', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Greeting WAV target", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
