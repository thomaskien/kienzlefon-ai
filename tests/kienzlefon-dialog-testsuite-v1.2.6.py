#!/usr/bin/env python3
"""
Kienzlefon dialog, voice and regression test runner.

Direct mode talks to the real kienzlefon-ai-text-v1 API. Voice mode drives a
real telephone call through Asterisk chan_websocket and the configured patient
TTS / observer ASR. Voice v1.2.5 adds a deterministic reference/WAV diagnostic mode: after the
external target answers, it records a fixed RX-only window, plays one fully
prepared WAV without VAD/barge-in control, then records another fixed RX-only
window. Normal voice mode remains available separately. Version 1.2.6 aligns
the Qwen default speaker with the Kienzlefon 2.0 runtime profile.
The runner deliberately does not reproduce Kienzlefon's
domain logic and performs technical validation only. All scenario data must be
synthetic.
"""

from __future__ import annotations

import argparse
import array
import base64
import concurrent.futures
import contextlib
import copy
import dataclasses
import datetime as dt
import hashlib
import http.client
import ipaddress
import json
import math
import os
import queue
import re
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import wave
from collections import deque
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence


VERSION = "1.2.6"
SCENARIO_FORMAT_VERSION = "1.0"
TEXT_PROTOCOL = "kienzlefon-ai-text-v1"
RUN_PROTOCOL = "kienzlefon-dialog-test-run-v1"
RECORDS_PROTOCOL = "kienzlefon-dialog-records-v1"
TECHNICAL_PROTOCOL = "kienzlefon-dialog-technical-validation-v1"
MAX_HTTP_BODY_BYTES = 16 * 1024 * 1024
HANGUP_SIGNAL = "SIMULATE_HANGUP"
DEFAULT_TIMEOUT_SECONDS = 120.0
DEFAULT_PATIENT_MAX_TOKENS = 160
DEFAULT_PATIENT_TEMPERATURE = 0.3
DEFAULT_PATIENT_TOP_P = 0.9
VOICE_PROTOCOL = "kienzlefon-dialog-voice-v1"
VOICE_MEDIA_RATE = 16000
VOICE_PCM_WIDTH = 2
VOICE_FRAME_MS = 20
VOICE_FRAME_BYTES = VOICE_MEDIA_RATE * VOICE_PCM_WIDTH * VOICE_FRAME_MS // 1000
DEFAULT_VOICE_MEDIA_BIND = "127.0.0.1"
DEFAULT_VOICE_MEDIA_PORT = 8787
DEFAULT_VOICE_WS_CONNECTION = "kienzlefon-testsuite"
DEFAULT_VOICE_ASTERISK_ENDPOINT = "ai-slot-02-endpoint"
DEFAULT_VOICE_ASR_URL = "ws://127.0.0.1:8178/v1/asr/stream"
DEFAULT_VOICE_QWEN_URL = "http://127.0.0.1:8182/v1/tts/stream"
DEFAULT_VOICE_PIPER_URL = "http://127.0.0.1:8181/v1/audio/speech"
DEFAULT_VOICE_QWEN_SPEAKER = "uncle_fu"
DEFAULT_VOICE_QWEN_LANGUAGE = "German"
DEFAULT_VOICE_QWEN_SEED = 42
DEFAULT_VOICE_ANSWER_TIMEOUT = 35.0
DEFAULT_VOICE_GREETING_WAIT = 15.0
DEFAULT_VOICE_RESPONSE_TIMEOUT = 30.0
DEFAULT_VOICE_ASR_TIMEOUT = 45.0
DEFAULT_VOICE_TTS_TIMEOUT = 45.0
DEFAULT_VOICE_DIAL_TIMEOUT = 120
DEFAULT_VOICE_LISTEN_ONLY_SECONDS = 0.0
DEFAULT_VOICE_WAKEUP_TEXT = "Hallo."
DEFAULT_VOICE_WAKEUP_BARGE_MS = 20
DEFAULT_VOICE_ENERGY_THRESHOLD = 180
DEFAULT_VOICE_PREROLL_MS = 300
DEFAULT_VOICE_SPEECH_START_MS = 120
DEFAULT_VOICE_SPEECH_END_MS = 3000
DEFAULT_VOICE_MIN_UTTERANCE_MS = 240
DEFAULT_VOICE_MAX_UTTERANCE_MS = 30000
DEFAULT_VOICE_COMFORT_NOISE_RMS = 0
DEFAULT_VOICE_COMFORT_NOISE_SEED = 1202
DEFAULT_VOICE_REFERENCE_SECONDS = 12.0
DEFAULT_VOICE_REFERENCE_TEXT = "Guten Tag, ich wollte ein Rezept bestellen."


class TestsuiteError(Exception):
    """Base class for expected, safely reportable failures."""


class DependencyError(TestsuiteError):
    pass


class ConfigurationError(TestsuiteError):
    pass


class ContractError(TestsuiteError):
    pass


class VoiceError(TestsuiteError):
    pass


class TransportError(TestsuiteError):
    def __init__(
        self,
        operation: str,
        reason: str,
        *,
        status: int | None = None,
        response_body: str | None = None,
    ) -> None:
        super().__init__(f"{operation}: {reason}")
        self.operation = operation
        self.reason = reason
        self.status = status
        self.response_body = response_body


def dependency_modules() -> tuple[Any, Any]:
    try:
        import yaml
    except ImportError as exc:
        raise DependencyError(
            "PyYAML is missing; install the pinned testsuite requirements"
        ) from exc
    try:
        import jsonschema
    except ImportError as exc:
        raise DependencyError(
            "jsonschema is missing; install the pinned testsuite requirements"
        ) from exc
    return yaml, jsonschema


def now_iso() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="milliseconds")


def utc_run_stamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d_%H%M%SZ")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def strict_json_loads(text: str) -> Any:
    def reject_constant(value: str) -> None:
        raise ValueError(f"non-standard JSON constant: {value}")

    return json.loads(text, parse_constant=reject_constant)


def json_text(value: Any, *, pretty: bool = False) -> str:
    options: dict[str, Any] = {
        "ensure_ascii": False,
        "allow_nan": False,
        "sort_keys": True,
    }
    if pretty:
        options["indent"] = 2
    else:
        options["separators"] = (",", ":")
    return json.dumps(value, **options)


