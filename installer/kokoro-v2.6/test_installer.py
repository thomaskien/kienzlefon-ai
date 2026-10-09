#!/usr/bin/env python3
"""Offline tests: no packages, models, services or external sockets."""
import dataclasses
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import install_kokoro as installer
import kokoro_service as service


class ConfigurationTests(unittest.TestCase):
    def test_fresh_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg = installer.desired_config(Path(directory) / 'missing')
            self.assertEqual((cfg.device, cfg.port, cfg.voice), ('cuda', 8184, 'thorsten'))

    def test_upgrade_and_second_pass_preserve_custom_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.toml'
            expected = service.Config(Path('/custom/models'), device='cpu', port=18184,
                                      threads=2, max_concurrent=4, speed=1.2)
            path.write_text(installer.config_text(expected))
            for _ in range(2):
                cfg = installer.desired_config(path)
                self.assertEqual(cfg, expected)
                path.write_text(installer.config_text(cfg))

    def test_explicit_override_only_changes_requested_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.toml'
            old = service.Config(Path('/custom/models'), device='cpu', threads=2, speed=1.2)
            path.write_text(installer.config_text(old))
            self.assertEqual(installer.desired_config(path, 'cuda', 28184),
                             dataclasses.replace(old, device='cuda', port=28184))

    def test_invalid_types_and_limits(self):
        for values in ({'port': True}, {'port': 8184.5}, {'port': 1}, {'device': 'auto'},
                       {'threads': 0}, {'voice': 'other'}, {'model_revision': 'main'},
                       {'device': 'cpu', 'threads': 4, 'max_concurrent': 4}):
            with self.subTest(values=values), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'config.toml'
                path.write_text(installer.config_text(dataclasses.replace(service.Config(Path('/models')), **values)))
                with self.assertRaises(service.ServiceError):
                    installer.desired_config(path)

    def test_config_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config.toml'
            path.symlink_to(Path(directory) / 'other')
            with self.assertRaises(service.ServiceError):
                installer.desired_config(path)

    def test_unit_has_no_phone_or_fallback_service_actions(self):
        text = installer.unit_text()
        self.assertIn('kokoro-venv-v2.6/bin/python', text)
        self.assertIn('User=kienzlefon-kokoro', text)
        for forbidden in ('qwen', 'piper', 'asterisk', 'backend.toml'):
            self.assertNotIn(forbidden, text)

    def test_cpu_unit_does_not_require_gpu_groups(self):
        with patch.object(installer.grp, 'getgrnam', side_effect=AssertionError('GPU group queried')):
            self.assertNotIn('SupplementaryGroups', installer.unit_text('cpu'))

    def test_cuda_unit_only_uses_existing_groups(self):
        with patch.object(installer.grp, 'getgrnam', side_effect=KeyError('missing')):
            self.assertNotIn('SupplementaryGroups', installer.unit_text('cuda'))

    def test_device_dependency_profiles(self):
        cpu, cpu_index = installer.dependency_profile('cpu')
        cuda, cuda_index = installer.dependency_profile('cuda')
        self.assertTrue(cpu_index.endswith('/cpu'))
        self.assertTrue(cuda_index.endswith('/cu128'))
        self.assertIn('torch==2.8.0+cpu', cpu.read_text())
        self.assertIn('torch==2.8.0+cu128', cuda.read_text())
        self.assertFalse(any(line.startswith(('nvidia-', 'triton==')) for line in cpu.read_text().splitlines()))


