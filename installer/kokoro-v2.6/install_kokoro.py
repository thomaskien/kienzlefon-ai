#!/usr/bin/env python3
"""Kokoro model/service installation only. No telephone configuration or logic.

The 2.6 environment is separate from the transferred 1.0.x environment.
Configuration, executable source and unit publication are rolled back on error.
Model/dependency preparation happens before stopping the existing service.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import asdict
import fcntl
import grp
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

from kokoro_service import Config, ServiceError

VERSION = "2.6"
UNIT = "kienzlefon-kokoro-tts.service"
SOURCE = Path(__file__).resolve().parent
CONFIG = Path("/etc/kienzlefon-ai/kokoro.toml")
PROGRAM = Path("/opt/kienzlefon-ai/kokoro/kokoro_service.py")
VENV = Path("/opt/kienzlefon-ai/python/kokoro-venv-v2.6")
UNIT_PATH = Path("/etc/systemd/system") / UNIT
DROPIN = UNIT_PATH.with_name(UNIT + ".d") / "10-kienzlefon-gpu.conf"
STATE = Path("/var/lib/kienzlefon-ai/kokoro")


def run(args):
    subprocess.run([str(x) for x in args], check=True)


def unit_state():
    def value(command):
        return subprocess.run(["systemctl", command, UNIT], capture_output=True,
                              text=True, check=False).stdout.strip()
    return value("is-active"), value("is-enabled")


def config_text(cfg):
    values = asdict(cfg)
    values["model_dir"] = str(cfg.model_dir)
    return "[kokoro]\n" + "".join(f"{k} = {json.dumps(v)}\n" for k, v in values.items())


def desired_config(path, device=None, port=None):
    if path.is_symlink():
        raise ServiceError("unsafe_config_symlink")
    cfg = Config.load(path) if path.exists() else Config(Path("/opt/kienzlefon-ai/models/kokoro-thorsten"))
    values = asdict(cfg)
    if device is not None:
        values["device"] = device
    if port is not None:
        values["port"] = port
    # Use the identical parser as the actual service, including strict types.
    with tempfile.TemporaryDirectory(prefix="kokoro-validate-") as directory:
        candidate = Path(directory) / "config.toml"
        candidate.write_text(config_text(Config(**values)))
        return Config.load(candidate)


def unit_text(device="cuda"):
    groups = []
    if device == "cuda":
        for name in ("video", "render"):
            try:
                grp.getgrnam(name)
            except KeyError:
                continue
            groups.append(name)
    supplementary = "SupplementaryGroups=" + " ".join(groups) + "\n" if groups else ""
    return f"""[Unit]
Description=Kienzlefon resident Kokoro-Thorsten TTS
After=network.target
ConditionPathExists={CONFIG}

[Service]
Type=simple
User=kienzlefon-kokoro
Group=kienzlefon-kokoro
{supplementary}WorkingDirectory={PROGRAM.parent}
ExecStart={VENV}/bin/python {PROGRAM} --config {CONFIG}
Environment=PYTHONUNBUFFERED=1
Environment=HF_HUB_OFFLINE=1
Environment=TOKENIZERS_PARALLELISM=false
Environment=PYTHONDONTWRITEBYTECODE=1
Environment=PYTORCH_KERNEL_CACHE_PATH=/tmp/kienzlefon-kokoro-kernels
Restart=on-failure
RestartSec=3
TimeoutStopSec=30
KillMode=control-group
UMask=0077
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=
TasksMax=128
MemoryMax=8G
LimitNOFILE=1024