def ensure_private_dir(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.chmod(0o700)


def atomic_write_bytes(path: Path, data: bytes) -> None:
    ensure_private_dir(path.parent)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=str(path.parent)
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        path.chmod(0o600)
    finally:
        if temporary.exists():
            temporary.unlink()


def atomic_write_text(path: Path, text: str) -> None:
    atomic_write_bytes(path, text.encode("utf-8"))


def write_json(path: Path, value: Any) -> None:
    atomic_write_text(path, json_text(value, pretty=True) + "\n")


def read_utf8(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise ConfigurationError(f"{path}: not valid UTF-8") from exc


def safe_version_label(path: Path, explicit: str | None) -> str:
    if explicit:
        return explicit
    match = re.search(r"(?:^|[-_.])v(\d+(?:\.\d+)*)", path.name)
    if not match:
        raise ConfigurationError(
            f"cannot infer a version from {path.name}; provide an explicit version"
        )
    return match.group(1)


def safe_run_id(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value):
        raise ConfigurationError(
            "run ID must contain 1-128 ASCII letters, digits, dots, underscores, or dashes"
        )
    return value


def assert_loopback_url(value: str, label: str) -> None:
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ConfigurationError(f"{label} must be an HTTP(S) URL")
    hostname = parsed.hostname
    if hostname == "localhost":
        return
    try:
        address = ipaddress.ip_address(hostname)
    except ValueError as exc:
        raise ConfigurationError(f"{label} must use a loopback host") from exc
    if not address.is_loopback:
        raise ConfigurationError(f"{label} must use a loopback host")



def assert_loopback_ws_url(value: str, label: str) -> None:
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme not in {"ws", "wss"} or not parsed.hostname:
        raise ConfigurationError(f"{label} must be a WS(S) URL")
    hostname = parsed.hostname
    if hostname == "localhost":
        return
    try:
        address = ipaddress.ip_address(hostname)
    except ValueError as exc:
        raise ConfigurationError(f"{label} must use a loopback host") from exc
    if not address.is_loopback:
        raise ConfigurationError(f"{label} must use a loopback host")


def monotonic_ms() -> float:
    return round(time.monotonic_ns() / 1_000_000.0, 3)


def safe_voice_identifier(value: str, label: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.:-]{1,128}", value):
        raise ConfigurationError(f"{label} contains unsupported characters")
    return value


def validate_target_number(value: str) -> str:
    if not re.fullmatch(r"\+[1-9][0-9]{6,14}", value):
        raise ConfigurationError(
            "--target-number must be an international E.164-style number such as +492331234567"
        )
    return value


def write_pcm_wav(path: Path, pcm: bytes, sample_rate: int = VOICE_MEDIA_RATE) -> None:
    ensure_private_dir(path.parent)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with wave.open(str(temporary), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(VOICE_PCM_WIDTH)
            handle.setframerate(sample_rate)
            handle.writeframes(pcm)
        temporary.chmod(0o600)
        os.replace(temporary, path)
        path.chmod(0o600)
    finally:
        if temporary.exists():
            temporary.unlink()


def deep_json_copy(value: Any) -> Any:
    return strict_json_loads(json_text(value))


def safe_error_summary(exc: BaseException) -> str:
    if isinstance(exc, TransportError):
        status = f" HTTP {exc.status}" if exc.status is not None else ""
        return f"{exc.operation}:{status} {exc.reason}".strip()
    if isinstance(exc, TestsuiteError):
        return str(exc)
    return type(exc).__name__


@dataclasses.dataclass(frozen=True)
class HTTPPayload:
    status: int
    body_text: str
    data: Any
    headers: Mapping[str, str]


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: Any,
        code: int,
        msg: str,
        headers: Mapping[str, str],
        newurl: str,
    ) -> None:
        return None


class JSONHTTPClient:
    def __init__(self, timeout: float) -> None:
        self.timeout = timeout
        self.opener = urllib.request.build_opener(NoRedirectHandler())

    def request(
        self,
        operation: str,
        method: str,
        url: str,
        payload: Mapping[str, Any] | None = None,
    ) -> HTTPPayload:
        body = None
        headers = {"Accept": "application/json"}
        if payload is not None:
            body = json_text(payload).encode("utf-8")
            headers["Content-Type"] = "application/json; charset=utf-8"
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                raw = response.read(MAX_HTTP_BODY_BYTES + 1)
                status = int(response.status)
                response_headers = dict(response.headers.items())
        except urllib.error.HTTPError as exc:
            raw = exc.read(MAX_HTTP_BODY_BYTES + 1)
            response_text = raw.decode("utf-8", errors="replace")
            raise TransportError(
                operation,
                "HTTP request rejected",
                status=int(exc.code),
                response_body=response_text,
            ) from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise TransportError(operation, type(exc).__name__) from exc
        if len(raw) > MAX_HTTP_BODY_BYTES:
            raise TransportError(operation, "response body exceeds safety limit")
        try:
            response_text = raw.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise TransportError(operation, "response is not UTF-8") from exc
        try:
            data = strict_json_loads(response_text)
        except (json.JSONDecodeError, ValueError) as exc:
            raise TransportError(
                operation,
                "response is not strict JSON",
                status=status,
                response_body=response_text,
            ) from exc
        return HTTPPayload(status, response_text, data, response_headers)


class RuntimeClient:
    def __init__(self, base_url: str, timeout: float) -> None:
        self.base_url = base_url.rstrip("/")
        self.http = JSONHTTPClient(timeout)

    def _url(self, path: str) -> str:
        return self.base_url + path

    def health(self) -> HTTPPayload:
        return self.http.request("backend_health", "GET", self._url("/health"))

    def metadata(self) -> HTTPPayload:
        return self.http.request(
            "backend_metadata", "GET", self._url("/v1/dialog/metadata")
        )

    def create_session(
        self, channel: str, environment: Mapping[str, Any]
    ) -> HTTPPayload:
        return self.http.request(
            "backend_create_session",
            "POST",
            self._url("/v1/dialog/sessions"),
            {
                "channel": channel,
                "caller_id": environment.get("caller_id"),
                "environment": {
                    "within_phone_hours": environment.get(
                        "within_phone_hours", False
                    )
                },
            },
        )

    def turn(self, session_id: str, text: str) -> HTTPPayload:
        return self.http.request(
            "backend_turn",
            "POST",
            self._url(f"/v1/dialog/sessions/{session_id}/turn"),
            {"text": text},
        )

    def hangup(self, session_id: str) -> HTTPPayload:
        return self.http.request(
            "backend_hangup",
            "POST",
            self._url(f"/v1/dialog/sessions/{session_id}/hangup"),
            {},
        )

    def delete(self, session_id: str) -> HTTPPayload:
        return self.http.request(
            "backend_delete",
            "DELETE",
            self._url(f"/v1/dialog/sessions/{session_id}"),
        )


def endpoint_sibling(url: str, leaf: str) -> str:
    parsed = urllib.parse.urlparse(url)
    path = parsed.path.rstrip("/")
    suffix = "/chat/completions"
    if path.endswith(suffix):
        path = path[: -len(suffix)] + "/" + leaf.lstrip("/")
    else:
        path = path.rsplit("/", 1)[0] + "/" + leaf.lstrip("/")
    return urllib.parse.urlunparse(parsed._replace(path=path, query="", fragment=""))


class PatientLLMClient:
    def __init__(
        self,
        endpoint: str,
        timeout: float,
        *,
        model: str | None,
        temperature: float,
        top_p: float,
        max_tokens: int,
    ) -> None:
        self.endpoint = endpoint
        self.http = JSONHTTPClient(timeout)
        self.model = model
        self.temperature = temperature
        self.top_p = top_p
        self.max_tokens = max_tokens

    def discover_model(self) -> tuple[str, dict[str, Any]]:
        result = self.http.request(
            "patient_models", "GET", endpoint_sibling(self.endpoint, "models")
        )
        if not isinstance(result.data, Mapping):
            raise ContractError("patient model endpoint returned a non-object")
        models = result.data.get("data")
        if not isinstance(models, list) or not models:
            raise ContractError("patient model endpoint returned no models")
        first = models[0]
        if not isinstance(first, Mapping) or not isinstance(first.get("id"), str):
            raise ContractError("patient model endpoint has an invalid model entry")
        return first["id"], deep_json_copy(result.data)

    def try_props(self) -> dict[str, Any] | None:
        try:
            result = self.http.request(
                "patient_props", "GET", endpoint_sibling(self.endpoint, "props")
            )
        except TestsuiteError:
            return None
        return deep_json_copy(result.data) if isinstance(result.data, Mapping) else None

    def complete(
        self, messages: Sequence[Mapping[str, str]], seed: int
    ) -> tuple[str, Mapping[str, Any], HTTPPayload]:
        if not self.model:
            raise ConfigurationError("patient model has not been resolved")
        request_payload: dict[str, Any] = {
            "model": self.model,
            "messages": [dict(message) for message in messages],
            "temperature": self.temperature,
            "top_p": self.top_p,
            "max_tokens": self.max_tokens,
            "seed": seed,
            "stream": False,
            "chat_template_kwargs": {"enable_thinking": False},
        }
        result = self.http.request(
            "patient_completion", "POST", self.endpoint, request_payload
        )
        if not isinstance(result.data, Mapping):
            raise ContractError("patient completion returned a non-object")
        choices = result.data.get("choices")
        if not isinstance(choices, list) or not choices:
            raise ContractError("patient completion returned no choices")
        first = choices[0]
        if not isinstance(first, Mapping):
            raise ContractError("patient completion choice is invalid")
        message = first.get("message")
        if not isinstance(message, Mapping) or not isinstance(
            message.get("content"), str
        ):
            raise ContractError("patient completion content is not a string")
        content = message["content"].strip()
        if not content:
            raise ContractError("patient completion content is empty")
        return content, request_payload, result


@dataclasses.dataclass(frozen=True)
class Scenario:
    scenario_id: str
    path: Path
    source_bytes: bytes
    data: Mapping[str, Any]

    @property
    def source_sha256(self) -> str:
        return sha256_bytes(self.source_bytes)


def verify_package_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = strict_json_loads(read_utf8(path))
    except (json.JSONDecodeError, ValueError) as exc:
        raise ConfigurationError(f"{path}: invalid package manifest") from exc
    if not isinstance(manifest, Mapping) or not isinstance(
        manifest.get("files"), list
    ):
        raise ConfigurationError(f"{path}: invalid package manifest structure")
    root = path.parent
    listed: set[Path] = set()
    for entry in manifest["files"]:
        if not isinstance(entry, Mapping):
            raise ConfigurationError(f"{path}: invalid file entry")
        relative = entry.get("path")
        expected_hash = entry.get("sha256")
        expected_size = entry.get("bytes")
        if (
            not isinstance(relative, str)
            or not isinstance(expected_hash, str)
            or not isinstance(expected_size, int)
        ):
            raise ConfigurationError(f"{path}: incomplete file entry")
        pure = Path(relative)
        if pure.is_absolute() or ".." in pure.parts:
            raise ConfigurationError(f"{path}: unsafe manifest path {relative}")
        candidate = root / pure
        if not candidate.is_file():
            raise ConfigurationError(f"{candidate}: manifest file is missing")
        data = candidate.read_bytes()
        if len(data) != expected_size or sha256_bytes(data) != expected_hash:
            raise ConfigurationError(f"{candidate}: package integrity mismatch")
        listed.add(pure)
    actual = {
        candidate.relative_to(root)
        for candidate in root.rglob("*")
        if candidate.is_file() and candidate != path
    }
    if actual != listed:
        missing = sorted(str(item) for item in listed - actual)
        extra = sorted(str(item) for item in actual - listed)
        raise ConfigurationError(
            f"{path}: package file set mismatch; missing={missing}, extra={extra}"
        )
    return dict(manifest)


def load_scenarios(
    scenarios_dir: Path,
    schema_path: Path,
    *,
    channel: str,
    selected_ids: Sequence[str],
    selected_tags: Sequence[str],
) -> list[Scenario]:
    yaml, jsonschema = dependency_modules()
    try:
        schema = strict_json_loads(read_utf8(schema_path))
    except (json.JSONDecodeError, ValueError) as exc:
        raise ConfigurationError(f"{schema_path}: invalid JSON schema") from exc
    validator_class = jsonschema.validators.validator_for(schema)
    validator_class.check_schema(schema)
    validator = validator_class(schema)
    scenarios: list[Scenario] = []
    seen_ids: set[str] = set()
    for path in sorted(scenarios_dir.glob("KF-*.yaml")):
        source_bytes = path.read_bytes()
        try:
            source_text = source_bytes.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ConfigurationError(f"{path}: not valid UTF-8") from exc
        try:
            value = yaml.safe_load(source_text)
        except yaml.YAMLError as exc:
            raise ConfigurationError(f"{path}: invalid YAML") from exc
        errors = sorted(validator.iter_errors(value), key=lambda error: list(error.path))
        if errors:
            detail = "; ".join(
                f"{'/'.join(str(part) for part in error.path) or '<root>'}: "
                f"{error.message}"
                for error in errors
            )
            raise ConfigurationError(f"{path}: schema validation failed: {detail}")
        scenario_id = value["scenario_id"]
        if scenario_id in seen_ids:
            raise ConfigurationError(f"duplicate scenario ID: {scenario_id}")
        seen_ids.add(scenario_id)
        if not value["enabled"] or channel not in value["channels"]:
            continue
        if selected_ids and scenario_id not in selected_ids:
            continue
        tags = set(value["tags"])
        if selected_tags and not tags.intersection(selected_tags):
            continue
        scenarios.append(Scenario(scenario_id, path, source_bytes, value))
    missing_ids = sorted(set(selected_ids) - seen_ids)
    if missing_ids:
        raise ConfigurationError(f"unknown scenario IDs: {', '.join(missing_ids)}")
    if not scenarios:
        raise ConfigurationError("scenario selection is empty")
    return scenarios


def verify_scenario_index(scenarios_dir: Path) -> None:
    index_path = scenarios_dir / "index.json"
    if not index_path.is_file():
        raise ConfigurationError(f"{index_path}: scenario index is missing")
    try:
        index = strict_json_loads(read_utf8(index_path))
    except (json.JSONDecodeError, ValueError) as exc:
        raise ConfigurationError(f"{index_path}: invalid JSON") from exc
    if not isinstance(index, list):
        raise ConfigurationError(f"{index_path}: index must be an array")
    indexed = {
        (entry.get("scenario_id"), entry.get("file"))
        for entry in index
        if isinstance(entry, Mapping)
    }
    actual = set()
    yaml, _ = dependency_modules()
    for path in scenarios_dir.glob("KF-*.yaml"):
        value = yaml.safe_load(read_utf8(path))
        actual.add((value.get("scenario_id"), path.name))
    if indexed != actual:
        raise ConfigurationError(f"{index_path}: index does not match YAML files")


def allowed_patient_context(scenario: Scenario, channel: str) -> dict[str, Any]:
    return {
        "format": "kienzlefon-patient-simulation-context-v1",
        "channel": channel,
        "patient": deep_json_copy(scenario.data["patient"]),
    }


def initial_patient_messages(
    scenario: Scenario, channel: str, patient_system_prompt: str
) -> list[dict[str, str]]:
    context = allowed_patient_context(scenario, channel)
    return [
        {"role": "system", "content": patient_system_prompt},
        {
            "role": "user",
            "content": (
                "Zulässiger synthetischer Szenariokontext. Verwende ausschließlich "
                "diese Angaben:\n" + json_text(context, pretty=True)
            ),
        },
        {"role": "assistant", "content": str(scenario.data["patient"]["opening"])},
    ]


def validate_runtime_metadata(
    metadata: Any,
    *,
    channel: str,
) -> dict[str, Any]:
    if not isinstance(metadata, Mapping):
        raise ContractError("runtime metadata is not an object")
    if metadata.get("protocol") != TEXT_PROTOCOL:
        raise ContractError("runtime metadata protocol mismatch")
    system_prompt = metadata.get("system_prompt")
    if not isinstance(system_prompt, str) or not system_prompt.strip():
        raise ContractError("runtime metadata has no usable system prompt")
    overlays = metadata.get("channel_overlays")
    if not isinstance(overlays, Mapping):
        raise ContractError("runtime channel overlay metadata is incomplete")
    overlay = overlays.get(channel)
    if not isinstance(overlay, str) or not overlay.strip():
        raise ContractError(f"runtime has no usable {channel} overlay")
    if not isinstance(metadata.get("backend_version"), str):
        raise ContractError("runtime metadata has no backend version")
    if not isinstance(metadata.get("llm_url"), str):
        raise ContractError("runtime metadata has no LLM URL")
    if not isinstance(metadata.get("inference"), Mapping):
        raise ContractError("runtime metadata has no inference parameters")
    return dict(metadata)


def validate_session_created(value: Any, channel: str) -> str:
    if not isinstance(value, Mapping):
        raise ContractError("session response is not an object")
    if value.get("protocol") != TEXT_PROTOCOL:
        raise ContractError("session response protocol mismatch")
    session_id = value.get("session_id")
    if not isinstance(session_id, str):
        raise ContractError("session response has no session ID")
    try:
        uuid.UUID(session_id)
    except ValueError as exc:
        raise ContractError("session response has an invalid session ID") from exc
    if value.get("channel") != channel or value.get("terminal") is not False:
        raise ContractError("session response has an invalid initial state")
    return session_id


def validate_record(record: Any) -> None:
    if not isinstance(record, Mapping):
        raise ContractError("backend record is not an object")
    if not isinstance(record.get("type"), str):
        raise ContractError("backend record type is not a string")
    if not isinstance(record.get("complete"), bool):
        raise ContractError("backend record complete is not boolean")
    if not isinstance(record.get("data"), Mapping):
        raise ContractError("backend record data is not an object")
    try:
        json_text(record)
    except (TypeError, ValueError) as exc:
        raise ContractError("backend record is not JSON serializable") from exc


def validate_turn_response(
    value: Any, *, session_id: str, channel: str, includes_llm_result: bool
) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise ContractError("backend response is not an object")
    if value.get("protocol") != TEXT_PROTOCOL:
        raise ContractError("backend response protocol mismatch")
    if value.get("session_id") != session_id or value.get("channel") != channel:
        raise ContractError("backend response session identity mismatch")
    if not isinstance(value.get("terminal"), bool):
        raise ContractError("backend response terminal is not boolean")
    if not isinstance(value.get("state"), Mapping):
        raise ContractError("backend response state is not an object")
    state_orders = value["state"].get("orders")
    if not isinstance(state_orders, list):
        raise ContractError("backend state orders is not an array")
    records = value.get("records")
    if not isinstance(records, list):
        raise ContractError("backend records is not an array")
    for record in records:
        validate_record(record)
    action_result = value.get("action_result")
    if action_result is not None and not isinstance(action_result, Mapping):
        raise ContractError("backend action_result is not an object or null")
    if includes_llm_result:
        if not isinstance(value.get("reply"), str):
            raise ContractError("backend reply is not a string")
        if "raw_response" not in value:
            raise ContractError("backend raw_response is missing")
        normalized = value.get("normalized_response")
        if not isinstance(normalized, Mapping):
            raise ContractError("backend normalized_response is not an object")
        if not isinstance(normalized.get("orders"), list):
            raise ContractError("backend normalized orders is not an array")
        if not isinstance(value.get("repairs"), list):
            raise ContractError("backend repairs is not an array")
    return dict(value)


@dataclasses.dataclass
class TechnicalValidation:
    scenario_id: str
    checks: list[dict[str, Any]] = dataclasses.field(default_factory=list)
    errors: list[dict[str, Any]] = dataclasses.field(default_factory=list)
    warnings: list[dict[str, Any]] = dataclasses.field(default_factory=list)
    terminal_reason: str | None = None

    def check(self, name: str, detail: str = "ok") -> None:
        self.checks.append({"name": name, "ok": True, "detail": detail})

    def error(self, code: str, detail: str) -> None:
        self.errors.append({"code": code, "detail": detail})

    def warning(self, code: str, detail: str) -> None:
        self.warnings.append({"code": code, "detail": detail})

    @property
    def passed(self) -> bool:
        return not self.errors

    def payload(self) -> dict[str, Any]:
        return {
            "protocol": TECHNICAL_PROTOCOL,
            "scenario_id": self.scenario_id,
            "technical_status": "PASS" if self.passed else "FAIL",
            "semantic_evaluation": "NOT_PERFORMED",
            "terminal_reason": self.terminal_reason,
            "checks": self.checks,
            "errors": self.errors,
            "warnings": self.warnings,
        }


class EventRecorder:
    def __init__(self, scenario_id: str, channel: str) -> None:
        self.scenario_id = scenario_id
        self.channel = channel
        self.events: list[dict[str, Any]] = []

    def add(self, event: str, *, turn: int | None = None, **values: Any) -> None:
        payload: dict[str, Any] = {
            "event": event,
            "timestamp": now_iso(),
            "scenario_id": self.scenario_id,
            "channel": self.channel,
        }
        if turn is not None:
            payload["turn"] = turn
        payload.update(values)
        self.events.append(payload)

    def write(self, path: Path) -> None:
        content = "".join(json_text(event) + "\n" for event in self.events)
        atomic_write_text(path, content)


def print_live_dialog_turn(scenario_id: str, role: str, value: str) -> None:
    safe = "".join(
        character
        if character in "\n\t" or character.isprintable()
        else f"\\u{ord(character):04x}"
        for character in value
    )
    lines = safe.splitlines() or [""]
    for index, line in enumerate(lines):
        visible_role = role if index == 0 else "..."
        print(f"[{scenario_id}] {visible_role}: {line}", flush=True)



@dataclasses.dataclass(frozen=True)
class ConfirmedSegment:
    start: float | None
    end: float | None
    text: str
    sequence: int


class ConfirmedTranscriptAssembler:
    START_TOLERANCE_SECONDS = 0.08

    def __init__(self) -> None:
        self._segments: list[ConfirmedSegment] = []
        self._sequence = 0

    @staticmethod
    def _time(value: Any) -> float | None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        result = float(value)
        return result if math.isfinite(result) else None

    @staticmethod
    def _revision(old: str, new: str) -> bool:
        old, new = old.strip(), new.strip()
        return bool(old and new and (old.startswith(new) or new.startswith(old)))

    def add(self, text: str, start: Any, end: Any) -> None:
        text = text.strip()
        if not text:
            return
        start_f, end_f = self._time(start), self._time(end)
        self._sequence += 1
        match: int | None = None
        if start_f is not None:
            match = next(
                (
                    index
                    for index, segment in enumerate(self._segments)
                    if segment.start is not None
                    and abs(segment.start - start_f) <= self.START_TOLERANCE_SECONDS
                ),
                None,
            )
        if match is None and start_f is not None and end_f is not None:
            for index, segment in enumerate(self._segments):
                if (
                    segment.start is not None
                    and segment.end is not None
                    and min(segment.end, end_f)
                    >= max(segment.start, start_f) - self.START_TOLERANCE_SECONDS
                    and self._revision(segment.text, text)
                ):
                    match = index
                    break
        if match is None and start_f is None and self._segments:
            last = self._segments[-1]
            if last.start is None and self._revision(last.text, text):
                match = len(self._segments) - 1
        replacement = ConfirmedSegment(start_f, end_f, text, self._sequence)
        if match is None:
            self._segments.append(replacement)
        else:
            previous = self._segments[match]
            replacement = ConfirmedSegment(
                start_f if start_f is not None else previous.start,
                end_f if end_f is not None else previous.end,
                text,
                previous.sequence,
            )
            self._segments[match] = replacement

    def transcript(self) -> str:
        ordered = sorted(
            self._segments,
            key=lambda item: (1, 0.0, item.sequence)
            if item.start is None
            else (0, item.start, item.sequence),
        )
        return " ".join(item.text for item in ordered).strip()


class ASRWebSocketClient:
    """Minimal dependency-free RFC6455 client for the local Kienzlefon ASR."""

    def __init__(self, url: str, timeout: float) -> None:
        self.url = url
        self.timeout = timeout
        self.sock: socket.socket | ssl.SSLSocket | None = None
        self.buffer = bytearray()

    def __enter__(self) -> "ASRWebSocketClient":
        parsed = urllib.parse.urlsplit(self.url)
        if parsed.scheme not in {"ws", "wss"} or not parsed.hostname:
            raise VoiceError("invalid ASR WebSocket URL")
        secure = parsed.scheme == "wss"
        port = parsed.port or (443 if secure else 80)
        sock = socket.create_connection((parsed.hostname, port), timeout=self.timeout)
        if secure:
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname=parsed.hostname)
        sock.settimeout(self.timeout)
        self.sock = sock
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        host = parsed.hostname if port == (443 if secure else 80) else f"{parsed.hostname}:{port}"
        request = (
            f"GET {path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\n"
            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\nUser-Agent: Kienzlefon-Dialog-Testsuite/1.1.4\r\n\r\n"
        ).encode("ascii")
        sock.sendall(request)
        header = self._read_header()
        lines = header.decode("iso-8859-1").split("\r\n")
        if not lines or " 101 " not in f" {lines[0]} ":
            raise VoiceError("ASR WebSocket upgrade failed")
        headers = {
            name.strip().lower(): value.strip()
            for line in lines[1:]
            if ":" in line
            for name, value in [line.split(":", 1)]
        }
        expected = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
        ).decode()
        if headers.get("sec-websocket-accept") != expected:
            raise VoiceError("ASR WebSocket accept key mismatch")
        return self

    def _read_header(self) -> bytes:
        assert self.sock is not None
        while b"\r\n\r\n" not in self.buffer:
            if len(self.buffer) >= 65536:
                raise VoiceError("ASR WebSocket header too large")
            block = self.sock.recv(4096)
            if not block:
                raise VoiceError("ASR WebSocket closed during handshake")
            self.buffer.extend(block)
        end = self.buffer.index(b"\r\n\r\n") + 4
        header = bytes(self.buffer[:end])
        del self.buffer[:end]
        return header

    def _recv_exact(self, size: int) -> bytes:
        assert self.sock is not None
        while len(self.buffer) < size:
            block = self.sock.recv(max(4096, size - len(self.buffer)))
            if not block:
                raise VoiceError("ASR WebSocket closed")
            self.buffer.extend(block)
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    def send(self, opcode: int, payload: bytes) -> None:
        assert self.sock is not None
        length = len(payload)
        if length < 126:
            length_bytes = bytes([0x80 | length])
        elif length <= 65535:
            length_bytes = bytes([0x80 | 126]) + struct.pack("!H", length)
        else:
            length_bytes = bytes([0x80 | 127]) + struct.pack("!Q", length)
        mask = os.urandom(4)
        masked = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))
        self.sock.sendall(bytes([0x80 | opcode]) + length_bytes + mask + masked)

    def send_binary(self, payload: bytes) -> None:
        self.send(0x2, payload)

    def recv_json(self) -> Mapping[str, Any]:
        fragments = bytearray()
        message_opcode: int | None = None
        while True:
            first, second = self._recv_exact(2)
            final = bool(first & 0x80)
            opcode = first & 0x0F
            if first & 0x70:
                raise VoiceError("ASR WebSocket reserved bits set")
            if second & 0x80:
                raise VoiceError("ASR server sent a masked frame")
            length = second & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._recv_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._recv_exact(8))[0]
            if length > 4 * 1024 * 1024:
                raise VoiceError("ASR WebSocket message too large")
            payload = self._recv_exact(length) if length else b""
            if opcode == 0x8:
                raise VoiceError("ASR WebSocket closed before end event")
            if opcode == 0x9:
                self.send(0xA, payload)
                continue
            if opcode == 0xA:
                continue
            if opcode in {0x1, 0x2}:
                if message_opcode is not None:
                    raise VoiceError("nested ASR WebSocket fragments")
                message_opcode = opcode
                fragments.extend(payload)
            elif opcode == 0x0:
                if message_opcode is None:
                    raise VoiceError("unexpected ASR continuation frame")
                fragments.extend(payload)
            else:
                raise VoiceError("unsupported ASR WebSocket opcode")
            if final:
                if message_opcode != 0x1:
                    raise VoiceError("ASR response was not text JSON")
                value = strict_json_loads(bytes(fragments).decode("utf-8"))
                if not isinstance(value, Mapping):
                    raise VoiceError("ASR response JSON was not an object")
                return value

    def __exit__(self, *_args: Any) -> None:
        if self.sock is not None:
            with contextlib.suppress(OSError):
                self.sock.shutdown(socket.SHUT_RDWR)
            with contextlib.suppress(OSError):
                self.sock.close()
            self.sock = None


class BandlimitedPCMResampler:
    """Stateful dependency-free mono S16LE windowed-sinc resampler."""

    def __init__(self, source_rate: int, target_rate: int) -> None:
        if source_rate <= 0 or target_rate <= 0:
            raise ValueError("sample rates must be positive")
        self.source_rate = source_rate
        self.target_rate = target_rate
        self.radius = 16
        self.cutoff = 0.5 * min(1.0, target_rate / source_rate) * 0.94
        self.samples: list[int] = []
        self.base_index = 0
        self.next_numerator = 0
        self.remainder = b""
        self._phases: dict[int, tuple[tuple[int, float], ...]] = {}

    def _coefficients(self, fraction_numerator: int) -> tuple[tuple[int, float], ...]:
        cached = self._phases.get(fraction_numerator)
        if cached is not None:
            return cached
        fraction = fraction_numerator / self.target_rate
        values: list[tuple[int, float]] = []
        for offset in range(-self.radius + 1, self.radius + 1):
            distance = fraction - offset
            position = abs(distance) / self.radius
            if position >= 1.0:
                weight = 0.0
            else:
                window = (
                    0.42
                    + 0.5 * math.cos(math.pi * position)
                    + 0.08 * math.cos(2.0 * math.pi * position)
                )
                argument = 2.0 * self.cutoff * distance
                sinc = (
                    1.0
                    if abs(argument) < 1e-15
                    else math.sin(math.pi * argument) / (math.pi * argument)
                )
                weight = 2.0 * self.cutoff * sinc * window
            values.append((offset, weight))
        total = sum(weight for _offset, weight in values)
        if abs(total) < 1e-12:
            raise VoiceError("resampler filter invalid")
        result = tuple((offset, weight / total) for offset, weight in values)
        self._phases[fraction_numerator] = result
        return result

    def feed(self, data: bytes, *, final: bool = False) -> bytes:
        combined = self.remainder + data
        self.remainder = combined[-1:] if len(combined) % 2 else b""
        usable = combined[: len(combined) - len(combined) % 2]
        if usable:
            values = array.array("h")
            values.frombytes(usable)
            if sys.byteorder != "little":
                values.byteswap()
            self.samples.extend(int(value) for value in values)

        output = array.array("h")
        end_index = self.base_index + len(self.samples)
        while self.samples:
            left_index, fraction_numerator = divmod(
                self.next_numerator, self.target_rate
            )
            if left_index >= end_index:
                break
            if not final and left_index + self.radius >= end_index:
                break
            weighted = 0.0
            available_weight = 0.0
            for offset, weight in self._coefficients(fraction_numerator):
                source_index = left_index + offset
                if source_index < 0 or source_index >= end_index:
                    continue
                local_index = source_index - self.base_index
                if local_index < 0:
                    raise VoiceError("resampler history underflow")
                weighted += self.samples[local_index] * weight
                available_weight += weight
            if abs(available_weight) < 1e-12:
                raise VoiceError("resampler edge filter invalid")
            value = round(weighted / available_weight)
            output.append(max(-32768, min(32767, value)))
            self.next_numerator += self.source_rate

        if final:
            self.samples.clear()
            self.base_index = 0
            self.next_numerator = 0
            self.remainder = b""
        else:
            next_left = self.next_numerator // self.target_rate
            drop = min(
                max(0, next_left - self.radius + 1 - self.base_index),
                len(self.samples),
            )
            if drop:
                del self.samples[:drop]
                self.base_index += drop
        if sys.byteorder != "little":
            output.byteswap()
        return output.tobytes()


def pcm_resample(data: bytes, source_rate: int, target_rate: int) -> bytes:
    if source_rate == target_rate:
        return data[: len(data) - len(data) % 2]
    return BandlimitedPCMResampler(source_rate, target_rate).feed(data, final=True)


def observer_asr_transcribe(url: str, timeout: float, pcm_16k: bytes) -> tuple[str, dict[str, Any]]:
    started = time.monotonic()
    partial_count = 0
    confirmed_count = 0
    assembler = ConfirmedTranscriptAssembler()
    with ASRWebSocketClient(url, timeout) as ws:
        ready = ws.recv_json()
        audio = ready.get("audio")
        if (
            ready.get("type") != "ready"
            or ready.get("protocol") != "kienzlefon-asr-v1"
            or not isinstance(audio, Mapping)
            or audio.get("encoding") != "pcm_s16le"
            or audio.get("sample_rate") != VOICE_MEDIA_RATE
            or audio.get("channels") != 1
        ):
            raise VoiceError("observer ASR ready contract mismatch")
        for offset in range(0, len(pcm_16k), 6400):
            ws.send_binary(pcm_16k[offset : offset + 6400])
        ws.send_binary(b"")
        while True:
            event = ws.recv_json()
            kind = event.get("type")
            if kind == "confirmed":
                text = event.get("text")
                if isinstance(text, str):
                    confirmed_count += 1
                    assembler.add(text, event.get("start"), event.get("end"))
            elif kind == "partial":
                partial_count += 1
            elif kind == "ready":
                continue
            elif kind == "end":
                break
            elif kind == "error":
                raise VoiceError("observer ASR reported an error")
            else:
                raise VoiceError(f"unknown observer ASR event: {kind!r}")
    transcript = assembler.transcript()
    return transcript, {
        "duration_ms": round((time.monotonic() - started) * 1000.0, 3),
        "partial_count": partial_count,
        "confirmed_count": confirmed_count,
        "confirmed_chars": len(transcript),
    }