class GPUTests(unittest.TestCase):
    def torch(self, count=1):
        return SimpleNamespace(cuda=SimpleNamespace(device_count=lambda: count))

    def nvml(self, count=2):
        return SimpleNamespace(nvmlDeviceGetHandleByUUID=lambda value: ('uuid', value),
                               nvmlDeviceGetHandleByIndex=lambda value: ('index', value),
                               nvmlDeviceGetCount=lambda: count)

    def test_uuid_maps_physical_second_gpu(self):
        with patch.dict(os.environ, CUDA_VISIBLE_DEVICES='GPU-second'):
            self.assertEqual(service.selected_gpu_handle(self.torch(), self.nvml()), ('uuid', 'GPU-second'))

    def test_legacy_single_gpu_without_environment(self):
        with patch.dict(os.environ, CUDA_VISIBLE_DEVICES=''):
            self.assertEqual(service.selected_gpu_handle(self.torch(), self.nvml(1)), ('index', 0))

    def test_ambiguous_devices_fail(self):
        for visible, count in (('', 2), ('1', 2), ('0,1', 2), ('GPU-one', 2)):
            with self.subTest(visible=visible), patch.dict(os.environ, CUDA_VISIBLE_DEVICES=visible):
                with self.assertRaises(service.ServiceError):
                    service.selected_gpu_handle(self.torch(count if visible == 'GPU-one' else 1), self.nvml(count))


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.source = self.root / 'source'; self.source.mkdir()
        (self.source / 'kokoro_service.py').write_bytes(b'new service')
        self.state = self.root / 'state'; self.state.mkdir()
        self.paths = [self.root / name for name in ('service.py', 'config.toml', 'kokoro.service', 'gpu.conf')]
        self.events = []
        self.cfg = service.Config(Path('/models'))
        overrides = dict(zip(('PROGRAM', 'CONFIG', 'UNIT_PATH', 'DROPIN'), self.paths))
        overrides.update(SOURCE=self.source, STATE=self.state)
        self.enter(patch.multiple(installer, **overrides))
        self.enter(patch.object(installer.grp, 'getgrnam', return_value=SimpleNamespace(gr_gid=os.getgid())))
        self.enter(patch.object(installer.os, 'fchown', return_value=None))
        self.enter(patch.object(installer, 'unit_state', return_value=('active', 'enabled')))
        self.enter(patch.object(installer, 'run', side_effect=lambda args: self.events.append([str(x) for x in args])))
        self.enter(patch.object(installer.subprocess, 'run', return_value=SimpleNamespace(returncode=0)))
        self.enter(patch.object(installer, 'wait_health', return_value=None))

    def enter(self, context):
        value = context.__enter__(); self.addCleanup(context.__exit__, None, None, None)
        return value

    def old_files(self):
        for index, path in enumerate(self.paths):
            path.write_bytes(f'old-{index}'.encode()); path.chmod(0o640)
        return {path: installer.snapshot(path) for path in self.paths}

    def test_install_and_repeated_publish(self):
        for _ in range(2):
            installer.publish(self.cfg, 'GPU-second')
            self.assertEqual(self.paths[0].read_bytes(), b'new service')
            self.assertIn('GPU-second', self.paths[3].read_text())
        self.assertEqual([e for e in self.events if e[:2] == ['systemctl', 'restart']],
                         [['systemctl', 'restart', installer.UNIT]] * 2)

    def test_cpu_has_empty_gpu_environment(self):
        installer.publish(dataclasses.replace(self.cfg, device='cpu'), '', no_start=True)
        self.assertTrue(self.paths[3].read_text().endswith('CUDA_VISIBLE_DEVICES=\n'))
        self.assertNotIn(['systemctl', 'restart', installer.UNIT], self.events)

    def test_failed_health_restores_contents_modes_and_service(self):
        before = self.old_files()
        with patch.object(installer, 'wait_health', side_effect=service.ServiceError('injected')):
            with self.assertRaises(service.ServiceError): installer.publish(self.cfg, 'GPU-second')
        self.assertEqual({p: installer.snapshot(p) for p in self.paths}, before)
        self.assertIn(['systemctl', 'start', installer.UNIT], self.events)

    def test_failed_fresh_install_removes_only_published_files(self):
        with patch.object(installer, 'unit_state', return_value=('inactive', 'not-found')):
            with patch.object(installer, 'wait_health', side_effect=service.ServiceError('injected')):
                with self.assertRaises(service.ServiceError): installer.publish(self.cfg, 'GPU-second')
        self.assertTrue(all(not p.exists() for p in self.paths))

    def test_failed_second_write_restores_first(self):
        before = self.old_files(); original = installer.atomic_write
        def fail(path, *args, **kwargs):
            if path == self.paths[1]: raise OSError('injected')
            return original(path, *args, **kwargs)
        with patch.object(installer, 'atomic_write', side_effect=fail):
            with self.assertRaises(OSError): installer.publish(self.cfg, 'GPU-second')
        self.assertEqual({p: installer.snapshot(p) for p in self.paths}, before)

    def test_concurrent_change_not_overwritten_on_rollback(self):
        self.old_files()
        def fail(*args):
            self.paths[1].write_bytes(b'newer-admin-change')
            raise service.ServiceError('injected')
        with patch.object(installer, 'wait_health', side_effect=fail):
            with self.assertRaisesRegex(service.ServiceError, 'concurrent_edit'):
                installer.publish(self.cfg, 'GPU-second')
        self.assertEqual(self.paths[1].read_bytes(), b'newer-admin-change')
        self.assertNotIn(['systemctl', 'start', installer.UNIT], self.events)

    def test_concurrent_service_state_prevents_rollback_mutations(self):
        self.old_files()
        state = ['active', 'enabled']
        def fail(*args):
            state[:] = ['inactive', 'disabled']
            self.events.clear()
            raise service.ServiceError('injected')
        with patch.object(installer, 'unit_state', side_effect=lambda: tuple(state)), \
                patch.object(installer, 'wait_health', side_effect=fail):
            with self.assertRaisesRegex(service.ServiceError, 'manual_check_required'):
                installer.publish(self.cfg, 'GPU-second')
        self.assertEqual(self.events, [])
        self.assertEqual(self.paths[0].read_bytes(), b'new service')

    def test_gpu_missing_fails_before_any_changes(self):
        with self.assertRaises(service.ServiceError): installer.publish(self.cfg, '')
        self.assertFalse(self.events)
        self.assertTrue(all(not p.exists() for p in self.paths))

    def test_masked_unit_not_unmasked(self):
        with patch.object(installer, 'unit_state', return_value=('inactive', 'masked')):
            with self.assertRaises(service.ServiceError): installer.publish(self.cfg, 'GPU-second')
        self.assertFalse(self.events)


if __name__ == '__main__':
    unittest.main(verbosity=2)