[Install]
WantedBy=multi-user.target
"""


def snapshot(path):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ServiceError("unsafe_managed_file")
    if not path.exists():
        return None
    info = path.stat()
    return (path.read_bytes(), info.st_mode & 0o777, info.st_uid, info.st_gid)


def atomic_write(path, body, mode=0o644, uid=0, gid=0):
    snapshot(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
    if path.parent.resolve() != path.parent:
        raise ServiceError("unsafe_managed_directory")
    fd, name = tempfile.mkstemp(prefix=".kokoro-", dir=path.parent)
    stage = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(body)
            stream.flush()
            os.fchmod(stream.fileno(), mode)
            os.fchown(stream.fileno(), uid, gid)
            os.fsync(stream.fileno())
        os.replace(stage, path)
    finally:
        stage.unlink(missing_ok=True)


def wait_health(cfg, seconds=180):
    host = "[::1]" if cfg.host == "::1" else cfg.host
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"http://{host}:{cfg.port}/health", timeout=2) as response:
                data = json.load(response)
            if (data.get("status") == "ok" and data.get("engine") == "kokoro"
                    and data.get("device") == cfg.device and data.get("model_loaded") is True
                    and data.get("model_instances") == 1 and data.get("model_revision") == cfg.model_revision):
                return
        except (OSError, ValueError):
            pass
        time.sleep(0.25)
    raise ServiceError("kokoro_warmup_health_timeout")


def prepare_model(cfg):
    cfg.model_dir.mkdir(parents=True, exist_ok=True, mode=0o755)
    if cfg.model_dir.resolve() != cfg.model_dir:
        raise ServiceError("unsafe_model_directory")
    manifest = json.loads((SOURCE / "model_manifest.json").read_text())
    valid = True
    for name in ("config.json", "model.pth", "voices/thorsten.pt"):
        path = cfg.model_dir / name
        if path.is_symlink():
            raise ServiceError("unsafe_model_symlink")
        if not path.exists():
            valid = False
        elif hashlib.sha256(path.read_bytes()).hexdigest() != manifest["files"][name]["sha256"]:
            raise ServiceError("existing_model_checksum_mismatch")
    if not valid:
        run([VENV / "bin/python", SOURCE / "download_models.py", "--output", cfg.model_dir])


def prepare(cfg):
    needed = []
    for package in ("python3-venv", "python3-pip", "git", "espeak-ng", "libgomp1"):
        result = subprocess.run(["dpkg-query", "-W", "-f=${Status}", package],
                                capture_output=True, text=True)
        if result.returncode or "install ok installed" not in result.stdout:
            needed.append(package)
    if needed:
        run(["apt-get", "update"])
        run(["apt-get", "install", "-y", *needed])
    try:
        pwd.getpwnam("kienzlefon-kokoro")
    except KeyError:
        run(["useradd", "--system", "--user-group", "--no-create-home", "--home-dir",
             "/nonexistent", "--shell", "/usr/sbin/nologin", "kienzlefon-kokoro"])
    # Versioned environment prevents a failed preparation from damaging the
    # environment used by a previous production service.
    if VENV.is_symlink():
        raise ServiceError("unsafe_venv_symlink")
    if not (VENV / "bin/python").exists():
        VENV.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
        run([sys.executable, "-m", "venv", VENV])
    requirements, index = dependency_profile(cfg.device)
    digest = hashlib.sha256(requirements.read_bytes()).hexdigest()
    marker = VENV / ".kienzlefon-requirements-sha256"
    if not marker.exists() or marker.read_text().strip() != digest:
        if marker.exists():
            raise ServiceError("versioned_environment_manifest_mismatch")
        run([VENV / "bin/python", "-m", "pip", "install", "-r", requirements,
             "--extra-index-url", index])
        run([VENV / "bin/python", "-m", "pip", "check"])
        marker.write_text(digest + "\n")
    else:
        run([VENV / "bin/python", "-m", "pip", "check"])
    # Source and dependencies contain no secrets; the unprivileged user must
    # be able to traverse the environment even under a restrictive root umask.
    for path in [VENV, *VENV.rglob("*")]:
        if path.is_symlink():
            continue
        mode = path.stat().st_mode
        path.chmod(0o755 if path.is_dir() or mode & 0o111 else 0o644)
    prepare_model(cfg)


def dependency_profile(device):
    suffix = "-cpu" if device == "cpu" else ""
    index = "cpu" if device == "cpu" else "cu128"
    return SOURCE / f"requirements{suffix}.lock.txt", f"https://download.pytorch.org/whl/{index}"


def publish(cfg, uuid, no_start=False):
    if cfg.device == "cuda" and not re.fullmatch(r"GPU-[A-Za-z0-9-]+", uuid or ""):
        raise ServiceError("stable_cuda_gpu_uuid_required")
    gid = grp.getgrnam("kienzlefon-kokoro").gr_gid
    writes = {
        PROGRAM: ((SOURCE / "kokoro_service.py").read_bytes(), 0o755, 0),
        CONFIG: (config_text(cfg).encode(), 0o640, gid),
        UNIT_PATH: (unit_text(cfg.device).encode(), 0o644, 0),
        DROPIN: (("[Service]\nEnvironment=CUDA_VISIBLE_DEVICES=" + (uuid if cfg.device == "cuda" else "") + "\n").encode(), 0o644, 0),
    }
    before = {path: snapshot(path) for path in writes}
    active, enabled = unit_state()
    if enabled in {"masked", "masked-runtime"}:
        raise ServiceError("kokoro_unit_masked")
    backup = Path(tempfile.mkdtemp(prefix="install-2.6-", dir=STATE))
    backup.chmod(0o700)
    for index, (path, previous) in enumerate(before.items()):
        if previous is not None:
            target = backup / f"{index}-{path.name}"
            target.write_bytes(previous[0]); target.chmod(0o600)
    (backup / "service-state.json").write_text(json.dumps({"active": active, "enabled": enabled}))
    published = {}
    owned = {}
    expected_state = (active, enabled)
    def service_command(action):
        nonlocal expected_state
        run(["systemctl", action, UNIT])
        expected_state = unit_state()
    try:
        if active == "active":
            service_command("stop")
        for path, (body, mode, group) in writes.items():
            if snapshot(path) != before[path]:
                raise ServiceError("managed_input_changed_retry")
            atomic_write(path, body, mode, gid=group)
            published[path] = body
            owned[path] = snapshot(path)
        run(["systemctl", "daemon-reload"])
        expected_state = unit_state()
        run(["systemd-analyze", "verify", UNIT_PATH])
        if no_start:
            service_command("disable")
        else:
            service_command("enable")
            service_command("restart")
            wait_health(cfg)
    except BaseException:
        # Do not combine restored files with another administrator's service
        # decision. A changed state (including an asynchronous process failure)
        # requires inspection instead of an unsafe automatic restart.
        if unit_state() != expected_state or any(snapshot(path) != value for path, value in owned.items()):
            raise ServiceError("rollback_preserved_concurrent_edit_or_state_manual_check_required")
        subprocess.run(["systemctl", "stop", UNIT], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        conflict = False
        for path, body in reversed(list(published.items())):
            if not path.exists() or path.is_symlink() or path.read_bytes() != body:
                conflict = True
                continue
            old = before[path]
            if old is None:
                path.unlink()
            else:
                atomic_write(path, old[0], old[1], old[2], old[3])
        run(["systemctl", "daemon-reload"])
        subprocess.run(["systemctl", "disable", UNIT], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if enabled in {"enabled", "enabled-runtime"}:
            run(["systemctl", "enable", *(["--runtime"] if enabled == "enabled-runtime" else []), UNIT])
        if active == "active" and not conflict:
            run(["systemctl", "start", UNIT])
        if conflict:
            raise ServiceError("rollback_preserved_concurrent_edit_manual_check_required")
        raise


@contextmanager
def maintenance_lock():
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    if STATE.resolve() != STATE:
        raise ServiceError("unsafe_state_directory")
    fd = os.open(STATE / "install.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(fd)


def main():
    global VENV
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=("install", "configure", "plan"), required=True)
    parser.add_argument("--device", choices=("cuda", "cpu"))
    parser.add_argument("--port", type=int)
    parser.add_argument("--gpu-uuid", default="")
    parser.add_argument("--no-start", action="store_true")
    args = parser.parse_args()
    cfg = desired_config(CONFIG, args.device, args.port)
    if cfg.device == "cpu":
        VENV = VENV.with_name(VENV.name + "-cpu")
    if cfg.device == "cuda" and not re.fullmatch(r"GPU-[A-Za-z0-9-]+", args.gpu_uuid):
        raise ServiceError("stable_cuda_gpu_uuid_required")
    if args.action == "plan":
        print(config_text(cfg), end="")
        return
    if os.geteuid() != 0:
        raise ServiceError("root_required")
    with maintenance_lock():
        initial = snapshot(CONFIG)
        if args.action == "install":
            prepare(cfg)
        elif not (VENV / "bin/python").exists():
            raise ServiceError("kokoro_2_6_environment_missing_run_install")
        if snapshot(CONFIG) != initial:
            raise ServiceError("config_changed_during_preparation_retry")
        publish(cfg, args.gpu_uuid, args.no_start)
    print("KOKORO_INSTALL_OK version=2.6")


if __name__ == "__main__":
    try:
        main()
    except (ServiceError, OSError, ValueError, TypeError, subprocess.CalledProcessError) as error:
        # Fixed technical errors only; never dump configuration or model input.
        print("KOKORO_INSTALL_FAIL " + (str(error) if isinstance(error, ServiceError) else type(error).__name__), file=sys.stderr)
        raise SystemExit(1)