def _voice_http_connection(url: str, timeout: float) -> tuple[http.client.HTTPConnection, str]:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise VoiceError("invalid TTS HTTP URL")
    cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
    connection = cls(parsed.hostname, parsed.port, timeout=timeout)
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    return connection, path


def _validate_voice_audio_headers(response: http.client.HTTPResponse, expected_rate: int, explicit: bool) -> int:
    content_type = response.getheader("Content-Type", "").lower()
    if "audio/pcm" not in content_type and "application/octet-stream" not in content_type:
        raise VoiceError("TTS response content type is not raw PCM")
    rate_header = response.getheader("X-Sample-Rate")
    if rate_header:
        if not rate_header.isdigit():
            raise VoiceError("TTS sample-rate header is invalid")
        rate = int(rate_header)
    elif explicit:
        raise VoiceError("TTS sample-rate header is missing")
    else:
        rate = expected_rate
    if rate != expected_rate:
        raise VoiceError(f"unexpected TTS sample rate {rate}")
    channels = response.getheader("X-Channels")
    if explicit and channels is None:
        raise VoiceError("TTS channels header is missing")
    if channels is not None and channels != "1":
        raise VoiceError("TTS is not mono")
    sample_format = response.getheader("X-Sample-Format")
    if explicit and sample_format is None:
        raise VoiceError("TTS sample-format header is missing")
    if sample_format is not None and sample_format.lower() not in {"s16le", "pcm_s16le"}:
        raise VoiceError("TTS sample format is not s16le")
    return rate


class PatientTTSClient:
    def __init__(
        self,
        *,
        backend: str,
        qwen_url: str,
        piper_url: str,
        timeout: float,
        qwen_speaker: str,
        qwen_language: str,
        qwen_seed: int,
    ) -> None:
        self.backend = backend
        self.qwen_url = qwen_url
        self.piper_url = piper_url
        self.timeout = timeout
        self.qwen_speaker = qwen_speaker
        self.qwen_language = qwen_language
        self.qwen_seed = qwen_seed

    def stream(self, text: str, emit: Any) -> dict[str, Any]:
        if not text or len(text) > 4000 or "\x00" in text:
            raise VoiceError("invalid patient TTS input")
        if self.backend == "qwen":
            url = self.qwen_url
            payload = {
                "text": text,
                "speaker": self.qwen_speaker,
                "language": self.qwen_language,
                "seed": self.qwen_seed,
            }
            expected_rate = 24000
            explicit = True
        elif self.backend == "piper":
            url = self.piper_url
            payload = {"input": text, "response_format": "pcm"}
            expected_rate = 22050
            explicit = False
        else:
            raise VoiceError("unsupported patient TTS backend")
        body = json_text(payload).encode("utf-8")
        connection, path = _voice_http_connection(url, self.timeout)
        started = time.monotonic()
        first_audio: float | None = None
        source_bytes = 0
        target_bytes = 0
        probe = bytearray()
        try:
            connection.request(
                "POST",
                path,
                body=body,
                headers={
                    "Content-Type": "application/json; charset=utf-8",
                    "Accept": "audio/pcm, application/octet-stream",
                },
            )
            response = connection.getresponse()
            if not 200 <= response.status < 300:
                response.read(4096)
                raise VoiceError(f"patient TTS HTTP failure: {response.status}")
            source_rate = _validate_voice_audio_headers(response, expected_rate, explicit)
            resampler = BandlimitedPCMResampler(source_rate, VOICE_MEDIA_RATE)
            read_method = getattr(response, "read1", response.read)
            while True:
                block = read_method(8192)
                if not block:
                    break
                source_bytes += len(block)
                if not probe and len(block) >= 12 and block[:4] == b"RIFF" and block[8:12] == b"WAVE":
                    raise VoiceError("patient TTS unexpectedly returned WAV instead of raw PCM")
                if len(probe) < 12:
                    probe.extend(block)
                    if len(probe) < 12:
                        continue
                    block = bytes(probe)
                    probe.clear()
                    if block[:4] == b"RIFF" and block[8:12] == b"WAVE":
                        raise VoiceError("patient TTS unexpectedly returned WAV instead of raw PCM")
                converted = resampler.feed(block)
                if converted:
                    if first_audio is None:
                        first_audio = time.monotonic()
                    emit(converted)
                    target_bytes += len(converted)
            if probe:
                converted = resampler.feed(bytes(probe))
                if converted:
                    if first_audio is None:
                        first_audio = time.monotonic()
                    emit(converted)
                    target_bytes += len(converted)
            if resampler.remainder:
                raise VoiceError("patient TTS returned misaligned s16le PCM")
            tail = resampler.feed(b"", final=True)
            if tail:
                if first_audio is None:
                    first_audio = time.monotonic()
                emit(tail)
                target_bytes += len(tail)
            if target_bytes == 0:
                raise VoiceError("patient TTS returned no audio")
        finally:
            connection.close()
        finished = time.monotonic()
        return {
            "backend": self.backend,
            "source_rate": expected_rate,
            "target_rate": VOICE_MEDIA_RATE,
            "source_bytes": source_bytes,
            "target_bytes": target_bytes,
            "ttfa_ms": round(((first_audio or finished) - started) * 1000.0, 3),
            "total_ms": round((finished - started) * 1000.0, 3),
        }


@dataclasses.dataclass(frozen=True)
class VoiceVADSettings:
    energy_threshold: int
    preroll_ms: int
    speech_start_ms: int
    speech_end_ms: int
    minimum_utterance_ms: int
    maximum_utterance_ms: int


class EnergyVAD:
    def __init__(self, config: VoiceVADSettings) -> None:
        self.threshold = config.energy_threshold
        self.start_frames = max(1, math.ceil(config.speech_start_ms / VOICE_FRAME_MS))
        self.end_frames = max(1, math.ceil(config.speech_end_ms / VOICE_FRAME_MS))
        self.min_frames = max(1, math.ceil(config.minimum_utterance_ms / VOICE_FRAME_MS))
        self.max_frames = max(1, math.ceil(config.maximum_utterance_ms / VOICE_FRAME_MS))
        self.preroll: deque[bytes] = deque(maxlen=max(1, math.ceil(config.preroll_ms / VOICE_FRAME_MS)))
        self.active = False
        self.speech_run = 0
        self.speech_frames = 0
        self.silence_run = 0
        self.frames: list[bytes] = []
        self.started = False
        self.last_energy = 0
        self.last_peak = 0
        self.last_end_reason = ""
        self.last_frame_count = 0
        self.last_speech_frames = 0
        self.last_silence_frames = 0
        self.last_accepted = False

    @staticmethod
    def levels(frame: bytes) -> tuple[int, int]:
        usable = frame[: len(frame) - len(frame) % 2]
        if not usable:
            return 0, 0
        samples = array.array("h")
        samples.frombytes(usable)
        if sys.byteorder != "little":
            samples.byteswap()
        rms = math.isqrt(sum(int(value) * int(value) for value in samples) // len(samples))
        peak = max(abs(int(value)) for value in samples)
        return rms, peak

    def feed(self, frame: bytes) -> bytes | None:
        self.started = False
        self.last_energy, self.last_peak = self.levels(frame)
        speech = self.last_energy >= self.threshold
        if not self.active:
            self.preroll.append(frame)
            self.speech_run = self.speech_run + 1 if speech else 0
            if self.speech_run >= self.start_frames:
                self.active = True
                self.started = True
                self.frames = list(self.preroll)
                self.preroll.clear()
                self.speech_frames = self.speech_run
                self.silence_run = 0
            return None
        self.frames.append(frame)
        if speech:
            self.speech_frames += 1
        self.silence_run = 0 if speech else self.silence_run + 1
        if len(self.frames) >= self.max_frames or self.silence_run >= self.end_frames:
            result = b"".join(self.frames)
            spoken_frames = self.speech_frames
            self.last_end_reason = "maximum_duration" if len(self.frames) >= self.max_frames else "silence"
            self.last_frame_count = len(self.frames)
            self.last_speech_frames = spoken_frames
            self.last_silence_frames = self.silence_run
            self.last_accepted = spoken_frames >= self.min_frames
            self.reset()
            return result if self.last_accepted else b""
        return None

    def reset(self) -> None:
        self.active = False
        self.speech_run = 0
        self.speech_frames = 0
        self.silence_run = 0
        self.frames = []
        self.preroll.clear()


@dataclasses.dataclass(frozen=True)
class MediaFrame:
    pcm: bytes
    monotonic_ms: float
    wall_time: str


class MediaWebSocketSession:
    """One outbound chan_websocket media connection from Asterisk."""

    def __init__(self, conn: socket.socket, initial: bytes) -> None:
        self.conn = conn
        self.buffer = bytearray(initial)
        self.audio_queue: queue.Queue[MediaFrame | None] = queue.Queue(maxsize=10000)
        # Mirror of inbound media for non-destructive activity detection while
        # patient TTS is playing.  The primary audio_queue remains untouched so
        # listen() can later transcribe the assistant response from its beginning.
        self.activity_queue: queue.Queue[MediaFrame] = queue.Queue(maxsize=10000)
        self.control_queue: queue.Queue[str] = queue.Queue()
        self.control_backlog: deque[str] = deque()
        self.closed = threading.Event()
        self.xon = threading.Event()
        self.xon.set()
        self.send_lock = threading.Lock()
        self.media_remainder = bytearray()
        self.raw_rx = bytearray()
        self.raw_rx_lock = threading.Lock()
        self.raw_rx_frames = 0
        self.raw_rx_first_monotonic_ms: float | None = None
        self.raw_rx_last_monotonic_ms: float | None = None
        self.reader = threading.Thread(target=self._reader_loop, name="kzf-media-ws-reader", daemon=True)
        self.reader.start()

    @staticmethod
    def _frame(opcode: int, payload: bytes) -> bytes:
        first = 0x80 | opcode
        length = len(payload)
        if length < 126:
            header = bytes([first, length])
        elif length <= 65535:
            header = bytes([first, 126]) + struct.pack("!H", length)
        else:
            header = bytes([first, 127]) + struct.pack("!Q", length)
        return header + payload

    def _recv_exact(self, size: int) -> bytes:
        while len(self.buffer) < size:
            block = self.conn.recv(max(4096, size - len(self.buffer)))
            if not block:
                raise EOFError
            self.buffer.extend(block)
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    def _recv_frame(self) -> tuple[int, bytes]:
        fragments = bytearray()
        message_opcode: int | None = None
        while True:
            first, second = self._recv_exact(2)
            final = bool(first & 0x80)
            opcode = first & 0x0F
            if first & 0x70:
                raise VoiceError("Asterisk media WebSocket set reserved bits")
            masked = bool(second & 0x80)
            length = second & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._recv_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._recv_exact(8))[0]
            if length > 2 * 1024 * 1024:
                raise VoiceError("Asterisk media WebSocket frame too large")
            mask = self._recv_exact(4) if masked else b""
            payload = self._recv_exact(length) if length else b""
            if masked:
                payload = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))
            if opcode >= 0x8:
                return opcode, payload
            if opcode in {0x1, 0x2}:
                if message_opcode is not None:
                    raise VoiceError("nested Asterisk media WebSocket fragments")
                message_opcode = opcode
                fragments.extend(payload)
            elif opcode == 0x0:
                if message_opcode is None:
                    raise VoiceError("unexpected Asterisk media WebSocket continuation")
                fragments.extend(payload)
            else:
                raise VoiceError("unsupported Asterisk media WebSocket opcode")
            if final:
                return int(message_opcode), bytes(fragments)

    def _queue_media(self, payload: bytes) -> None:
        self.media_remainder.extend(payload)
        while len(self.media_remainder) >= VOICE_FRAME_BYTES:
            frame = bytes(self.media_remainder[:VOICE_FRAME_BYTES])
            del self.media_remainder[:VOICE_FRAME_BYTES]
            item = MediaFrame(frame, monotonic_ms(), now_iso())
            with self.raw_rx_lock:
                if self.raw_rx_first_monotonic_ms is None:
                    self.raw_rx_first_monotonic_ms = item.monotonic_ms
                self.raw_rx_last_monotonic_ms = item.monotonic_ms
                self.raw_rx.extend(frame)
                self.raw_rx_frames += 1
            try:
                self.audio_queue.put_nowait(item)
            except queue.Full:
                with contextlib.suppress(queue.Empty):
                    self.audio_queue.get_nowait()
                self.audio_queue.put_nowait(item)
            try:
                self.activity_queue.put_nowait(item)
            except queue.Full:
                with contextlib.suppress(queue.Empty):
                    self.activity_queue.get_nowait()
                self.activity_queue.put_nowait(item)

    def _reader_loop(self) -> None:
        try:
            while True:
                opcode, payload = self._recv_frame()
                if opcode == 0x8:
                    break
                if opcode == 0x9:
                    with self.send_lock:
                        self.conn.sendall(self._frame(0xA, payload))
                    continue
                if opcode == 0xA:
                    continue
                if opcode == 0x2:
                    self._queue_media(payload)
                    continue
                if opcode == 0x1:
                    text = payload.decode("utf-8", errors="replace").strip()
                    # Voice calls use chan_websocket JSON control format in v1.2.5.
                    # Normalize incoming JSON events back to the legacy one-line
                    # representation so the existing wait_control()/MEDIA_START
                    # parsing remains regression-compatible.
                    normalized = text
                    if text.startswith("{"):
                        try:
                            obj = json.loads(text)
                        except json.JSONDecodeError:
                            obj = None
                        if isinstance(obj, dict) and isinstance(obj.get("event"), str):
                            parts = [str(obj["event"])]
                            for key, value in obj.items():
                                if key == "event" or isinstance(value, (dict, list)):
                                    continue
                                if isinstance(value, bool):
                                    rendered = "true" if value else "false"
                                elif value is None:
                                    rendered = ""
                                else:
                                    rendered = str(value)
                                parts.append(f"{key}:{rendered}")
                            normalized = " ".join(parts)
                    if normalized.startswith("MEDIA_XOFF"):
                        self.xon.clear()
                    elif normalized.startswith("MEDIA_XON"):
                        self.xon.set()
                    self.control_queue.put(normalized)
        except (EOFError, OSError, VoiceError):
            pass
        finally:
            self.closed.set()
            with contextlib.suppress(queue.Full):
                self.audio_queue.put_nowait(None)

    def send_text(self, text: str) -> None:
        if self.closed.is_set():
            raise VoiceError("media WebSocket is closed")
        # chan_websocket SET_MEDIA_DIRECTION is only available with JSON control
        # messages.  Keep callers using the compact legacy command strings and
        # serialize them here.
        command, _, argument = text.partition(" ")
        payload: dict[str, Any] = {"command": command}
        argument = argument.strip()
        if command in {"STOP_MEDIA_BUFFERING", "MARK_MEDIA"} and argument:
            payload["correlation_id"] = argument
        elif command == "SET_MEDIA_DIRECTION":
            if argument not in {"in", "out", "both"}:
                raise VoiceError(f"invalid media direction {argument!r}")
            payload["direction"] = argument
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        with self.send_lock:
            self.conn.sendall(self._frame(0x1, data))

    def set_media_direction(self, direction: str) -> None:
        self.send_text(f"SET_MEDIA_DIRECTION {direction}")

    def send_binary(self, payload: bytes) -> None:
        if len(payload) > 65000:
            for offset in range(0, len(payload), 64000):
                self.send_binary(payload[offset : offset + 64000])
            return
        if not self.xon.wait(timeout=30.0):
            raise VoiceError("Asterisk media queue remained in XOFF state")
        if self.closed.is_set():
            raise VoiceError("media WebSocket is closed")
        with self.send_lock:
            self.conn.sendall(self._frame(0x2, payload))

    def wait_control(self, prefix: str, timeout: float, correlation_id: str | None = None) -> str:
        deadline = time.monotonic() + timeout
        while True:
            for index, value in enumerate(tuple(self.control_backlog)):
                if value.startswith(prefix) and (correlation_id is None or correlation_id in value):
                    del self.control_backlog[index]
                    return value
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise VoiceError(f"timeout waiting for Asterisk media event {prefix}")
            try:
                value = self.control_queue.get(timeout=min(remaining, 0.5))
            except queue.Empty:
                if self.closed.is_set():
                    raise VoiceError(f"media WebSocket closed while waiting for {prefix}")
                continue
            if value.startswith(prefix) and (correlation_id is None or correlation_id in value):
                return value
            self.control_backlog.append(value)

    def discard_pending_activity(self) -> int:
        count = 0
        while True:
            try:
                self.activity_queue.get_nowait()
            except queue.Empty:
                break
            count += 1
        return count

    def discard_pending_audio(self) -> int:
        count = 0
        terminal = False
        while True:
            try:
                value = self.audio_queue.get_nowait()
            except queue.Empty:
                break
            if value is None:
                terminal = True
            else:
                count += 1
        if terminal:
            with contextlib.suppress(queue.Full):
                self.audio_queue.put_nowait(None)
        return count

    def next_utterance(
        self,
        vad_settings: VoiceVADSettings,
        start_timeout: float,
        *,
        not_before_monotonic_ms: float | None = None,
        on_speech_start: Callable[[], None] | None = None,
    ) -> tuple[bytes, dict[str, Any]] | None:
        vad = EnergyVAD(vad_settings)
        deadline = time.monotonic() + start_timeout
        detected_start: MediaFrame | None = None
        last_frame: MediaFrame | None = None
        while True:
            remaining = deadline - time.monotonic()
            if not vad.active and remaining <= 0:
                return None
            timeout = 1.0 if vad.active else max(0.05, min(1.0, remaining))
            try:
                item = self.audio_queue.get(timeout=timeout)
            except queue.Empty:
                if self.closed.is_set():
                    if vad.active and vad.frames:
                        pcm = b"".join(vad.frames)
                        return pcm, {
                            "start_detected_at": detected_start.wall_time if detected_start else None,
                            "start_detected_monotonic_ms": detected_start.monotonic_ms if detected_start else None,
                            "end_detected_at": last_frame.wall_time if last_frame else now_iso(),
                            "end_detected_monotonic_ms": last_frame.monotonic_ms if last_frame else monotonic_ms(),
                            "end_reason": "hangup",
                        }
                    return None
                continue
            if item is None:
                if vad.active and vad.frames:
                    pcm = b"".join(vad.frames)
                    return pcm, {
                        "start_detected_at": detected_start.wall_time if detected_start else None,
                        "start_detected_monotonic_ms": detected_start.monotonic_ms if detected_start else None,
                        "end_detected_at": last_frame.wall_time if last_frame else now_iso(),
                        "end_detected_monotonic_ms": last_frame.monotonic_ms if last_frame else monotonic_ms(),
                        "end_reason": "hangup",
                    }
                return None
            if (
                not_before_monotonic_ms is not None
                and item.monotonic_ms <= not_before_monotonic_ms
            ):
                # Strict half-duplex: ignore every inbound frame that arrived
                # before the caller finished its own TX phase.  We still keep
                # those bytes in the continuous raw diagnostic recording.
                continue
            last_frame = item
            result = vad.feed(item.pcm)
            if vad.started:
                detected_start = item
                if on_speech_start is not None:
                    callback = on_speech_start
                    on_speech_start = None
                    callback()
            if result is not None:
                if not result:
                    detected_start = None
                    deadline = time.monotonic() + start_timeout
                    continue
                trailing_ms = vad.last_silence_frames * VOICE_FRAME_MS
                estimated_start_mono = (
                    (detected_start.monotonic_ms - (vad.start_frames - 1) * VOICE_FRAME_MS)
                    if detected_start is not None
                    else None
                )
                estimated_end_mono = item.monotonic_ms - trailing_ms
                return result, {
                    "start_detected_at": detected_start.wall_time if detected_start else None,
                    "start_detected_monotonic_ms": detected_start.monotonic_ms if detected_start else None,
                    "estimated_speech_start_monotonic_ms": estimated_start_mono,
                    "end_detected_at": item.wall_time,
                    "end_detected_monotonic_ms": item.monotonic_ms,
                    "estimated_speech_end_monotonic_ms": estimated_end_mono,
                    "end_reason": vad.last_end_reason,
                    "utterance_ms": vad.last_frame_count * VOICE_FRAME_MS,
                    "speech_ms": vad.last_speech_frames * VOICE_FRAME_MS,
                    "trailing_silence_ms": trailing_ms,
                    "rms_last": vad.last_energy,
                    "peak_last": vad.last_peak,
                }

    def snapshot_raw_rx(self) -> tuple[bytes, dict[str, Any]]:
        with self.raw_rx_lock:
            pcm = bytes(self.raw_rx)
            frames = self.raw_rx_frames
            first = self.raw_rx_first_monotonic_ms
            last = self.raw_rx_last_monotonic_ms
        return pcm, {
            "frames": frames,
            "bytes": len(pcm),
            "duration_ms": round(len(pcm) / (VOICE_MEDIA_RATE * VOICE_PCM_WIDTH) * 1000.0, 3),
            "first_monotonic_ms": first,
            "last_monotonic_ms": last,
        }

    def close(self) -> None:
        with contextlib.suppress(OSError):
            self.conn.shutdown(socket.SHUT_RDWR)
        with contextlib.suppress(OSError):
            self.conn.close()
        self.closed.set()


class MediaWebSocketServer:
    def __init__(self, bind: str, port: int) -> None:
        self.bind = bind
        self.port = port
        self.listener: socket.socket | None = None
        self.thread: threading.Thread | None = None
        self.session: MediaWebSocketSession | None = None
        self.ready = threading.Event()
        self.connected = threading.Event()
        self.error: BaseException | None = None

    def start(self) -> None:
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((self.bind, self.port))
        listener.listen(1)
        listener.settimeout(1.0)
        self.listener = listener
        self.thread = threading.Thread(target=self._serve, name="kzf-media-ws-server", daemon=True)
        self.thread.start()
        self.ready.wait(2.0)
        if self.error is not None:
            raise VoiceError(f"cannot start media WebSocket server: {self.error}")

    def _serve(self) -> None:
        self.ready.set()
        try:
            assert self.listener is not None
            while True:
                try:
                    conn, _address = self.listener.accept()
                    break
                except socket.timeout:
                    if self.listener.fileno() < 0:
                        return
            conn.settimeout(None)
            header = bytearray()
            while b"\r\n\r\n" not in header:
                block = conn.recv(4096)
                if not block:
                    raise VoiceError("media WebSocket closed during HTTP upgrade")
                header.extend(block)
                if len(header) > 65536:
                    raise VoiceError("media WebSocket HTTP header too large")
            end = header.index(b"\r\n\r\n") + 4
            raw_header = bytes(header[:end])
            initial = bytes(header[end:])
            lines = raw_header.decode("iso-8859-1").split("\r\n")
            if not lines or not lines[0].startswith("GET "):
                raise VoiceError("invalid media WebSocket HTTP request")
            headers = {
                name.strip().lower(): value.strip()
                for line in lines[1:]
                if ":" in line
                for name, value in [line.split(":", 1)]
            }
            key = headers.get("sec-websocket-key")
            protocols = {item.strip() for item in headers.get("sec-websocket-protocol", "").split(",") if item.strip()}
            if not key or "websocket" not in headers.get("upgrade", "").lower():
                raise VoiceError("invalid media WebSocket upgrade headers")
            if protocols and "media" not in protocols:
                raise VoiceError("Asterisk did not request the media WebSocket subprotocol")
            accept = base64.b64encode(
                hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()
            ).decode("ascii")
            response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n"
                + ("Sec-WebSocket-Protocol: media\r\n" if "media" in protocols else "")
                + "\r\n"
            ).encode("ascii")
            conn.sendall(response)
            self.session = MediaWebSocketSession(conn, initial)
            self.connected.set()
        except BaseException as exc:
            self.error = exc
            self.connected.set()

    def wait_session(self, timeout: float) -> MediaWebSocketSession:
        if not self.connected.wait(timeout):
            raise VoiceError(f"no Asterisk media WebSocket connection within {timeout:.1f}s")
        if self.error is not None:
            raise VoiceError(f"media WebSocket server failed: {self.error}")
        if self.session is None:
            raise VoiceError("media WebSocket connected without a session")
        return self.session

    def close(self) -> None:
        if self.session is not None:
            self.session.close()
        if self.listener is not None:
            with contextlib.suppress(OSError):
                self.listener.close()
            self.listener = None


def parse_media_start(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    parts = text.split()
    if not parts or parts[0] != "MEDIA_START":
        return result
    for token in parts[1:]:
        if ":" in token:
            key, value = token.split(":", 1)
            result[key] = value
    return result


class PatientMediaInterrupted(RuntimeError):
    """Internal control flow: target assistant started speaking during patient TTS."""


@dataclasses.dataclass(frozen=True)
class VoiceSettings:
    target_number: str
    asterisk_endpoint: str
    ws_connection: str
    media_bind: str
    media_port: int
    answer_timeout: float
    greeting_wait: float
    response_timeout: float
    dial_timeout: int
    listen_only_seconds: float
    wakeup_text: str
    wakeup_barge_ms: int
    comfort_noise_rms: int
    comfort_noise_seed: int
    reference_test: bool
    reference_seconds: float
    reference_text: str
    reference_wav: Path | None
    asr_url: str
    asr_timeout: float
    tts: PatientTTSClient
    vad: VoiceVADSettings


class AsteriskVoiceCall:
    def __init__(self, settings: VoiceSettings, recorder: EventRecorder) -> None:
        self.settings = settings
        self.recorder = recorder
        self.server = MediaWebSocketServer(settings.media_bind, settings.media_port)
        self.session: MediaWebSocketSession | None = None
        self.originate: subprocess.Popen[str] | None = None
        # Strict half-duplex: inbound frames that arrived while the synthetic
        # patient was transmitting are never treated as the next assistant turn.
        self.rx_accept_after_monotonic_ms: float | None = None

    def start(self) -> None:
        if shutil.which("asterisk") is None:
            raise VoiceError("asterisk CLI was not found")
        self.server.start()
        # IMPORTANT: create the media WebSocket leg first, then dial the target.
        # MEDIA_START only proves the WebSocket channel exists; it does NOT mean
        # the PJSIP destination has answered.  A Dial() U-handler runs only after
        # the called party answers and before the bridge is formed.  v1.1.8 uses
        # that handler to set one global Asterisk flag.  Voice mode is deliberately
        # single-call only, so the global is deterministic and is reset before and
        # after every call.  This avoids relying on MASTER_CHANNEL()/channel-variable
        # visibility in `core show channel`, which proved unreliable in v1.1.6.
        self._prepare_answer_marker()
        command = (
            f"channel originate WebSocket/{self.settings.ws_connection}/c(slin16)f(json) "
            f"application Dial PJSIP/{self.settings.target_number}@{self.settings.asterisk_endpoint},"
            f"{self.settings.dial_timeout},U(kienzlefon-testsuite-answer)"
        )
        self.recorder.add(
            "call_originate_start",
            monotonic_ms=monotonic_ms(),
            target_number=self.settings.target_number,
            asterisk_endpoint=self.settings.asterisk_endpoint,
            websocket_connection=self.settings.ws_connection,
        )
        self.originate = subprocess.Popen(
            ["asterisk", "-rx", command],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            self.session = self.server.wait_session(self.settings.answer_timeout)
        except BaseException:
            output = ""
            if self.originate.poll() is not None and self.originate.stdout is not None:
                output = self.originate.stdout.read().strip()
            if output:
                self.recorder.add("asterisk_originate_output", output=output)
            raise
        media_start = self.session.wait_control("MEDIA_START", 5.0)
        details = parse_media_start(media_start)
        self.recorder.add(
            "media_connected",
            monotonic_ms=monotonic_ms(),
            media_start=media_start,
            media=details,
            note="WebSocket leg ready before target Dial()",
        )
        if details.get("format") and details.get("format") != "slin16":
            raise VoiceError(f"Asterisk media format is {details.get('format')}, expected slin16")
        if details.get("optimal_frame_size") and details.get("optimal_frame_size") != str(VOICE_FRAME_BYTES):
            raise VoiceError(
                f"Asterisk optimal frame size is {details.get('optimal_frame_size')}, expected {VOICE_FRAME_BYTES}"
            )
        channel_name = details.get("channel", "")
        if not re.fullmatch(r"[A-Za-z0-9_./:@+-]{1,200}", channel_name):
            raise VoiceError("MEDIA_START did not provide a safe WebSocket channel name")
        if self.settings.reference_test:
            # True receive-only before the remote side answers: this disables
            # chan_websocket's app->Asterisk media timer/synthetic silence.
            self.set_media_direction("in", reason="reference_pre_answer_rx_only")
        self._wait_target_answer(channel_name)

    @staticmethod
    def _asterisk_cli(command: str, timeout: float = 3.0) -> str:
        result = subprocess.run(
            ["asterisk", "-rx", command],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = ((result.stdout or "") + (result.stderr or "")).strip()
        if result.returncode != 0:
            raise VoiceError(f"Asterisk CLI failed for {command!r}: {output or result.returncode}")
        return output

    def _prepare_answer_marker(self) -> None:
        """Validate/reset the v1.1.8 post-answer global marker."""
        show = self._asterisk_cli("dialplan show kienzlefon-testsuite-answer")
        if "kienzlefon-testsuite-answer" not in show or "KZF_TESTSUITE_ANSWERED" not in show:
            raise VoiceError(
                "Asterisk context kienzlefon-testsuite-answer is missing or outdated; "
                "install the v1.1.8 GLOBAL(KZF_TESTSUITE_ANSWERED) setup block"
            )
        self._asterisk_cli("dialplan set global KZF_TESTSUITE_ANSWERED 0")
        globals_now = self._asterisk_cli("dialplan show globals")
        if not re.search(r"^\s*KZF_TESTSUITE_ANSWERED=0\s*$", globals_now, re.MULTILINE):
            raise VoiceError("could not reset Asterisk global KZF_TESTSUITE_ANSWERED=0")
        self.recorder.add("target_answer_marker_reset", monotonic_ms=monotonic_ms())

    def _wait_target_answer(self, channel_name: str) -> None:
        """Wait for Dial(U()) to mark that the external target really answered."""
        deadline = time.monotonic() + self.settings.answer_timeout
        last_globals = ""
        while time.monotonic() < deadline:
            globals_now = self._asterisk_cli("dialplan show globals")
            last_globals = globals_now
            if re.search(r"^\s*KZF_TESTSUITE_ANSWERED=1\s*$", globals_now, re.MULTILINE):
                self.recorder.add(
                    "target_answered",
                    monotonic_ms=monotonic_ms(),
                    websocket_channel=channel_name,
                    marker="GLOBAL(KZF_TESTSUITE_ANSWERED)=1",
                )
                # Early media/ringback can have substantial energy and must not
                # be mistaken for target speech after the real answer.
                if self.session is not None:
                    self.session.discard_pending_audio()
                    self.session.discard_pending_activity()
                return
            # `asterisk -rx "channel originate ..."` is only the local CLI
            # control process.  It normally exits as soon as Asterisk has accepted
            # the originate request while the actual Asterisk channels keep running.
            # Therefore Popen.poll() MUST NOT be used as call-liveness evidence.
            # The media WebSocket closing, however, is a real channel-lifecycle
            # signal and may safely terminate the answer wait.
            if self.session is not None and self.session.closed.is_set():
                extra = ""
                if (
                    self.originate is not None
                    and self.originate.poll() is not None
                    and self.originate.stdout is not None
                ):
                    with contextlib.suppress(Exception):
                        extra = self.originate.stdout.read().strip()
                if extra:
                    self.recorder.add("asterisk_originate_output", output=extra)
                raise VoiceError("media WebSocket closed before target answer marker")
            time.sleep(0.10)
        detail = f"; globals: {last_globals[-500:]}" if last_globals else ""
        raise VoiceError(f"timeout waiting for target answer ({self.settings.answer_timeout:.1f}s){detail}")

    def save_continuous_rx(self, audio_path: Path) -> dict[str, Any]:
        if self.session is None:
            return {"frames": 0, "bytes": 0, "duration_ms": 0.0}
        pcm, meta = self.session.snapshot_raw_rx()
        if pcm:
            write_pcm_wav(audio_path, pcm)
        self.recorder.add(
            "assistant_rx_continuous",
            monotonic_ms=monotonic_ms(),
            path=str(audio_path.name),
            **meta,
        )
        return meta

    def listen_only_diagnostic(self, seconds: float, audio_path: Path) -> tuple[str, dict[str, Any]]:
        if self.session is None:
            raise VoiceError("voice call is not connected")
        self.recorder.add(
            "voice_listen_only_start",
            monotonic_ms=monotonic_ms(),
            seconds=seconds,
        )
        start_pcm, _ = self.session.snapshot_raw_rx()
        start_offset = len(start_pcm)
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self.session.closed.is_set():
                break
            time.sleep(min(0.05, max(0.0, deadline - time.monotonic())))
        all_pcm, all_meta = self.session.snapshot_raw_rx()
        pcm = all_pcm[start_offset:]
        if pcm:
            write_pcm_wav(audio_path, pcm)
        rms, peak = EnergyVAD.levels(pcm) if pcm else (0, 0)
        transcript = ""
        asr_meta: dict[str, Any] = {}
        if pcm:
            transcript, asr_meta = observer_asr_transcribe(
                self.settings.asr_url, self.settings.asr_timeout, pcm
            )
        meta = {
            "requested_seconds": seconds,
            "captured_bytes": len(pcm),
            "captured_duration_ms": round(len(pcm) / (VOICE_MEDIA_RATE * VOICE_PCM_WIDTH) * 1000.0, 3),
            "rms": rms,
            "peak": peak,
            "session_closed": self.session.closed.is_set(),
            **asr_meta,
        }
        self.recorder.add(
            "voice_listen_only_end",
            monotonic_ms=monotonic_ms(),
            text=transcript,
            **meta,
        )
        return transcript, meta

    @staticmethod
    def _comfort_noise_frame(rms: int, state: int) -> tuple[bytes, int]:
        """Return one deterministic 20-ms slin16 room-tone frame.

        The signal is intentionally tiny, zero-mean pseudo-random noise rather
        than digital zero.  It simulates the non-zero microphone floor of a real
        handset without being intended to count as speech.
        """
        if rms <= 0:
            return b"\x00" * VOICE_FRAME_BYTES, state
        # Uniform noise with peak chosen so RMS is approximately the requested
        # value (RMS_uniform ~= peak/sqrt(3)).  Use a tiny local LCG so the runner
        # needs no extra dependency and the waveform is reproducible.
        peak = max(1, min(12000, int(round(rms * math.sqrt(3.0)))))
        samples = array.array("h")
        x = state & 0x7FFFFFFF
        for _ in range(VOICE_FRAME_BYTES // VOICE_PCM_WIDTH):
            x = (1103515245 * x + 12345) & 0x7FFFFFFF
            value = (x % (2 * peak + 1)) - peak
            samples.append(value)
        if sys.byteorder != "little":
            samples.byteswap()
        return samples.tobytes(), x

    def _start_comfort_noise(
        self,
        *,
        turn: int,
        purpose: str,
    ) -> tuple[threading.Event, threading.Thread | None, list[str]]:
        """Pace quiet room tone toward Asterisk while the patient is silent."""
        if self.session is None:
            raise VoiceError("voice call is not connected")
        stop = threading.Event()
        errors: list[str] = []
        rms = int(self.settings.comfort_noise_rms)
        if rms <= 0:
            self.recorder.add(
                "comfort_noise_disabled",
                turn=turn,
                purpose=purpose,
                monotonic_ms=monotonic_ms(),
            )
            return stop, None, errors

        self.recorder.add(
            "comfort_noise_start",
            turn=turn,
            purpose=purpose,
            monotonic_ms=monotonic_ms(),
            rms_target=rms,
            frame_ms=VOICE_FRAME_MS,
        )

        def pump() -> None:
            state = (self.settings.comfort_noise_seed + turn * 7919) & 0x7FFFFFFF
            next_send = time.monotonic()
            sent = 0
            try:
                while not stop.is_set():
                    frame, state = self._comfort_noise_frame(rms, state)
                    self.session.send_binary(frame)
                    sent += 1
                    next_send += VOICE_FRAME_MS / 1000.0
                    delay = next_send - time.monotonic()
                    if delay > 0:
                        stop.wait(delay)
                    elif delay < -0.2:
                        # Avoid catch-up bursts after scheduler stalls.
                        next_send = time.monotonic()
            except BaseException as exc:
                if not stop.is_set():
                    errors.append(f"{type(exc).__name__}: {exc}")
            finally:
                self.recorder.add(
                    "comfort_noise_thread_end",
                    turn=turn,
                    purpose=purpose,
                    monotonic_ms=monotonic_ms(),
                    frames_sent=sent,
                    error=errors[-1] if errors else None,
                )

        thread = threading.Thread(
            target=pump,
            name=f"kzf-comfort-noise-{turn}",
            daemon=True,
        )
        thread.start()
        return stop, thread, errors

    def _stop_comfort_noise(
        self,
        stop: threading.Event,
        thread: threading.Thread | None,
        errors: list[str],
        *,
        turn: int,
        purpose: str,
        reason: str,
    ) -> None:
        stop.set()
        if thread is not None:
            thread.join(timeout=1.0)
            if thread.is_alive():
                errors.append("comfort-noise thread did not stop within 1s")
        self.recorder.add(
            "comfort_noise_stop",
            turn=turn,
            purpose=purpose,
            reason=reason,
            monotonic_ms=monotonic_ms(),
            error=errors[-1] if errors else None,
        )
        if errors:
            raise VoiceError(errors[-1])

    def capture_fixed_rx_window(
        self,
        seconds: float,
        audio_path: Path,
        *,
        label: str,
    ) -> tuple[str, dict[str, Any]]:
        """Capture one deterministic RX-only window without VAD/turn control.

        No application media is transmitted.  The complete binary media received
        from Asterisk during the wall-clock window is written verbatim as slin16
        WAV and only afterwards submitted once to the observer ASR.  ASR never
        changes timing or control flow in this diagnostic mode.
        """
        if self.session is None:
            raise VoiceError("voice call is not connected")
        self.session.discard_pending_audio()
        self.session.discard_pending_activity()
        before_pcm, _ = self.session.snapshot_raw_rx()
        start_offset = len(before_pcm)
        started = monotonic_ms()
        self.recorder.add(
            "reference_rx_window_start",
            label=label,
            monotonic_ms=started,
            seconds=seconds,
            transmitted_media=False,
        )
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self.session.closed.is_set():
                break
            time.sleep(min(0.05, max(0.0, deadline - time.monotonic())))
        after_pcm, _ = self.session.snapshot_raw_rx()
        pcm = after_pcm[start_offset:]
        if pcm:
            write_pcm_wav(audio_path, pcm)
        rms, peak = EnergyVAD.levels(pcm) if pcm else (0, 0)
        transcript = ""
        asr_meta: dict[str, Any] = {}
        if pcm:
            transcript, asr_meta = observer_asr_transcribe(
                self.settings.asr_url,
                self.settings.asr_timeout,
                pcm,
            )
        ended = monotonic_ms()
        meta = {
            "label": label,
            "requested_seconds": seconds,
            "captured_bytes": len(pcm),
            "captured_duration_ms": round(
                len(pcm) / (VOICE_MEDIA_RATE * VOICE_PCM_WIDTH) * 1000.0, 3
            ),
            "rms": rms,
            "peak": peak,
            "session_closed": self.session.closed.is_set(),
            "window_start_monotonic_ms": started,
            "window_end_monotonic_ms": ended,
            **asr_meta,
        }
        self.recorder.add(
            "reference_rx_window_end",
            monotonic_ms=ended,
            text=transcript,
            path=audio_path.name,
            **meta,
        )
        return transcript, meta

    def set_media_direction(self, direction: str, *, reason: str) -> None:
        """Switch chan_websocket media direction from the application's view.

        "in" means Asterisk -> application only.  In current chan_websocket this
        also closes the transmit-side 20-ms channel timer, so Asterisk does not
        synthesize silence into the bridged PJSIP leg while Sophia is speaking.
        """
        if self.session is None:
            raise VoiceError("voice call is not connected")
        self.session.set_media_direction(direction)
        self.recorder.add(
            "media_direction_set",
            monotonic_ms=monotonic_ms(),
            direction=direction,
            reason=reason,
        )
        # Control commands are processed asynchronously by Asterisk.  A tiny
        # guard interval is diagnostic only; it is not used for turn detection.
        time.sleep(0.05)

    def play_prepared_pcm(
        self,
        pcm: bytes,
        audio_path: Path,
        *,
        label: str,
    ) -> dict[str, Any]:
        """Play one already prepared 16-kHz mono S16LE WAV payload.

        This diagnostic path contains no VAD, no barge-in, no comfort noise and
        no Python pacing.  The full payload is bulk-buffered into chan_websocket;
        Asterisk owns framing/timing and QUEUE_DRAINED marks the end of playout.
        """
        if self.session is None:
            raise VoiceError("voice call is not connected")
        if not pcm:
            raise VoiceError("reference WAV contains no PCM")
        if len(pcm) % VOICE_PCM_WIDTH:
            raise VoiceError("reference WAV PCM is not aligned to 16-bit samples")
        write_pcm_wav(audio_path, pcm)
        self.session.discard_pending_activity()
        self.set_media_direction("both", reason=f"{label}_playback")
        corr = f"reference-{uuid.uuid4().hex[:8]}"
        started = monotonic_ms()
        self.recorder.add(
            "reference_wav_playback_start",
            label=label,
            monotonic_ms=started,
            audio_bytes=len(pcm),
            duration_ms=round(len(pcm) / (VOICE_MEDIA_RATE * VOICE_PCM_WIDTH) * 1000.0, 3),
            timing_owner="asterisk_chan_websocket",
            vad_control=False,
            barge_in=False,
        )
        self.session.send_text("START_MEDIA_BUFFERING")
        for offset in range(0, len(pcm), 64000):
            self.session.send_binary(pcm[offset : offset + 64000])
        self.session.send_text(f"STOP_MEDIA_BUFFERING {corr}")
        self.session.send_text("REPORT_QUEUE_DRAINED")
        buffering_event = self.session.wait_control(
            "MEDIA_BUFFERING_COMPLETED", max(10.0, self.settings.response_timeout), corr
        )
        queue_event = self.session.wait_control(
            "QUEUE_DRAINED", max(5.0, self.settings.response_timeout)
        )
        # Enter true RX-only mode immediately after the last queued frame.  In
        # chan_websocket this closes the transmit timer instead of generating
        # synthetic silence every 20 ms.
        self.set_media_direction("in", reason=f"{label}_playback_complete")
        ended = monotonic_ms()
        self.rx_accept_after_monotonic_ms = ended
        self.session.discard_pending_activity()
        self.recorder.add(
            "reference_wav_playback_end",
            label=label,
            monotonic_ms=ended,
            audio_bytes=len(pcm),
            buffering_event=buffering_event,
            queue_event=queue_event,
            timing_owner="asterisk_chan_websocket",
        )
        return {
            "audio_bytes": len(pcm),
            "duration_ms": round(len(pcm) / (VOICE_MEDIA_RATE * VOICE_PCM_WIDTH) * 1000.0, 3),
            "audio_start_monotonic_ms": started,
            "audio_end_monotonic_ms": ended,
        }

    def speak(
        self,
        text: str,
        turn: int,
        audio_path: Path,
        *,
        barge_start_ms: int | None = None,
        purpose: str = "scenario",
    ) -> dict[str, Any]:
        """Play one complete patient turn using Asterisk-timed bulk media.

        The complete TTS utterance is generated before playback.  It is then
        queued to chan_websocket as bulk media as fast as flow control permits.
        chan_websocket performs the 20-ms framing and timing.  The application
        deliberately does NOT pace 640-byte frames with time.sleep(); scheduler
        jitter in that pattern caused audible gaps because chan_websocket inserts
        silence whenever the next application packet arrives late.

        Speech remains strict half-duplex: no receive-side/barge-in decision is
        made while the patient turn is being queued or played.
        """
        if self.session is None:
            raise VoiceError("voice call is not connected")

        generated_pcm = bytearray()
        self.recorder.add(
            "patient_tts_start",
            turn=turn,
            monotonic_ms=monotonic_ms(),
            backend=self.settings.tts.backend,
            playback_mode="asterisk_timed_bulk",
            purpose=purpose,
        )

        def collect(block: bytes) -> None:
            generated_pcm.extend(block)

        tts_meta = self.settings.tts.stream(text, collect)
        self.recorder.add(
            "patient_tts_end",
            turn=turn,
            monotonic_ms=monotonic_ms(),
            generated_audio_bytes=len(generated_pcm),
            playback_mode="asterisk_timed_bulk",
            purpose=purpose,
            **tts_meta,
        )
        if not generated_pcm:
            raise VoiceError("patient TTS produced no PCM")

        # Ignore any inbound media/activity that belongs to the preceding RX turn.
        self.session.discard_pending_activity()

        corr = f"patient-{turn}-{uuid.uuid4().hex[:8]}"
        first_queued = monotonic_ms()
        self.recorder.add(
            "half_duplex_tx_enter",
            turn=turn,
            monotonic_ms=first_queued,
            purpose=purpose,
            generated_frames=math.ceil(len(generated_pcm) / VOICE_FRAME_BYTES),
            timing_owner="asterisk_chan_websocket",
        )
        self.recorder.add(
            "patient_audio_start",
            turn=turn,
            monotonic_ms=first_queued,
            playback_mode="asterisk_timed_bulk",
            purpose=purpose,
            note="media queued; chan_websocket owns playout timing",
        )

        # START_MEDIA_BUFFERING lets Asterisk join arbitrary binary message sizes
        # into complete codec frames.  Send quickly; do not attempt 20-ms pacing in
        # Python.  64,000 bytes is below WebSocket's 65,500-byte limit and equals
        # 100 optimal 640-byte slin16 frames when possible.
        self.session.send_text("START_MEDIA_BUFFERING")
        queued_bytes = 0
        for offset in range(0, len(generated_pcm), 64000):
            block = bytes(generated_pcm[offset : offset + 64000])
            self.session.send_binary(block)
            queued_bytes += len(block)

        self.session.send_text(f"STOP_MEDIA_BUFFERING {corr}")
        self.session.send_text("REPORT_QUEUE_DRAINED")

        # MEDIA_BUFFERING_COMPLETED is emitted when the last bulk-media frame has
        # been sent to the Asterisk core.  QUEUE_DRAINED confirms no queued media
        # remains before RX ownership is restored.
        buffering_event = self.session.wait_control(
            "MEDIA_BUFFERING_COMPLETED", max(10.0, self.settings.response_timeout), corr
        )
        queue_event = self.session.wait_control(
            "QUEUE_DRAINED", max(5.0, self.settings.response_timeout)
        )
        ended = monotonic_ms()
        self.rx_accept_after_monotonic_ms = ended
        self.session.discard_pending_activity()

        self.recorder.add(
            "patient_audio_end",
            turn=turn,
            monotonic_ms=ended,
            buffering_event=buffering_event,
            queue_event=queue_event,
            generated_audio_bytes=len(generated_pcm),
            audio_bytes=len(generated_pcm),
            queued_audio_bytes=queued_bytes,
            generated_frames=math.ceil(len(generated_pcm) / VOICE_FRAME_BYTES),
            interrupted=False,
            playback_mode="asterisk_timed_bulk",
            purpose=purpose,
            timing_owner="asterisk_chan_websocket",
        )
        self.recorder.add(
            "half_duplex_rx_enter",
            turn=turn,
            monotonic_ms=ended,
            purpose=purpose,
            rx_accept_after_monotonic_ms=ended,
        )
        write_pcm_wav(audio_path, bytes(generated_pcm))
        return {
            **tts_meta,
            "playback_mode": "asterisk_timed_bulk",
            "purpose": purpose,
            "generated_audio_bytes": len(generated_pcm),
            "played_audio_bytes": len(generated_pcm),
            "queued_audio_bytes": queued_bytes,
            "generated_frames": math.ceil(len(generated_pcm) / VOICE_FRAME_BYTES),
            "audio_start_monotonic_ms": first_queued,
            "audio_end_monotonic_ms": ended,
            "interrupted": False,
            "barge_in": None,
            "timing_owner": "asterisk_chan_websocket",
        }

    def listen(self, turn: int, audio_path: Path, start_timeout: float) -> tuple[str, dict[str, Any]] | None:
        """Listen for one complete target turn in strict RX-only half-duplex.

        No comfort noise, wake-up media or other application audio is transmitted
        during this phase.  Incoming Asterisk media is only captured, segmented
        and sent to the observer ASR.
        """
        if self.session is None:
            raise VoiceError("voice call is not connected")
        deadline = time.monotonic() + start_timeout
        self.recorder.add(
            "half_duplex_rx_listen",
            turn=turn,
            monotonic_ms=monotonic_ms(),
            purpose="initial_greeting" if turn == 0 else "assistant_turn",
            transmitted_media=False,
        )
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            utterance = self.session.next_utterance(
                self.settings.vad,
                remaining,
                not_before_monotonic_ms=self.rx_accept_after_monotonic_ms,
            )
            if utterance is None:
                return None
            pcm, media_meta = utterance
            if not pcm:
                continue
            self.recorder.add("assistant_audio_start", turn=turn, **media_meta)
            write_pcm_wav(audio_path, pcm)
            self.recorder.add(
                "observer_asr_start",
                turn=turn,
                monotonic_ms=monotonic_ms(),
                audio_bytes=len(pcm),
            )
            transcript, asr_meta = observer_asr_transcribe(
                self.settings.asr_url,
                self.settings.asr_timeout,
                pcm,
            )
            if not transcript:
                self.recorder.add(
                    "observer_asr_empty",
                    turn=turn,
                    monotonic_ms=monotonic_ms(),
                    **asr_meta,
                )
                continue
            self.recorder.add(
                "observer_asr_final",
                turn=turn,
                monotonic_ms=monotonic_ms(),
                text=transcript,
                **asr_meta,
            )
            self.recorder.add(
                "assistant_audio_end",
                turn=turn,
                monotonic_ms=media_meta.get("end_detected_monotonic_ms"),
                **media_meta,
            )
            return transcript, {**media_meta, **asr_meta, "audio_bytes": len(pcm)}

    def hangup(self, reason: str) -> None:
        if self.session is not None and not self.session.closed.is_set():
            with contextlib.suppress(Exception):
                self.session.send_text("HANGUP")
        self.recorder.add("call_hangup", monotonic_ms=monotonic_ms(), reason=reason)
        with contextlib.suppress(Exception):
            self._asterisk_cli("dialplan set global KZF_TESTSUITE_ANSWERED 0")
        self.server.close()
        if self.originate is not None:
            with contextlib.suppress(subprocess.TimeoutExpired):
                output, _ = self.originate.communicate(timeout=2.0)
                if output and output.strip():
                    self.recorder.add("asterisk_originate_output", output=output.strip())


@dataclasses.dataclass(frozen=True)
class RunSettings:
    channel: str
    backend: RuntimeClient
    patient: PatientLLMClient
    patient_system_prompt: str
    seed_override: int | None
    show_dialog: bool = False


@dataclasses.dataclass
class ScenarioOutcome:
    scenario_id: str
    technical_pass: bool
    terminal_reason: str | None
    scenario_dir: Path
    error_summary: str | None = None


def event_transport_error(
    recorder: EventRecorder,
    event: str,
    exc: BaseException,
    *,
    turn: int | None = None,
) -> None:
    values: dict[str, Any] = {"error_class": type(exc).__name__}
    if isinstance(exc, TransportError):
        values["operation"] = exc.operation
        values["http_status"] = exc.status
        values["response_body"] = exc.response_body
    else:
        values["reason"] = safe_error_summary(exc)
    recorder.add(event, turn=turn, **values)


def record_backend_state(
    response: Mapping[str, Any],
    *,
    assistant_turn: int,
    recorder: EventRecorder,
    order_snapshots: list[dict[str, Any]],
    backend_record_snapshots: list[dict[str, Any]],
    emitted_record_keys: set[str],
) -> None:
    state_orders = deep_json_copy(response["state"]["orders"])
    normalized_orders = deep_json_copy(
        response.get("normalized_response", {}).get("orders", [])
    )
    order_snapshots.append(
        {
            "turn": assistant_turn,
            "state_orders": state_orders,
            "normalized_orders": normalized_orders,
        }
    )
    records = deep_json_copy(response["records"])
    backend_record_snapshots.append({"turn": assistant_turn, "records": records})
    for record in records:
        key = str(record.get("order_id") or sha256_bytes(json_text(record).encode()))
        if key not in emitted_record_keys:
            emitted_record_keys.add(key)
            recorder.add("record_emitted", turn=assistant_turn, record=record)


def render_transcript(
    scenario: Scenario,
    channel: str,
    dialogue: Sequence[tuple[str, str]],
    final_records: Sequence[Mapping[str, Any]],
    terminal_reason: str | None,
) -> str:
    lines = [
        f"# TEST: {scenario.scenario_id}",
        "",
        str(scenario.data["title"]),
        "",
        f"Kanal: {channel}",
        f"Technisches Dialogende: {terminal_reason or 'unbekannt'}",
        "",
        "## Dialog",
        "",
    ]
    for role, text in dialogue:
        lines.extend([f"### {role}", "", text, ""])
    lines.extend(
        [
            "## Erzeugte Datensätze",
            "",
            "~~~json",
            json_text(list(final_records), pretty=True),
            "~~~",
            "",
        ]
    )
    return "\n".join(lines)


def best_effort_finalize(
    runtime: RuntimeClient,
    session_id: str,
    recorder: EventRecorder,
    validation: TechnicalValidation,
    *,
    reason: str,
) -> tuple[dict[str, Any] | None, bool]:
    try:
        payload = runtime.hangup(session_id)
        value = validate_turn_response(
            payload.data,
            session_id=session_id,
            channel=recorder.channel,
            includes_llm_result=False,
        )
        recorder.add(
            "hangup",
            action_reason=reason,
            backend_http_body=payload.body_text,
            raw=deep_json_copy(value),
        )
        validation.check("backend_hangup")
        return value, True
    except BaseException as exc:
        event_transport_error(recorder, "backend_error", exc)
        validation.error("backend_hangup_failed", safe_error_summary(exc))
        return None, False


def run_scenario(
    scenario: Scenario,
    scenario_root: Path,
    settings: RunSettings,
) -> ScenarioOutcome:
    scenario_dir = scenario_root / scenario.scenario_id
    ensure_private_dir(scenario_dir)
    atomic_write_bytes(scenario_dir / "scenario.yaml", scenario.source_bytes)
    recorder = EventRecorder(scenario.scenario_id, settings.channel)
    validation = TechnicalValidation(scenario.scenario_id)
    dialogue: list[tuple[str, str]] = []
    order_snapshots: list[dict[str, Any]] = []
    backend_record_snapshots: list[dict[str, Any]] = []
    emitted_record_keys: set[str] = set()
    final_records: list[dict[str, Any]] = []
    session_id: str | None = None
    session_terminal = False
    terminal_reason: str | None = None
    patient_messages = initial_patient_messages(
        scenario, settings.channel, settings.patient_system_prompt
    )
    current_patient_text = str(scenario.data["patient"]["opening"]).strip()
    max_turns = int(scenario.data["simulation"]["max_turns"])
    scenario_seed = (
        settings.seed_override
        if settings.seed_override is not None
        else int(scenario.data["simulation"]["seed"])
    )
    recorder.add(
        "scenario_start",
        scenario_sha256=scenario.source_sha256,
        max_turns=max_turns,
        patient_seed=scenario_seed,
    )
    error_summary: str | None = None
    try:
        created = settings.backend.create_session(
            settings.channel, scenario.data["environment"]
        )
        session_id = validate_session_created(created.data, settings.channel)
        validation.check("backend_session_created")
        for exchange in range(1, max_turns + 1):
            patient_turn = exchange * 2 - 1
            assistant_turn = exchange * 2
            recorder.add(
                "patient_turn",
                turn=patient_turn,
                text=current_patient_text,
                source="scenario_opening" if exchange == 1 else "patient_simulator",
            )
            dialogue.append(("PATIENT", current_patient_text))
            if settings.show_dialog:
                print_live_dialog_turn(
                    scenario.scenario_id, "PATIENT", current_patient_text
                )
            try:
                backend_payload = settings.backend.turn(
                    session_id, current_patient_text
                )
                backend_response = validate_turn_response(
                    backend_payload.data,
                    session_id=session_id,
                    channel=settings.channel,
                    includes_llm_result=True,
                )
            except BaseException as exc:
                event_transport_error(
                    recorder, "backend_error", exc, turn=assistant_turn
                )
                validation.error("backend_turn_failed", safe_error_summary(exc))
                terminal_reason = "backend_error"
                error_summary = safe_error_summary(exc)
                break
            validation.check(f"backend_turn_{exchange}_contract")
            recorder.add(
                "assistant_raw_response",
                turn=assistant_turn,
                raw=deep_json_copy(backend_response["raw_response"]),
                backend_http_body=backend_payload.body_text,
            )
            reply = backend_response["reply"]
            recorder.add("assistant_reply", turn=assistant_turn, text=reply)
            dialogue.append(("KIENZLEFON", reply))
            if settings.show_dialog:
                print_live_dialog_turn(scenario.scenario_id, "KIENZLEFON", reply)
            record_backend_state(
                backend_response,
                assistant_turn=assistant_turn,
                recorder=recorder,
                order_snapshots=order_snapshots,
                backend_record_snapshots=backend_record_snapshots,
                emitted_record_keys=emitted_record_keys,
            )
            final_records = deep_json_copy(backend_response["records"])
            action_result = backend_response.get("action_result")
            if (
                isinstance(action_result, Mapping)
                and action_result.get("requested") is True
                and action_result.get("action") != "beenden"
            ):
                recorder.add(
                    "transfer_requested",
                    turn=assistant_turn,
                    action_result=deep_json_copy(action_result),
                )
            if backend_response["terminal"]:
                session_terminal = True
                terminal_reason = (
                    "handoff_requested"
                    if isinstance(action_result, Mapping)
                    and action_result.get("action") != "beenden"
                    else "backend_conversation_end"
                )
                break
            if exchange >= max_turns:
                validation.error(
                    "max_turns_reached",
                    f"hard limit of {max_turns} patient turns reached",
                )
                terminal_reason = "max_turns_reached"
                finalized, session_terminal = best_effort_finalize(
                    settings.backend,
                    session_id,
                    recorder,
                    validation,
                    reason="max_turns_reached",
                )
                if finalized is not None:
                    final_records = deep_json_copy(finalized["records"])
                    backend_record_snapshots.append(
                        {"turn": assistant_turn, "records": final_records}
                    )
                break
            patient_messages.append(
                {
                    "role": "user",
                    "content": (
                        "Letzte Kienzlefon-Antwort:\n"
                        + reply
                        + "\nAntworte jetzt ausschließlich als Patient oder mit "
                        + HANGUP_SIGNAL
                        + ", falls die Regieanweisung dies jetzt verlangt."
                    ),
                }
            )
            try:
                generated, request_payload, patient_payload = (
                    settings.patient.complete(patient_messages, scenario_seed)
                )
            except BaseException as exc:
                event_transport_error(
                    recorder, "patient_simulator_error", exc, turn=patient_turn + 2
                )
                validation.error("patient_simulator_failed", safe_error_summary(exc))
                terminal_reason = "patient_simulator_error"
                error_summary = safe_error_summary(exc)
                break
            recorder.add(
                "patient_simulator_request",
                turn=patient_turn + 2,
                raw=deep_json_copy(request_payload),
            )
            recorder.add(
                "patient_simulator_raw_response",
                turn=patient_turn + 2,
                raw=deep_json_copy(patient_payload.data),
                response_body=patient_payload.body_text,
            )
            patient_messages.append({"role": "assistant", "content": generated})
            if generated == HANGUP_SIGNAL:
                dialogue.append(("PATIENT", f"[{HANGUP_SIGNAL}]"))
                if settings.show_dialog:
                    print_live_dialog_turn(
                        scenario.scenario_id, "PATIENT", f"[{HANGUP_SIGNAL}]"
                    )
                finalized, session_terminal = best_effort_finalize(
                    settings.backend,
                    session_id,
                    recorder,
                    validation,
                    reason="patient_simulator_signal",
                )
                if finalized is not None:
                    final_records = deep_json_copy(finalized["records"])
                    backend_record_snapshots.append(
                        {"turn": patient_turn + 2, "records": final_records}
                    )
                terminal_reason = "simulated_hangup"
                break
            current_patient_text = generated
        if terminal_reason is None:
            terminal_reason = "runner_error"
            validation.error("runner_terminal_missing", "dialog loop ended unexpectedly")
    except BaseException as exc:
        event_transport_error(recorder, "backend_error", exc)
        validation.error("scenario_setup_failed", safe_error_summary(exc))
        terminal_reason = "setup_error"
        error_summary = safe_error_summary(exc)
    finally:
        if session_id is not None and not session_terminal:
            finalized, session_terminal = best_effort_finalize(
                settings.backend,
                session_id,
                recorder,
                validation,
                reason=terminal_reason or "runner_cleanup",
            )
            if finalized is not None:
                final_records = deep_json_copy(finalized["records"])
        if session_id is not None and session_terminal:
            try:
                deleted = settings.backend.delete(session_id)
                if (
                    not isinstance(deleted.data, Mapping)
                    or deleted.data.get("ok") is not True
                ):
                    raise ContractError("backend delete response is invalid")
                validation.check("backend_session_deleted")
            except BaseException as exc:
                event_transport_error(recorder, "backend_error", exc)
                validation.error("backend_session_delete_failed", safe_error_summary(exc))
        validation.terminal_reason = terminal_reason
        recorder.add(
            "scenario_end",
            technical_status="PASS" if validation.passed else "FAIL",
            terminal_reason=terminal_reason,
        )
        records_payload = {
            "protocol": RECORDS_PROTOCOL,
            "scenario_id": scenario.scenario_id,
            "final_records": final_records,
            "order_snapshots": order_snapshots,
            "backend_record_snapshots": backend_record_snapshots,
        }
        recorder.write(scenario_dir / "events.jsonl")
        write_json(scenario_dir / "records.json", records_payload)
        write_json(
            scenario_dir / "technical_validation.json", validation.payload()
        )
        atomic_write_text(
            scenario_dir / "transcript.md",
            render_transcript(
                scenario,
                settings.channel,
                dialogue,
                final_records,
                terminal_reason,
            ),
        )
    return ScenarioOutcome(
        scenario.scenario_id,
        validation.passed,
        terminal_reason,
        scenario_dir,
        error_summary,
    )


def discover_models_from_url(url: str, timeout: float) -> dict[str, Any] | None:
    try:
        result = JSONHTTPClient(timeout).request(
            "backend_models", "GET", endpoint_sibling(url, "models")
        )
    except TestsuiteError:
        return None
    return deep_json_copy(result.data) if isinstance(result.data, Mapping) else None


def detect_git_commit(root: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    value = result.stdout.strip()
    return value if re.fullmatch(r"[0-9a-fA-F]{40,64}", value) else None


def snapshot_tree(path: Path) -> dict[str, str]:
    return {
        str(candidate.relative_to(path)): sha256_file(candidate)
        for candidate in sorted(path.rglob("*"))
        if candidate.is_file()
    }


def immutable_artifact_hashes(path: Path) -> dict[str, str]:
    return {
        relative: digest
        for relative, digest in snapshot_tree(path).items()
        if relative != "manifest.json"
        and not relative.startswith("evaluations/")
    }


def verify_run_artifact_hashes(run_dir: Path, manifest: Mapping[str, Any]) -> None:
    expected = manifest.get("artifact_hashes")
    if not isinstance(expected, Mapping) or not expected:
        raise ConfigurationError(f"{run_dir}: immutable artifact hashes are missing")
    for relative, expected_hash in expected.items():
        if not isinstance(relative, str) or not isinstance(expected_hash, str):
            raise ConfigurationError(f"{run_dir}: invalid artifact hash entry")
        relative_path = Path(relative)
        if relative_path.is_absolute() or ".." in relative_path.parts:
            raise ConfigurationError(f"{run_dir}: unsafe artifact hash path")
        path = run_dir / relative
        if (
            path.is_symlink()
            or not path.is_file()
            or sha256_file(path) != expected_hash
        ):
            raise ConfigurationError(
                f"{run_dir}: immutable artifact mismatch at {relative}"
            )


def load_json_file(path: Path) -> Any:
    try:
        return strict_json_loads(read_utf8(path))
    except (json.JSONDecodeError, ValueError) as exc:
        raise ConfigurationError(f"{path}: invalid JSON") from exc


def load_jsonl(path: Path) -> list[Any]:
    values = []
    for line_number, line in enumerate(read_utf8(path).splitlines(), start=1):
        try:
            values.append(strict_json_loads(line))
        except (json.JSONDecodeError, ValueError) as exc:
            raise ConfigurationError(
                f"{path}:{line_number}: invalid JSONL event"
            ) from exc
    return values


def collect_bundle_data(run_dir: Path) -> dict[str, Any]:
    manifest = load_json_file(run_dir / "manifest.json")
    prompts_dir = run_dir / "prompts"
    system_prompt = read_utf8(prompts_dir / "kienzlefon-system.txt")
    patient_prompt = read_utf8(prompts_dir / "patient-simulator-system.txt")
    overlay = read_utf8(prompts_dir / "channel-overlay.txt")
    evaluator_path = prompts_dir / "external-evaluator-instructions.md"
    evaluator_instructions = (
        read_utf8(evaluator_path) if evaluator_path.is_file() else ""
    )
    scenarios = []
    scenario_root = run_dir / "scenarios"
    for scenario_dir in sorted(
        (path for path in scenario_root.iterdir() if path.is_dir()),
        key=lambda path: path.name,
    ):
        yaml, _ = dependency_modules()
        scenario_text = read_utf8(scenario_dir / "scenario.yaml")
        scenario_value = yaml.safe_load(scenario_text)
        scenarios.append(
            {
                "scenario": scenario_value,
                "scenario_yaml": scenario_text,
                "transcript": read_utf8(scenario_dir / "transcript.md"),
                "events": load_jsonl(scenario_dir / "events.jsonl"),
                "records": load_json_file(scenario_dir / "records.json"),
                "technical_validation": load_json_file(
                    scenario_dir / "technical_validation.json"
                ),
            }
        )
    return {
        "protocol": "kienzlefon-dialog-evaluation-bundle-v1",
        "manifest": manifest,
        "prompts": {
            "kienzlefon_system": system_prompt,
            "patient_simulator_system": patient_prompt,
            "channel_overlay": overlay,
        },
        "external_evaluator_instructions": evaluator_instructions,
        "scenarios": scenarios,
    }


def render_evaluation_markdown(bundle: Mapping[str, Any]) -> str:
    manifest = bundle["manifest"]
    prompts = bundle["prompts"]
    target_mode = manifest.get("target_mode", "direct")
    lines = [
        "# Kienzlefon – externes Evaluation-Bundle",
        "",
        str(bundle.get("external_evaluator_instructions", "")).strip(),
        "",
        "## Run",
        "",
        f"- Run-ID: {manifest.get('run_id')}",
        f"- Kanal: {manifest.get('channel')}",
        f"- Zielmodus: {target_mode}",
        f"- Patientenmodell: {manifest.get('patient_model', {}).get('model')}",
    ]
    if target_mode == "voice":
        lines.extend([
            f"- Zielrufnummer: {manifest.get('target', {}).get('number')}",
            "- Ziel-System-Prompt: nicht verfügbar (Blackbox-Telefontest)",
            "- Ziel-JSONs: nicht im Bundle; werden separat anhand der Zeitstempel zugeordnet",
            "",
        ])
    else:
        lines.extend([
            f"- Backendversion: {manifest.get('backend', {}).get('version')}",
            "- Kienzlefon-Promptquelle: Runtime-Metadaten",
            "",
            "## Tatsächlich verwendeter Kienzlefon-System-Prompt",
            "",
            "~~~text",
            str(prompts["kienzlefon_system"]),
            "~~~",
            "",
        ])
    for entry in bundle["scenarios"]:
        scenario = entry["scenario"]
        lines.extend(
            [
                "=" * 70,
                "",
                f"# {scenario['scenario_id']} – {scenario['title']}",
                "",
                f"Tags: {', '.join(scenario.get('tags', []))}",
                "",
                "## Testziel und Erwartungen",
                "",
                "~~~json",
                json_text(
                    {
                        "test_goal": scenario.get("test_goal"),
                        "expectations": scenario.get("expectations"),
                        "channel_overrides": scenario.get("channel_overrides"),
                    },
                    pretty=True,
                ),
                "~~~",
                "",
                "## Vollständiges Szenario",
                "",
                "~~~yaml",
                entry["scenario_yaml"],
                "~~~",
                "",
                "## Dialog",
                "",
                entry["transcript"],
                "",
                "## Records",
                "",
                "~~~json",
                json_text(entry["records"], pretty=True),
                "~~~",
                "",
                "## Technische Validierung",
                "",
                "~~~json",
                json_text(entry["technical_validation"], pretty=True),
                "~~~",
                "",
            ]
        )
    return "\n".join(lines).rstrip() + "\n"


def write_bundle(run_dir: Path, output_dir: Path) -> None:
    bundle = collect_bundle_data(run_dir)
    ensure_private_dir(output_dir)
    write_json(output_dir / "evaluation_bundle.json", bundle)
    atomic_write_text(
        output_dir / "evaluation_bundle.md",
        render_evaluation_markdown(bundle),
    )


def run_bundle_only(run_dir: Path, output: Path | None) -> int:
    if not run_dir.is_dir():
        raise ConfigurationError(f"{run_dir}: run directory does not exist")
    before = snapshot_tree(run_dir)
    manifest = load_json_file(run_dir / "manifest.json")
    if manifest.get("protocol") != RUN_PROTOCOL:
        raise ConfigurationError(f"{run_dir}: unsupported run protocol")
    if manifest.get("status") not in {"complete", "technical_failures"}:
        raise ConfigurationError(f"{run_dir}: run is not finalized")
    verify_run_artifact_hashes(run_dir, manifest)
    if output is None:
        output = run_dir.parent / f"{run_dir.name}-bundle-{utc_run_stamp()}"
    output = output.resolve()
    if output.is_relative_to(run_dir.resolve()):
        raise ConfigurationError("bundle output must be outside the source run")
    if output.exists():
        raise ConfigurationError(f"{output}: output already exists")
    write_bundle(run_dir, output)
    after = snapshot_tree(run_dir)
    if before != after:
        raise TestsuiteError("bundle-only modified the source run")
    print(f"Bundle erstellt: {output}")
    return 0


def prepare_prompt_artifacts(
    stage: Path,
    *,
    metadata: Mapping[str, Any],
    channel: str,
    patient_prompt_bytes: bytes,
    evaluator_instructions: bytes,
    patient_prompt_version: str,
    patient_prompt_source: Path,
) -> dict[str, Any]:
    prompts_dir = stage / "prompts"
    ensure_private_dir(prompts_dir)
    system_bytes = metadata["system_prompt"].encode("utf-8")
    overlay_bytes = metadata["channel_overlays"][channel].encode("utf-8")
    atomic_write_bytes(prompts_dir / "kienzlefon-system.txt", system_bytes)
    atomic_write_bytes(
        prompts_dir / "patient-simulator-system.txt", patient_prompt_bytes
    )
    atomic_write_bytes(prompts_dir / "channel-overlay.txt", overlay_bytes)
    atomic_write_bytes(
        prompts_dir / "external-evaluator-instructions.md",
        evaluator_instructions,
    )
    prompt_metadata = {
        "kienzlefon_system": {
            "source": "runtime_metadata",
            "backend_version": metadata["backend_version"],
        },
        "patient_simulator_system": {
            "version": patient_prompt_version,
            "source": str(patient_prompt_source),
        },
        "channel_overlay": {
            "channel": channel,
            "source": "runtime_metadata",
            "backend_version": metadata["backend_version"],
        },
    }
    write_json(prompts_dir / "metadata.json", prompt_metadata)
    return prompt_metadata


def run_parallel_scenarios(
    scenarios: Sequence[Scenario],
    scenario_root: Path,
    settings: RunSettings,
    *,
    max_parallel: int,
    fail_fast: bool,
) -> list[ScenarioOutcome]:
    outcomes: list[ScenarioOutcome] = []
    iterator = iter(scenarios)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_parallel) as executor:
        pending: dict[concurrent.futures.Future[ScenarioOutcome], Scenario] = {}
        for _ in range(max_parallel):
            try:
                scenario = next(iterator)
            except StopIteration:
                break
            pending[executor.submit(run_scenario, scenario, scenario_root, settings)] = (
                scenario
            )
        stop_scheduling = False
        while pending:
            done, _ = concurrent.futures.wait(
                pending, return_when=concurrent.futures.FIRST_COMPLETED
            )
            for future in done:
                scenario = pending.pop(future)
                try:
                    outcome = future.result()
                except BaseException as exc:
                    raise TestsuiteError(
                        f"{scenario.scenario_id}: unexpected runner failure "
                        f"({type(exc).__name__})"
                    ) from exc
                outcomes.append(outcome)
                line = (
                    f"{outcome.scenario_id}: "
                    f"{'TECHNISCH PASS' if outcome.technical_pass else 'TECHNISCH FAIL'}"
                )
                if not outcome.technical_pass and outcome.error_summary:
                    line += f" – {outcome.error_summary}"
                print(line)
                if fail_fast and not outcome.technical_pass:
                    stop_scheduling = True
            if stop_scheduling:
                for future in pending:
                    future.cancel()
                continue
            while len(pending) < max_parallel:
                try:
                    scenario = next(iterator)
                except StopIteration:
                    break
                pending[
                    executor.submit(run_scenario, scenario, scenario_root, settings)
                ] = scenario
    return sorted(outcomes, key=lambda outcome: outcome.scenario_id)



def render_voice_transcript(
    scenario: Scenario,
    dialogue: Sequence[tuple[str, str]],
    terminal_reason: str | None,
    target_number: str,
) -> str:
    lines = [
        f"# TEST: {scenario.scenario_id}",
        "",
        str(scenario.data["title"]),
        "",
        "Kanal: telephone",
        "Zielmodus: voice",
        f"Zielrufnummer: {target_number}",
        f"Technisches Dialogende: {terminal_reason or 'unbekannt'}",
        "",
        "## Dialog",
        "",
    ]
    for role, text in dialogue:
        lines.extend([f"### {role}", "", text, ""])
    lines.extend([
        "## Ziel-Datensätze",
        "",
        "Nicht Bestandteil dieses Voice-Runs. Externe Ziel-JSONs werden separat anhand der Zeitstempel zugeordnet.",
        "",
    ])
    return "\n".join(lines)


def voice_prompt_artifacts(
    stage: Path,
    *,
    patient_prompt_bytes: bytes,
    evaluator_instructions: bytes,
    patient_prompt_version: str,
    patient_prompt_source: Path,
) -> dict[str, Any]:
    prompts_dir = stage / "prompts"
    ensure_private_dir(prompts_dir)
    unavailable = (
        "Externes Voice-Ziel: interner System-Prompt und Kanal-Overlay sind der Testsuite nicht zugänglich.\n"
    ).encode("utf-8")
    voice_note = (
        "\n\n## Ergänzung für Voice-Targets\n\n"
        "Dieser Run testet eine telefonisch erreichbare Ziel-KI als Blackbox über deren vollständige ASR/LLM/TTS-Kette. "
        "Die vom Ziel erzeugten JSON-Dateien sind bewusst nicht Bestandteil dieses Bundles und werden separat anhand der "
        "absoluten Zeitstempel zugeordnet. Bewerte strukturierte Datensätze erst, wenn diese separat vorliegen.\n"
    ).encode("utf-8")
    atomic_write_bytes(prompts_dir / "kienzlefon-system.txt", unavailable)
    atomic_write_bytes(prompts_dir / "channel-overlay.txt", unavailable)
    atomic_write_bytes(prompts_dir / "patient-simulator-system.txt", patient_prompt_bytes)
    atomic_write_bytes(prompts_dir / "external-evaluator-instructions.md", evaluator_instructions + voice_note)
    metadata = {
        "kienzlefon_system": {"source": "unavailable_voice_target"},
        "patient_simulator_system": {"version": patient_prompt_version, "source": str(patient_prompt_source)},
        "channel_overlay": {"channel": "telephone", "source": "unavailable_voice_target"},
    }
    write_json(prompts_dir / "metadata.json", metadata)
    return metadata


def load_reference_wav_pcm(path: Path) -> bytes:
    """Load a diagnostic WAV that is already telephony-ready.

    Keeping the format strict is intentional: this reference test is meant to
    isolate transport/playout, not hide format conversion inside the test path.
    """
    try:
        with wave.open(str(path), "rb") as handle:
            channels = handle.getnchannels()
            width = handle.getsampwidth()
            rate = handle.getframerate()
            comptype = handle.getcomptype()
            frames = handle.getnframes()
            pcm = handle.readframes(frames)
    except (wave.Error, OSError) as exc:
        raise ConfigurationError(f"cannot read --voice-reference-wav {path}: {exc}") from exc
    if comptype != "NONE":
        raise ConfigurationError("--voice-reference-wav must be uncompressed PCM WAV")
    if channels != 1 or width != 2 or rate != VOICE_MEDIA_RATE:
        raise ConfigurationError(
            "--voice-reference-wav must be mono PCM16 at 16000 Hz "
            f"(got channels={channels}, width={width}, rate={rate})"
        )
    if not pcm:
        raise ConfigurationError("--voice-reference-wav contains no audio")
    return pcm


def generate_reference_pcm(tts: PatientTTSClient, text: str) -> tuple[bytes, dict[str, Any]]:
    pcm = bytearray()
    meta = tts.stream(text, pcm.extend)
    if not pcm:
        raise VoiceError("reference TTS produced no PCM")
    return bytes(pcm), meta


def run_voice_scenario(
    scenario: Scenario,
    scenario_root: Path,
    *,
    patient: PatientLLMClient,
    patient_system_prompt: str,
    seed_override: int | None,
    voice: VoiceSettings,
    show_dialog: bool,
) -> ScenarioOutcome:
    scenario_dir = scenario_root / scenario.scenario_id
    ensure_private_dir(scenario_dir)
    ensure_private_dir(scenario_dir / "audio")
    atomic_write_bytes(scenario_dir / "scenario.yaml", scenario.source_bytes)
    recorder = EventRecorder(scenario.scenario_id, "telephone")
    validation = TechnicalValidation(scenario.scenario_id)
    dialogue: list[tuple[str, str]] = []
    terminal_reason: str | None = None
    error_summary: str | None = None
    patient_messages = initial_patient_messages(scenario, "telephone", patient_system_prompt)
    current_patient_text = str(scenario.data["patient"]["opening"]).strip()
    max_turns = int(scenario.data["simulation"]["max_turns"])
    scenario_seed = seed_override if seed_override is not None else int(scenario.data["simulation"]["seed"])
    call = AsteriskVoiceCall(voice, recorder)
    reference_pcm: bytes | None = None
    reference_source: str | None = None
    reference_tts_meta: dict[str, Any] = {}
    if voice.reference_test:
        if voice.reference_wav is not None:
            reference_pcm = load_reference_wav_pcm(voice.reference_wav)
            reference_source = str(voice.reference_wav)
        else:
            reference_pcm, reference_tts_meta = generate_reference_pcm(voice.tts, voice.reference_text)
            reference_source = "generated-before-call"
        write_pcm_wav(scenario_dir / "audio" / "reference-02-patient-prepared.wav", reference_pcm)
    recorder.add(
        "scenario_start",
        scenario_sha256=scenario.source_sha256,
        max_turns=max_turns,
        patient_seed=scenario_seed,
        target_mode="voice",
        target_number=voice.target_number,
        monotonic_ms=monotonic_ms(),
    )
    try:
        call.start()
        validation.check("voice_media_connected")
        validation.check("voice_target_answered")
        if voice.reference_test:
            recorder.add(
                "reference_test_start",
                monotonic_ms=monotonic_ms(),
                rx_window_seconds=voice.reference_seconds,
                reference_source=reference_source,
                reference_text=voice.reference_text if voice.reference_wav is None else None,
                **reference_tts_meta,
            )
            start_text, start_meta = call.capture_fixed_rx_window(
                voice.reference_seconds,
                scenario_dir / "audio" / "reference-01-sophia-start.wav",
                label="sophia_start",
            )
            validation.check("reference_start_window_captured")
            dialogue.append(("TELEFONASSISTENT (REFERENZ START)", start_text or "[keine ASR-Transkription]"))
            if show_dialog:
                print_live_dialog_turn(
                    scenario.scenario_id,
                    "REFERENZ SOPHIA START",
                    start_text or "[keine ASR-Transkription]",
                )
            if reference_pcm is None:
                raise VoiceError("reference PCM was not prepared")
            play_meta = call.play_prepared_pcm(
                reference_pcm,
                scenario_dir / "audio" / "reference-02-patient-played.wav",
                label="prepared_patient_wav",
            )
            validation.check("reference_wav_played")
            if show_dialog:
                print_live_dialog_turn(
                    scenario.scenario_id,
                    "REFERENZ WAV GESENDET",
                    voice.reference_text if voice.reference_wav is None else voice.reference_wav.name,
                )
            response_text, response_meta = call.capture_fixed_rx_window(
                voice.reference_seconds,
                scenario_dir / "audio" / "reference-03-sophia-response.wav",
                label="sophia_response",
            )
            validation.check("reference_response_window_captured")
            dialogue.append(("TELEFONASSISTENT (REFERENZ ANTWORT)", response_text or "[keine ASR-Transkription]"))
            if show_dialog:
                print_live_dialog_turn(
                    scenario.scenario_id,
                    "REFERENZ SOPHIA ANTWORT",
                    response_text or "[keine ASR-Transkription]",
                )
            recorder.add(
                "reference_test_end",
                monotonic_ms=monotonic_ms(),
                start_capture=start_meta,
                playback=play_meta,
                response_capture=response_meta,
            )
            terminal_reason = "reference_test_complete"
        elif voice.listen_only_seconds > 0:
            diagnostic_text, diagnostic_meta = call.listen_only_diagnostic(
                voice.listen_only_seconds,
                scenario_dir / "audio" / "assistant-rx-listen-only.wav",
            )
            if diagnostic_meta.get("captured_bytes", 0):
                validation.check("voice_listen_only_rx")
            else:
                validation.error("voice_listen_only_no_rx", "no inbound media received during listen-only diagnostic")
            if diagnostic_text:
                dialogue.append(("TELEFONASSISTENT (RX-DIAGNOSE)", diagnostic_text))
                if show_dialog:
                    print_live_dialog_turn(scenario.scenario_id, "RX-DIAGNOSE", diagnostic_text)
                validation.check("voice_listen_only_asr")
            else:
                dialogue.append(("TELEFONASSISTENT (RX-DIAGNOSE)", "[keine ASR-Transkription]"))
                if show_dialog:
                    print_live_dialog_turn(scenario.scenario_id, "RX-DIAGNOSE", "[keine ASR-Transkription]")
                validation.warning("voice_listen_only_asr_empty", "raw inbound audio produced no observer-ASR transcript")
            terminal_reason = "listen_only_complete"
        else:
            # Strict half-duplex start: Sophia owns the line first.  We do not
            # send a wake-up "Hallo" and we never talk over an incomplete greeting.
            recorder.add(
                "half_duplex_rx_enter",
                turn=0,
                monotonic_ms=monotonic_ms(),
                purpose="initial_greeting",
            )
            greeting = call.listen(
                0,
                scenario_dir / "audio" / "assistant-greeting.wav",
                voice.greeting_wait,
            )
            if greeting is None:
                validation.error(
                    "voice_greeting_timeout",
                    f"no target greeting within {voice.greeting_wait:.1f}s in half-duplex comfort-noise mode",
                )
                terminal_reason = "voice_greeting_timeout"
            else:
                greeting_text, greeting_meta = greeting
                recorder.add("assistant_greeting", turn=0, text=greeting_text, **greeting_meta)
                dialogue.append(("TELEFONASSISTENT (BEGRÜSSUNG)", greeting_text))
                if show_dialog:
                    print_live_dialog_turn(scenario.scenario_id, "BEGRÜSSUNG", greeting_text)
                validation.check("voice_greeting_observed")

            if terminal_reason is None:
                for exchange in range(1, max_turns + 1):
                    patient_turn = exchange * 2 - 1
                    assistant_turn = exchange * 2
                    recorder.add(
                        "patient_turn",
                        turn=patient_turn,
                        text=current_patient_text,
                        source="scenario_opening" if exchange == 1 else "patient_simulator",
                    )
                    dialogue.append(("PATIENT", current_patient_text))
                    if show_dialog:
                        print_live_dialog_turn(scenario.scenario_id, "PATIENT", current_patient_text)
                    audio_meta = call.speak(
                        current_patient_text,
                        patient_turn,
                        scenario_dir / "audio" / f"patient-{patient_turn:03d}.wav",
                    )
                    validation.check(f"voice_patient_tts_{exchange}")
                    response = call.listen(
                        assistant_turn,
                        scenario_dir / "audio" / f"assistant-{assistant_turn:03d}.wav",
                        voice.response_timeout,
                    )
                    if response is None:
                        if call.session is not None and call.session.closed.is_set():
                            terminal_reason = "remote_hangup"
                            validation.warning("remote_hangup", "target ended the call before another transcribable reply")
                            break
                        validation.error("voice_response_timeout", f"no transcribable target response within {voice.response_timeout:.1f}s")
                        terminal_reason = "voice_response_timeout"
                        break
                    reply, response_meta = response
                    response_start = response_meta.get("estimated_speech_start_monotonic_ms")
                    patient_end = audio_meta.get("audio_end_monotonic_ms")
                    if isinstance(response_start, (int, float)) and isinstance(patient_end, (int, float)):
                        recorder.add(
                            "response_latency",
                            turn=assistant_turn,
                            latency_ms=round(float(response_start) - float(patient_end), 3),
                            patient_audio_end_monotonic_ms=patient_end,
                            assistant_speech_start_monotonic_ms=response_start,
                        )
                    recorder.add("assistant_reply", turn=assistant_turn, text=reply, source="observer_asr")
                    dialogue.append(("TELEFONASSISTENT", reply))
                    if show_dialog:
                        print_live_dialog_turn(scenario.scenario_id, "TELEFONASSISTENT", reply)
                    validation.check(f"voice_target_reply_{exchange}")

                    if call.session is not None and call.session.closed.is_set():
                        terminal_reason = "remote_hangup"
                        validation.warning("remote_hangup", "target ended the call after its reply")
                        break

                    if exchange >= max_turns:
                        validation.error("max_turns_reached", f"hard limit of {max_turns} patient turns reached")
                        terminal_reason = "max_turns_reached"
                        break

                    patient_messages.append(
                        {
                            "role": "user",
                            "content": (
                                "Letzte Antwort des Telefonassistenten:\n"
                                + reply
                                + "\nAntworte jetzt ausschließlich als Patient oder mit "
                                + HANGUP_SIGNAL
                                + ", falls die Regieanweisung dies jetzt verlangt."
                            ),
                        }
                    )
                    try:
                        generated, request_payload, patient_payload = patient.complete(patient_messages, scenario_seed)
                    except BaseException as exc:
                        event_transport_error(recorder, "patient_simulator_error", exc, turn=patient_turn + 2)
                        validation.error("patient_simulator_failed", safe_error_summary(exc))
                        terminal_reason = "patient_simulator_error"
                        error_summary = safe_error_summary(exc)
                        break
                    recorder.add("patient_simulator_request", turn=patient_turn + 2, raw=deep_json_copy(request_payload))
                    recorder.add(
                        "patient_simulator_raw_response",
                        turn=patient_turn + 2,
                        raw=deep_json_copy(patient_payload.data),
                        response_body=patient_payload.body_text,
                    )
                    patient_messages.append({"role": "assistant", "content": generated})
                    if generated == HANGUP_SIGNAL:
                        dialogue.append(("PATIENT", f"[{HANGUP_SIGNAL}]"))
                        if show_dialog:
                            print_live_dialog_turn(scenario.scenario_id, "PATIENT", f"[{HANGUP_SIGNAL}]")
                        terminal_reason = "simulated_hangup"
                        break
                    current_patient_text = generated

        if terminal_reason is None:
            terminal_reason = "runner_error"
            validation.error("runner_terminal_missing", "voice dialog loop ended unexpectedly")
    except BaseException as exc:
        event_transport_error(recorder, "voice_error", exc)
        validation.error("voice_transport_failed", safe_error_summary(exc))
        terminal_reason = "voice_error"
        error_summary = safe_error_summary(exc)
    finally:
        with contextlib.suppress(Exception):
            call.hangup(terminal_reason or "runner_cleanup")
        with contextlib.suppress(Exception):
            call.save_continuous_rx(scenario_dir / "audio" / "assistant-rx-continuous.wav")
        validation.terminal_reason = terminal_reason
        recorder.add(
            "scenario_end",
            technical_status="PASS" if validation.passed else "FAIL",
            terminal_reason=terminal_reason,
            monotonic_ms=monotonic_ms(),
        )
        recorder.write(scenario_dir / "events.jsonl")
        write_json(
            scenario_dir / "records.json",
            {
                "protocol": RECORDS_PROTOCOL,
                "scenario_id": scenario.scenario_id,
                "records_source": "external_separate",
                "final_records": [],
                "order_snapshots": [],
                "backend_record_snapshots": [],
                "note": "Voice target JSON files are supplied separately and correlated by timestamps.",
            },
        )
        write_json(scenario_dir / "technical_validation.json", validation.payload())
        atomic_write_text(
            scenario_dir / "transcript.md",
            render_voice_transcript(scenario, dialogue, terminal_reason, voice.target_number),
        )
    return ScenarioOutcome(
        scenario.scenario_id,
        validation.passed,
        terminal_reason,
        scenario_dir,
        error_summary,
    )


def validate_voice_options(args: argparse.Namespace) -> None:
    if args.channel != "telephone":
        raise ConfigurationError("--target-mode voice supports only --channel telephone")
    if args.max_parallel != 1:
        raise ConfigurationError("--target-mode voice requires --max-parallel 1")
    if not args.target_number:
        raise ConfigurationError("--target-mode voice requires --target-number")
    validate_target_number(args.target_number)
    safe_voice_identifier(args.asterisk_endpoint, "--asterisk-endpoint")
    safe_voice_identifier(args.asterisk_ws_connection, "--asterisk-ws-connection")
    try:
        bind = ipaddress.ip_address(args.voice_media_bind)
    except ValueError as exc:
        raise ConfigurationError("--voice-media-bind must be an IP address") from exc
    if not bind.is_loopback:
        raise ConfigurationError("--voice-media-bind must be loopback in v1.1.3")
    if not 1 <= args.voice_media_port <= 65535:
        raise ConfigurationError("--voice-media-port must be between 1 and 65535")
    assert_loopback_ws_url(args.observer_asr_url, "--observer-asr-url")
    assert_loopback_url(args.qwen_tts_url, "--qwen-tts-url")
    assert_loopback_url(args.piper_tts_url, "--piper-tts-url")
    for name in ("voice_answer_timeout", "voice_greeting_wait", "voice_response_timeout", "voice_asr_timeout", "voice_tts_timeout"):
        if float(getattr(args, name)) <= 0:
            raise ConfigurationError(f"--{name.replace('_', '-')} must be positive")
    if not 1 <= args.voice_dial_timeout <= 3600:
        raise ConfigurationError("--voice-dial-timeout must be between 1 and 3600")
    if not 100 <= args.voice_energy_threshold <= 10000:
        raise ConfigurationError("--voice-energy-threshold must be between 100 and 10000")
    if not 0 <= args.voice_comfort_noise_rms <= 1000:
        raise ConfigurationError("--voice-comfort-noise-rms must be between 0 and 1000")
    if not 0 <= args.voice_preroll_ms <= 2000:
        raise ConfigurationError("--voice-preroll-ms must be between 0 and 2000")
    if not 20 <= args.voice_speech_start_ms <= 2000:
        raise ConfigurationError("--voice-speech-start-ms must be between 20 and 2000")
    if not 100 <= args.voice_speech_end_ms <= 5000:
        raise ConfigurationError("--voice-speech-end-ms must be between 100 and 5000")
    if not 0.0 <= args.voice_listen_only_seconds <= 60.0:
        raise ConfigurationError("--voice-listen-only-seconds must be between 0 and 60")
    if not args.voice_wakeup_text.strip() or len(args.voice_wakeup_text) > 80:
        raise ConfigurationError("--voice-wakeup-text must contain 1-80 non-space characters")
    if not 20 <= args.voice_min_utterance_ms < args.voice_max_utterance_ms <= 120000:
        raise ConfigurationError("voice utterance duration limits are invalid")


def voice_preflight(args: argparse.Namespace) -> None:
    if shutil.which("asterisk") is None:
        raise DependencyError("asterisk CLI is missing")
    for command, expected, label in (
        ("module show like chan_websocket", "chan_websocket.so", "chan_websocket"),
        (f"pjsip show endpoint {args.asterisk_endpoint}", f"Endpoint:  {args.asterisk_endpoint}", "Asterisk PJSIP endpoint"),
    ):
        result = subprocess.run(
            ["asterisk", "-rx", command],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=10,
            check=False,
        )
        if result.returncode != 0 or expected not in result.stdout:
            raise ConfigurationError(f"{label} is not available or not loaded")


def run_voice_normal(args: argparse.Namespace) -> int:
    validate_numeric_options(args)
    validate_voice_options(args)
    if not args.confirm_synthetic_test_data:
        raise ConfigurationError("execution requires --confirm-synthetic-test-data")
    if args.show_dialog and args.max_parallel != 1:
        raise ConfigurationError("--show-dialog requires --max-parallel 1")
    assert_loopback_url(args.patient_llm_url, "--patient-llm-url")
    package_manifest = verify_package_manifest(args.package_manifest.resolve())
    verify_scenario_index(args.scenarios.resolve())
    scenarios = load_scenarios(
        args.scenarios.resolve(),
        args.schema.resolve(),
        channel="telephone",
        selected_ids=args.scenario,
        selected_tags=args.tag,
    )
    voice_preflight(args)
    root = Path(__file__).resolve().parent
    patient_path = args.patient_prompt.resolve()
    evaluator_path = args.external_evaluator_instructions.resolve()
    patient_bytes = patient_path.read_bytes()
    evaluator_bytes = evaluator_path.read_bytes()
    try:
        patient_prompt = patient_bytes.decode("utf-8")
        evaluator_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConfigurationError("a prompt/template file is not valid UTF-8") from exc
    patient = PatientLLMClient(
        args.patient_llm_url,
        args.timeout,
        model=args.patient_model,
        temperature=args.patient_temperature,
        top_p=args.patient_top_p,
        max_tokens=args.patient_max_tokens,
    )
    patient_models: dict[str, Any] | None = None
    if patient.model is None:
        patient.model, patient_models = patient.discover_model()
    else:
        try:
            _, patient_models = patient.discover_model()
        except TestsuiteError:
            patient_models = None
    patient_props = patient.try_props()
    output_root = (args.output or (root / "runs")).resolve()
    ensure_private_dir(output_root)
    run_id = safe_run_id(args.run_id or f"{utc_run_stamp()}_voice_{uuid.uuid4().hex[:8]}")
    final_dir = output_root / run_id
    if final_dir.exists():
        raise ConfigurationError(f"{final_dir}: run already exists")
    stage = output_root / f".{run_id}.incomplete-{uuid.uuid4().hex[:8]}"
    ensure_private_dir(stage)
    ensure_private_dir(stage / "scenarios")
    ensure_private_dir(stage / "evaluations")
    prompt_metadata = voice_prompt_artifacts(
        stage,
        patient_prompt_bytes=patient_bytes,
        evaluator_instructions=evaluator_bytes,
        patient_prompt_version=args.patient_prompt_version,
        patient_prompt_source=patient_path,
    )
    tts = PatientTTSClient(
        backend=args.patient_tts,
        qwen_url=args.qwen_tts_url,
        piper_url=args.piper_tts_url,
        timeout=args.voice_tts_timeout,
        qwen_speaker=args.qwen_speaker,
        qwen_language=args.qwen_language,
        qwen_seed=args.qwen_seed,
    )
    vad = VoiceVADSettings(
        energy_threshold=args.voice_energy_threshold,
        preroll_ms=args.voice_preroll_ms,
        speech_start_ms=args.voice_speech_start_ms,
        speech_end_ms=args.voice_speech_end_ms,
        minimum_utterance_ms=args.voice_min_utterance_ms,
        maximum_utterance_ms=args.voice_max_utterance_ms,
    )
    voice = VoiceSettings(
        target_number=args.target_number,
        asterisk_endpoint=args.asterisk_endpoint,
        ws_connection=args.asterisk_ws_connection,
        media_bind=args.voice_media_bind,
        media_port=args.voice_media_port,
        answer_timeout=args.voice_answer_timeout,
        greeting_wait=args.voice_greeting_wait,
        response_timeout=args.voice_response_timeout,
        dial_timeout=args.voice_dial_timeout,
        listen_only_seconds=args.voice_listen_only_seconds,
        wakeup_text=args.voice_wakeup_text,
        wakeup_barge_ms=DEFAULT_VOICE_WAKEUP_BARGE_MS,
        comfort_noise_rms=args.voice_comfort_noise_rms,
        comfort_noise_seed=DEFAULT_VOICE_COMFORT_NOISE_SEED,
        reference_test=args.voice_reference_test,
        reference_seconds=args.voice_reference_seconds,
        reference_text=args.voice_reference_text,
        reference_wav=args.voice_reference_wav.resolve() if args.voice_reference_wav is not None else None,
        asr_url=args.observer_asr_url,
        asr_timeout=args.voice_asr_timeout,
        tts=tts,
        vad=vad,
    )
    started_at = now_iso()
    manifest: dict[str, Any] = {
        "protocol": RUN_PROTOCOL,
        "testsuite_version": VERSION,
        "run_id": run_id,
        "status": "running",
        "started_at": started_at,
        "finished_at": None,
        "channel": "telephone",
        "target_mode": "voice",
        "synthetic_test_data_only": True,
        "semantic_evaluation": "NOT_PERFORMED",
        "scenario_format_version": SCENARIO_FORMAT_VERSION,
        "scenario_package": {
            "package": package_manifest.get("package"),
            "format_version": package_manifest.get("format_version"),
            "manifest_sha256": sha256_file(args.package_manifest.resolve()),
        },
        "kienzlefon_prompt": prompt_metadata["kienzlefon_system"],
        "patient_prompt": prompt_metadata["patient_simulator_system"],
        "channel_overlay": prompt_metadata["channel_overlay"],
        "backend": {"name": "external-voice-target", "protocol": VOICE_PROTOCOL, "version": None, "git_commit": detect_git_commit(root)},
        "target": {
            "mode": "voice",
            "number": args.target_number,
            "transport": "asterisk-chan_websocket",
            "asterisk_endpoint": args.asterisk_endpoint,
            "websocket_connection": args.asterisk_ws_connection,
            "media": {"encoding": "pcm_s16le", "sample_rate": VOICE_MEDIA_RATE, "channels": 1},
            "records": "external_separate",
        },
        "patient_model": {
            "endpoint": args.patient_llm_url,
            "model": patient.model,
            "models": patient_models,
            "props": patient_props,
            "temperature": patient.temperature,
            "top_p": patient.top_p,
            "max_tokens": patient.max_tokens,
            "seed_override": args.seed,
            "enable_thinking": False,
        },
        "voice": {
            "patient_tts": args.patient_tts,
            "qwen_tts_url": args.qwen_tts_url,
            "piper_tts_url": args.piper_tts_url,
            "qwen_speaker": args.qwen_speaker,
            "qwen_language": args.qwen_language,
            "qwen_seed": args.qwen_seed,
            "observer_asr_url": args.observer_asr_url,
            "media_bind": args.voice_media_bind,
            "media_port": args.voice_media_port,
            "answer_timeout_seconds": args.voice_answer_timeout,
            "greeting_wait_seconds": args.voice_greeting_wait,
            "response_timeout_seconds": args.voice_response_timeout,
            "listen_only_seconds": args.voice_listen_only_seconds,
            "reference_test": {
                "enabled": args.voice_reference_test,
                "rx_window_seconds": args.voice_reference_seconds,
                "text": args.voice_reference_text if args.voice_reference_wav is None else None,
                "wav": str(args.voice_reference_wav.resolve()) if args.voice_reference_wav is not None else None,
                "vad_controls_flow": False,
                "barge_in": False,
                "comfort_noise": False,
            },
            "duplex": {
                "mode": "strict_half_duplex_asterisk_timed",
                "comfort_noise_rms": args.voice_comfort_noise_rms,
                "spontaneous_greeting_required": True,
                "barge_in": False,
                "wakeup_salutation": False,
                "tx_pacing_ms": VOICE_FRAME_MS,
            },
            "continuous_rx_capture": True,
            "vad": dataclasses.asdict(vad),
        },
        "execution": {"max_parallel": 1, "fail_fast": args.fail_fast, "show_dialog": args.show_dialog, "timeout_seconds": args.timeout},
        "scenarios": [
            {
                "scenario_id": scenario.scenario_id,
                "source_file": scenario.path.name,
                "sha256": scenario.source_sha256,
                "seed": args.seed if args.seed is not None else scenario.data["simulation"]["seed"],
            }
            for scenario in scenarios
        ],
        "results": [],
    }
    write_json(stage / "manifest.json", manifest)
    outcomes: list[ScenarioOutcome] = []
    try:
        for scenario in scenarios:
            outcome = run_voice_scenario(
                scenario,
                stage / "scenarios",
                patient=patient,
                patient_system_prompt=patient_prompt,
                seed_override=args.seed,
                voice=voice,
                show_dialog=args.show_dialog,
            )
            outcomes.append(outcome)
            line = f"{outcome.scenario_id}: {'TECHNISCH PASS' if outcome.technical_pass else 'TECHNISCH FAIL'}"
            if not outcome.technical_pass and outcome.error_summary:
                line += f" – {outcome.error_summary}"
            print(line)
            if args.fail_fast and not outcome.technical_pass:
                break
        failures = [outcome for outcome in outcomes if not outcome.technical_pass]
        manifest["results"] = [
            {
                "scenario_id": outcome.scenario_id,
                "technical_status": "PASS" if outcome.technical_pass else "FAIL",
                "terminal_reason": outcome.terminal_reason,
                "error_summary": outcome.error_summary,
            }
            for outcome in outcomes
        ]
        manifest["status"] = "technical_failures" if failures else "complete"
        manifest["finished_at"] = now_iso()
        manifest["summary"] = {
            "selected": len(scenarios),
            "executed": len(outcomes),
            "technical_pass": len(outcomes) - len(failures),
            "technical_fail": len(failures),
            "semantic_pass": None,
        }
        write_json(stage / "manifest.json", manifest)
        write_bundle(stage, stage / "bundle")
        manifest["artifact_hashes"] = immutable_artifact_hashes(stage)
        write_json(stage / "manifest.json", manifest)
        os.replace(stage, final_dir)
        print(f"Run abgeschlossen: {final_dir}")
        print(f"Technisch PASS: {len(outcomes) - len(failures)}, technisch FAIL: {len(failures)}; semantisch: nicht bewertet")
        return 1 if failures else 0
    except BaseException:
        print(f"Unvollständiger Run verbleibt geschützt unter: {stage}", file=sys.stderr)
        raise


def default_paths() -> dict[str, Path]:
    root = Path(__file__).resolve().parent
    package = root / "kienzlefon-testsuite-spec-v1"
    return {
        "root": root,
        "package": package,
        "scenarios": package / "scenarios",
        "schema": package / "schemas" / "scenario.schema.json",
        "package_manifest": package / "PACKAGE_MANIFEST.json",
        "patient_prompt": package
        / "templates"
        / "patient-simulator-system.txt",
        "evaluator": package
        / "templates"
        / "external-evaluator-instructions.md",
    }


def build_parser() -> argparse.ArgumentParser:
    defaults = default_paths()
    parser = argparse.ArgumentParser(
        description=(
            "Technische Dialog-, Voice- und Regressionstests. Direct nutzt "
            "kienzlefon-ai-text-v1; Voice führt einen echten Asterisk-Telefonanruf. "
            "Es findet keine lokale semantische Bewertung statt."
        )
    )
    parser.add_argument("--version", action="version", version=VERSION)
    parser.add_argument("--scenarios", type=Path, default=defaults["scenarios"])
    parser.add_argument("--schema", type=Path, default=defaults["schema"])
    parser.add_argument(
        "--package-manifest", type=Path, default=defaults["package_manifest"]
    )
    parser.add_argument("--target-mode", choices=("direct", "voice"), default="direct")
    parser.add_argument("--target-number")
    parser.add_argument("--backend-url", default="http://127.0.0.1:8300")
    parser.add_argument("--asterisk-endpoint", default=DEFAULT_VOICE_ASTERISK_ENDPOINT)
    parser.add_argument("--asterisk-ws-connection", default=DEFAULT_VOICE_WS_CONNECTION)
    parser.add_argument("--voice-media-bind", default=DEFAULT_VOICE_MEDIA_BIND)
    parser.add_argument("--voice-media-port", type=int, default=DEFAULT_VOICE_MEDIA_PORT)
    parser.add_argument("--observer-asr-url", default=DEFAULT_VOICE_ASR_URL)
    parser.add_argument("--patient-tts", choices=("qwen", "piper"), default="qwen")
    parser.add_argument("--qwen-tts-url", default=DEFAULT_VOICE_QWEN_URL)
    parser.add_argument("--piper-tts-url", default=DEFAULT_VOICE_PIPER_URL)
    parser.add_argument("--qwen-speaker", default=DEFAULT_VOICE_QWEN_SPEAKER)
    parser.add_argument("--qwen-language", default=DEFAULT_VOICE_QWEN_LANGUAGE)
    parser.add_argument("--qwen-seed", type=int, default=DEFAULT_VOICE_QWEN_SEED)
    parser.add_argument("--voice-answer-timeout", type=float, default=DEFAULT_VOICE_ANSWER_TIMEOUT)
    parser.add_argument("--voice-greeting-wait", type=float, default=DEFAULT_VOICE_GREETING_WAIT)
    parser.add_argument(
        "--voice-wakeup-text",
        default=DEFAULT_VOICE_WAKEUP_TEXT,
        help="Kompatibilitaetsoption; in v1.2.2 half-duplex nicht verwendet",
    )
    parser.add_argument("--voice-response-timeout", type=float, default=DEFAULT_VOICE_RESPONSE_TIMEOUT)
    parser.add_argument("--voice-asr-timeout", type=float, default=DEFAULT_VOICE_ASR_TIMEOUT)
    parser.add_argument("--voice-tts-timeout", type=float, default=DEFAULT_VOICE_TTS_TIMEOUT)
    parser.add_argument("--voice-dial-timeout", type=int, default=DEFAULT_VOICE_DIAL_TIMEOUT)
    parser.add_argument(
        "--voice-listen-only-seconds",
        type=float,
        default=DEFAULT_VOICE_LISTEN_ONLY_SECONDS,
        help="Voice-Diagnose: Ziel anrufen, N Sekunden nur rohes RX-Audio aufzeichnen, keine Patient-TTS senden",
    )
    parser.add_argument(
        "--voice-reference-test",
        action="store_true",
        help=(
            "Deterministische Diagnose: feste RX-Aufnahme, vorbereitete WAV abspielen, "
            "zweite feste RX-Aufnahme; keine VAD-/Barge-in-Steuerung"
        ),
    )
    parser.add_argument(
        "--voice-reference-seconds",
        type=float,
        default=DEFAULT_VOICE_REFERENCE_SECONDS,
        help="Laenge jedes RX-only Referenzfensters in Sekunden (Default: 12)",
    )
    parser.add_argument(
        "--voice-reference-text",
        default=DEFAULT_VOICE_REFERENCE_TEXT,
        help="Text fuer die vor dem Anruf komplett erzeugte Referenz-WAV",
    )
    parser.add_argument(
        "--voice-reference-wav",
        type=Path,
        help="Optionale fertige mono PCM16/16-kHz WAV statt Qwen-Referenztext",
    )
    parser.add_argument("--voice-energy-threshold", type=int, default=DEFAULT_VOICE_ENERGY_THRESHOLD)
    parser.add_argument(
        "--voice-comfort-noise-rms",
        type=int,
        default=DEFAULT_VOICE_COMFORT_NOISE_RMS,
        help="RMS level of synthetic microphone room tone sent during RX-only phases; 0 disables",
    )
    parser.add_argument("--voice-preroll-ms", type=int, default=DEFAULT_VOICE_PREROLL_MS)
    parser.add_argument("--voice-speech-start-ms", type=int, default=DEFAULT_VOICE_SPEECH_START_MS)
    parser.add_argument("--voice-speech-end-ms", type=int, default=DEFAULT_VOICE_SPEECH_END_MS)
    parser.add_argument("--voice-min-utterance-ms", type=int, default=DEFAULT_VOICE_MIN_UTTERANCE_MS)
    parser.add_argument("--voice-max-utterance-ms", type=int, default=DEFAULT_VOICE_MAX_UTTERANCE_MS)
    parser.add_argument(
        "--patient-llm-url",
        default="http://127.0.0.1:8080/v1/chat/completions",
    )
    parser.add_argument("--patient-model")
    parser.add_argument(
        "--patient-prompt", type=Path, default=defaults["patient_prompt"]
    )
    parser.add_argument("--patient-prompt-version", default=VERSION)
    parser.add_argument(
        "--external-evaluator-instructions",
        type=Path,
        default=defaults["evaluator"],
    )
    parser.add_argument(
        "--channel", choices=("telephone", "chat"), default="telephone"
    )
    parser.add_argument("--scenario", action="append", default=[])
    parser.add_argument("--tag", action="append", default=[])
    parser.add_argument("--seed", type=int)
    parser.add_argument(
        "--max-parallel", type=int, default=1, choices=range(1, 65)
    )
    parser.add_argument("--fail-fast", action="store_true")
    parser.add_argument(
        "--show-dialog",
        action="store_true",
        help=(
            "shows synthetic patient and assistant turns live; "
            "requires --max-parallel 1"
        ),
    )
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument(
        "--patient-temperature", type=float, default=DEFAULT_PATIENT_TEMPERATURE
    )
    parser.add_argument("--patient-top-p", type=float, default=DEFAULT_PATIENT_TOP_P)
    parser.add_argument(
        "--patient-max-tokens", type=int, default=DEFAULT_PATIENT_MAX_TOKENS
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument("--run-id")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--bundle-only", type=Path)
    parser.add_argument(
        "--confirm-synthetic-test-data",
        action="store_true",
        help="required for execution; confirms that all scenario identities are synthetic",
    )
    return parser


def validate_numeric_options(args: argparse.Namespace) -> None:
    if args.timeout <= 0:
        raise ConfigurationError("--timeout must be positive")
    if not 0 <= args.patient_temperature <= 2:
        raise ConfigurationError("--patient-temperature must be between 0 and 2")
    if not 0 < args.patient_top_p <= 1:
        raise ConfigurationError("--patient-top-p must be greater than 0 and at most 1")
    if not 1 <= args.patient_max_tokens <= 4096:
        raise ConfigurationError("--patient-max-tokens must be between 1 and 4096")


def run_direct_normal(args: argparse.Namespace) -> int:
    validate_numeric_options(args)
    if not args.confirm_synthetic_test_data:
        raise ConfigurationError(
            "execution requires --confirm-synthetic-test-data"
        )
    if args.show_dialog and args.max_parallel != 1:
        raise ConfigurationError("--show-dialog requires --max-parallel 1")
    assert_loopback_url(args.backend_url, "--backend-url")
    assert_loopback_url(args.patient_llm_url, "--patient-llm-url")
    package_manifest = verify_package_manifest(args.package_manifest.resolve())
    verify_scenario_index(args.scenarios.resolve())
    scenarios = load_scenarios(
        args.scenarios.resolve(),
        args.schema.resolve(),
        channel=args.channel,
        selected_ids=args.scenario,
        selected_tags=args.tag,
    )
    root = Path(__file__).resolve().parent
    patient_path = args.patient_prompt.resolve()
    evaluator_path = args.external_evaluator_instructions.resolve()
    patient_bytes = patient_path.read_bytes()
    evaluator_bytes = evaluator_path.read_bytes()
    try:
        patient_prompt = patient_bytes.decode("utf-8")
        evaluator_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConfigurationError("a prompt/template file is not valid UTF-8") from exc
    runtime = RuntimeClient(args.backend_url, args.timeout)
    health = runtime.health()
    if (
        not isinstance(health.data, Mapping)
        or health.data.get("ok") is not True
        or not isinstance(health.data.get("version"), str)
    ):
        raise ContractError("runtime health response is invalid")
    metadata_payload = runtime.metadata()
    metadata = validate_runtime_metadata(
        metadata_payload.data,
        channel=args.channel,
    )
    assert_loopback_url(metadata["llm_url"], "runtime LLM URL")
    patient = PatientLLMClient(
        args.patient_llm_url,
        args.timeout,
        model=args.patient_model,
        temperature=args.patient_temperature,
        top_p=args.patient_top_p,
        max_tokens=args.patient_max_tokens,
    )
    patient_models: dict[str, Any] | None = None
    if patient.model is None:
        patient.model, patient_models = patient.discover_model()
    else:
        try:
            _, patient_models = patient.discover_model()
        except TestsuiteError:
            patient_models = None
    patient_props = patient.try_props()
    backend_models = discover_models_from_url(metadata["llm_url"], args.timeout)
    output_root = (args.output or (root / "runs")).resolve()
    ensure_private_dir(output_root)
    run_id = safe_run_id(
        args.run_id
        or f"{utc_run_stamp()}_{args.channel}_{uuid.uuid4().hex[:8]}"
    )
    final_dir = output_root / run_id
    if final_dir.exists():
        raise ConfigurationError(f"{final_dir}: run already exists")
    stage = output_root / f".{run_id}.incomplete-{uuid.uuid4().hex[:8]}"
    ensure_private_dir(stage)
    ensure_private_dir(stage / "scenarios")
    ensure_private_dir(stage / "evaluations")
    prompt_metadata = prepare_prompt_artifacts(
        stage,
        metadata=metadata,
        channel=args.channel,
        patient_prompt_bytes=patient_bytes,
        evaluator_instructions=evaluator_bytes,
        patient_prompt_version=args.patient_prompt_version,
        patient_prompt_source=patient_path,
    )
    started_at = now_iso()
    manifest: dict[str, Any] = {
        "protocol": RUN_PROTOCOL,
        "testsuite_version": VERSION,
        "run_id": run_id,
        "status": "running",
        "started_at": started_at,
        "finished_at": None,
        "channel": args.channel,
        "target_mode": "direct",
        "synthetic_test_data_only": True,
        "semantic_evaluation": "NOT_PERFORMED",
        "scenario_format_version": SCENARIO_FORMAT_VERSION,
        "scenario_package": {
            "package": package_manifest.get("package"),
            "format_version": package_manifest.get("format_version"),
            "manifest_sha256": sha256_file(args.package_manifest.resolve()),
        },
        "kienzlefon_prompt": prompt_metadata["kienzlefon_system"],
        "patient_prompt": prompt_metadata["patient_simulator_system"],
        "channel_overlay": prompt_metadata["channel_overlay"],
        "backend": {
            "name": "kienzlefon-ai",
            "protocol": TEXT_PROTOCOL,
            "version": metadata["backend_version"],
            "url": args.backend_url,
            "git_commit": detect_git_commit(root),
            "health": deep_json_copy(health.data),
        },
        "kienzlefon_model": {
            "llm_url": metadata["llm_url"],
            "models": backend_models,
            "inference": deep_json_copy(metadata["inference"]),
        },
        "patient_model": {
            "endpoint": args.patient_llm_url,
            "model": patient.model,
            "models": patient_models,
            "props": patient_props,
            "temperature": patient.temperature,
            "top_p": patient.top_p,
            "max_tokens": patient.max_tokens,
            "seed_override": args.seed,
            "enable_thinking": False,
        },
        "execution": {
            "max_parallel": args.max_parallel,
            "fail_fast": args.fail_fast,
            "show_dialog": args.show_dialog,
            "timeout_seconds": args.timeout,
        },
        "scenarios": [
            {
                "scenario_id": scenario.scenario_id,
                "source_file": scenario.path.name,
                "sha256": scenario.source_sha256,
                "seed": (
                    args.seed
                    if args.seed is not None
                    else scenario.data["simulation"]["seed"]
                ),
            }
            for scenario in scenarios
        ],
        "results": [],
    }
    write_json(stage / "manifest.json", manifest)
    settings = RunSettings(
        args.channel,
        runtime,
        patient,
        patient_prompt,
        args.seed,
        show_dialog=args.show_dialog,
    )
    try:
        outcomes = run_parallel_scenarios(
            scenarios,
            stage / "scenarios",
            settings,
            max_parallel=args.max_parallel,
            fail_fast=args.fail_fast,
        )
        failures = [outcome for outcome in outcomes if not outcome.technical_pass]
        manifest["results"] = [
            {
                "scenario_id": outcome.scenario_id,
                "technical_status": (
                    "PASS" if outcome.technical_pass else "FAIL"
                ),
                "terminal_reason": outcome.terminal_reason,
                "error_summary": outcome.error_summary,
            }
            for outcome in outcomes
        ]
        manifest["status"] = "technical_failures" if failures else "complete"
        manifest["finished_at"] = now_iso()
        manifest["summary"] = {
            "selected": len(scenarios),
            "executed": len(outcomes),
            "technical_pass": len(outcomes) - len(failures),
            "technical_fail": len(failures),
            "semantic_pass": None,
        }
        write_json(stage / "manifest.json", manifest)
        write_bundle(stage, stage / "bundle")
        manifest["artifact_hashes"] = immutable_artifact_hashes(stage)
        write_json(stage / "manifest.json", manifest)
        os.replace(stage, final_dir)
        print(f"Run abgeschlossen: {final_dir}")
        print(
            f"Technisch PASS: {len(outcomes) - len(failures)}, "
            f"technisch FAIL: {len(failures)}; semantisch: nicht bewertet"
        )
        return 1 if failures else 0
    except BaseException:
        print(
            f"Unvollständiger Run verbleibt geschützt unter: {stage}",
            file=sys.stderr,
        )
        raise


def run_normal(args: argparse.Namespace) -> int:
    if args.target_mode == "voice":
        return run_voice_normal(args)
    return run_direct_normal(args)


def run_validate_only(args: argparse.Namespace) -> int:
    verify_package_manifest(args.package_manifest.resolve())
    verify_scenario_index(args.scenarios.resolve())
    scenarios = load_scenarios(
        args.scenarios.resolve(),
        args.schema.resolve(),
        channel=args.channel,
        selected_ids=args.scenario,
        selected_tags=args.tag,
    )
    print(
        f"{len(scenarios)} Szenarien für Kanal {args.channel} technisch validiert."
    )
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    os.umask(0o077)
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.bundle_only is not None:
            if args.validate_only:
                raise ConfigurationError(
                    "--bundle-only and --validate-only are mutually exclusive"
                )
            return run_bundle_only(args.bundle_only.resolve(), args.output)
        if args.validate_only:
            return run_validate_only(args)
        return run_normal(args)
    except TestsuiteError as exc:
        print(f"FEHLER: {safe_error_summary(exc)}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("ABBRUCH: unterbrochen", file=sys.stderr)
        return 130
    except Exception as exc:
        print(
            f"INTERNER FEHLER: {type(exc).__name__}",
            file=sys.stderr,
        )
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
