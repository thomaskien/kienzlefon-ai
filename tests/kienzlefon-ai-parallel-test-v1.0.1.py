#!/usr/bin/env python3
"""Parallel load test for the Kienzlefon AI pipeline test suite.

The program starts multiple independent instances of the existing single-
utterance pipeline client. It neither installs nor starts services. Every worker
gets separate PCM and JSON output paths; worker stdout/stderr is suppressed,
never displayed, captured, or persisted in the aggregate report.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import math
import os
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Iterable, Mapping, NoReturn


PROGRAM_VERSION = "1.0.1"
DEFAULT_CONCURRENCY = (1, 2, 4)
DEFAULT_GPU_SAMPLE_MS = 200
DEFAULT_PHASE_TIMEOUT_SECONDS = 600.0
DEFAULT_COOLDOWN_SECONDS = 5.0

SELECTED_METRICS = (
    "asr_total_latency_seconds",
    "asr_tail_latency_seconds",
    "asr_time_to_first_confirmed_seconds",
    "llm_time_to_first_token_seconds",
    "time_to_first_speakable_section_seconds",
    "tts_time_to_first_audio_seconds",
    "post_asr_to_first_pcm_seconds",
    "post_audio_end_to_first_pcm_seconds",
    "total_time_to_first_pcm_block_seconds",
    "llm_output_tokens_per_second",
    "tts_realtime_factor",
    "pipeline_total_seconds",
)


class ParallelTestError(RuntimeError):
    """Expected orchestration or input error."""


def finite_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    result = float(value)
    return result if math.isfinite(result) else None


def percentile(values: Iterable[float], fraction: float) -> float | None:
    ordered = sorted(float(value) for value in values if math.isfinite(float(value)))
    if not ordered:
        return None
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def summarize_numbers(values: Iterable[float]) -> dict[str, float | int] | None:
    cleaned = [float(value) for value in values if math.isfinite(float(value))]
    if not cleaned:
        return None
    return {
        "count": len(cleaned),
        "min": min(cleaned),
        "mean": statistics.fmean(cleaned),
        "median": statistics.median(cleaned),
        "p95": percentile(cleaned, 0.95) or 0.0,
        "max": max(cleaned),
    }


class NvidiaMonitor:
    """Sample one NVIDIA GPU without making GPU monitoring a test dependency."""

    QUERY_FIELDS = (
        "name",
        "memory.used",
        "memory.total",
        "utilization.gpu",
        "power.draw",
        "temperature.gpu",
    )

    def __init__(self, *, gpu_index: int, interval_ms: int) -> None:
        self.gpu_index = gpu_index
        self.interval_seconds = interval_ms / 1000.0 if interval_ms else 0.0
        self.executable = shutil.which("nvidia-smi")
        self.samples: list[dict[str, Any]] = []
        self.last_error: str | None = None
        self._phase_start_ns: int | None = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self, phase_start_ns: int) -> None:
        self._phase_start_ns = phase_start_ns
        if self.executable is None or self.interval_seconds <= 0:
            if self.executable is None:
                self.last_error = "nvidia-smi nicht gefunden"
            return
        self._sample_once()
        self._thread = threading.Thread(
            target=self._run,
            name="kienzlefon-nvidia-monitor",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=max(4.0, self.interval_seconds * 4.0))
            self._thread = None
        if self.executable is not None and self.interval_seconds > 0:
            self._sample_once()

    def _run(self) -> None:
        while not self._stop.wait(self.interval_seconds):
            self._sample_once()

    def _sample_once(self) -> None:
        if self.executable is None or self._phase_start_ns is None:
            return
        command = [
            self.executable,
            "--id",
            str(self.gpu_index),
            "--query-gpu=" + ",".join(self.QUERY_FIELDS),
            "--format=csv,noheader,nounits",
        ]
        try:
            completed = subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=3.0,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            self.last_error = f"nvidia-smi konnte nicht abgefragt werden: {exc}"
            return
        if completed.returncode != 0:
            detail = completed.stderr.strip().replace("\n", " ")[:300]
            self.last_error = f"nvidia-smi Exit {completed.returncode}: {detail or 'keine Details'}"
            return
        rows = list(csv.reader(completed.stdout.splitlines()))
        if not rows or len(rows[0]) != len(self.QUERY_FIELDS):
            self.last_error = "nvidia-smi lieferte ein unerwartetes CSV-Format"
            return
        row = [value.strip() for value in rows[0]]
        sample = {
            "seconds_from_phase_start": (
                time.perf_counter_ns() - self._phase_start_ns
            )
            / 1_000_000_000.0,
            "name": row[0],
            "memory_used_mib": parse_nvidia_number(row[1]),
            "memory_total_mib": parse_nvidia_number(row[2]),
            "utilization_gpu_percent": parse_nvidia_number(row[3]),
            "power_draw_watts": parse_nvidia_number(row[4]),
            "temperature_gpu_celsius": parse_nvidia_number(row[5]),
        }
        self.samples.append(sample)

    def summary(self) -> dict[str, Any]:
        if not self.samples:
            return {
                "available": False,
                "sample_count": 0,
                "gpu_index": self.gpu_index,
                "reason": self.last_error or "GPU-Monitoring deaktiviert",
            }
        keys = (
            "memory_used_mib",
            "utilization_gpu_percent",
            "power_draw_watts",
            "temperature_gpu_celsius",
        )
        summaries: dict[str, Any] = {}
        for key in keys:
            values = [
                number
                for sample in self.samples
                if (number := finite_number(sample.get(key))) is not None
            ]
            summaries[key] = summarize_numbers(values)
        baseline = self.samples[0]
        return {
            "available": True,
            "sample_count": len(self.samples),
            "gpu_index": self.gpu_index,
            "gpu_name": baseline.get("name"),
            "memory_total_mib": baseline.get("memory_total_mib"),
            "baseline": {
                key: baseline.get(key)
                for key in keys
            },
            "summary": summaries,
            "last_error": self.last_error,
        }


def parse_nvidia_number(value: str) -> float | None:
    normalized = value.strip()
    if not normalized or normalized.upper() in {"N/A", "[N/A]", "NOT SUPPORTED"}:
        return None
    try:
        result = float(normalized)
    except ValueError:
        return None
    return result if math.isfinite(result) else None


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    default_pipeline = Path(__file__).resolve().with_name(
        "kienzlefon-ai-pipeline-test-v1.2.1.py"
    )
    parser = argparse.ArgumentParser(
        description=(
            "Startet die vorhandene Kienzlefon-Pipeline-Testsuite parallel mit "
            "getrennten Clients und erzeugt einen inhaltsfreien Sammelbericht."
        )
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {PROGRAM_VERSION}")
    parser.add_argument("--input", required=True, type=Path, help="Raw-PCM-Referenzaufnahme")
    parser.add_argument("--output-dir", required=True, type=Path, help="Basisverzeichnis für einen neuen Testlauf")
    parser.add_argument(
        "--pipeline-script",
        type=Path,
        default=default_pipeline,
        help=f"Einzeltest-Skript (Standard: {default_pipeline.name})",
    )
    parser.add_argument(
        "--python",
        default=sys.executable,
        help="Python-Interpreter für Worker (Standard: aktueller Interpreter)",
    )
    parser.add_argument(
        "--concurrency",
        nargs="+",
        type=int,
        default=list(DEFAULT_CONCURRENCY),
        metavar="N",
        help="Parallelitätsstufen (Standard: 1 2 4)",
    )
    parser.add_argument("--repetitions", type=int, default=1, help="Wiederholungen je Parallelitätsstufe")
    parser.add_argument("--tts", choices=("qwen", "piper"), default="qwen")
    parser.add_argument("--asr-url", default="ws://127.0.0.1:8178/v1/asr/stream")
    parser.add_argument("--llm-url", default="http://127.0.0.1:8080/v1/chat/completions")
    parser.add_argument("--tts-url", help="Optionaler TTS-Endpunkt; sonst verwendet die Einzeltestsuite ihren Standard")
    parser.add_argument("--asr-chunk-ms", type=int, default=500)
    parser.add_argument(
        "--realtime-input",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="ASR-Audio in natürlicher Geschwindigkeit senden (Standard: aktiviert)",
    )
    parser.add_argument("--input-rate", type=int, default=16_000)
    parser.add_argument("--input-channels", type=int, default=1)
    parser.add_argument("--qwen-speaker", default="ryan")
    parser.add_argument("--qwen-language", default="German")
    parser.add_argument("--qwen-seed", type=int, default=42)
    parser.add_argument("--system-prompt", help="Optionaler Systemprompt; sonst Standard der Einzeltestsuite")
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--phase-timeout", type=float, default=DEFAULT_PHASE_TIMEOUT_SECONDS)
    parser.add_argument("--cooldown-seconds", type=float, default=DEFAULT_COOLDOWN_SECONDS)
    parser.add_argument("--gpu-index", type=int, default=0)
    parser.add_argument(
        "--gpu-sample-ms",
        type=int,
        default=DEFAULT_GPU_SAMPLE_MS,
        help="NVIDIA-Messintervall in ms; 0 deaktiviert GPU-Monitoring",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Konfiguration prüfen, aber keine Worker starten und keine Dateien anlegen",
    )
    args = parser.parse_args(argv)

    if not args.concurrency or any(value < 1 or value > 64 for value in args.concurrency):
        parser.error("--concurrency benötigt Werte zwischen 1 und 64")
    if len(set(args.concurrency)) != len(args.concurrency):
        parser.error("--concurrency enthält doppelte Stufen")
    if not 1 <= args.repetitions <= 100:
        parser.error("--repetitions muss zwischen 1 und 100 liegen")
    if not 20 <= args.asr_chunk_ms <= 2000:
        parser.error("--asr-chunk-ms muss zwischen 20 und 2000 liegen")
    if args.input_rate <= 0:
        parser.error("--input-rate muss größer als 0 sein")
    if not 1 <= args.input_channels <= 32:
        parser.error("--input-channels muss zwischen 1 und 32 liegen")
    if args.qwen_seed < 0:
        parser.error("--qwen-seed muss >= 0 sein")
    if args.max_tokens <= 0:
        parser.error("--max-tokens muss größer als 0 sein")
    if not math.isfinite(args.temperature) or args.temperature < 0:
        parser.error("--temperature muss eine endliche Zahl >= 0 sein")
    if not math.isfinite(args.phase_timeout) or args.phase_timeout <= 0:
        parser.error("--phase-timeout muss größer als 0 sein")
    if not math.isfinite(args.cooldown_seconds) or args.cooldown_seconds < 0:
        parser.error("--cooldown-seconds muss >= 0 sein")
    if args.gpu_index < 0:
        parser.error("--gpu-index muss >= 0 sein")
    if args.gpu_sample_ms != 0 and not 100 <= args.gpu_sample_ms <= 10_000:
        parser.error("--gpu-sample-ms muss 0 oder ein Wert zwischen 100 und 10000 sein")
    if not args.python.strip():
        parser.error("--python darf nicht leer sein")
    return args


def validate_inputs(args: argparse.Namespace) -> str:
    if not args.input.is_file():
        raise ParallelTestError(f"Eingabedatei fehlt: {args.input}")
    if args.input.stat().st_size == 0:
        raise ParallelTestError(f"Eingabedatei ist leer: {args.input}")
    if not args.pipeline_script.is_file():
        raise ParallelTestError(f"Pipeline-Skript fehlt: {args.pipeline_script}")
    python = shutil.which(args.python) if os.sep not in args.python else args.python
    if python is None or not Path(python).is_file() or not os.access(python, os.X_OK):
        raise ParallelTestError(f"Python-Interpreter nicht ausführbar: {args.python}")
    args.python = str(Path(python).resolve())
    args.input = args.input.resolve()
    args.pipeline_script = args.pipeline_script.resolve()
    try:
        completed = subprocess.run(
            [args.python, str(args.pipeline_script), "--version"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10.0,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ParallelTestError(f"Pipeline-Version konnte nicht geprüft werden: {exc}") from exc
    if completed.returncode != 0:
        detail = completed.stderr.strip().replace("\n", " ")[:500]
        raise ParallelTestError(
            f"Pipeline --version fehlgeschlagen (Exit {completed.returncode}): {detail}"
        )
    version_line = completed.stdout.strip()
    if not version_line:
        raise ParallelTestError("Pipeline --version lieferte keine Ausgabe")
    return version_line


def create_run_directory(base: Path) -> Path:
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_id = uuid.uuid4().hex[:8]
    run_dir = base.resolve() / f"parallel-run-{timestamp}-{run_id}"
    run_dir.mkdir(parents=True, exist_ok=False)
    return run_dir


def build_worker_command(
    args: argparse.Namespace,
    *,
    output_path: Path,
    report_path: Path,
) -> list[str]:
    command = [
        args.python,
        str(args.pipeline_script),
        "--input",
        str(args.input),
        "--asr-url",
        args.asr_url,
        "--asr-chunk-ms",
        str(args.asr_chunk_ms),
        "--llm-url",
        args.llm_url,
        "--tts",
        args.tts,
        "--output",
        str(output_path),
        "--report",
        str(report_path),
        "--input-rate",
        str(args.input_rate),
        "--input-channels",
        str(args.input_channels),
        "--max-tokens",
        str(args.max_tokens),
        "--temperature",
        str(args.temperature),
    ]
    if args.realtime_input:
        command.append("--realtime-input")
    if args.tts_url:
        command.extend(["--tts-url", args.tts_url])
    if args.tts == "qwen":
        command.extend(
            [
                "--qwen-speaker",
                args.qwen_speaker,
                "--qwen-language",
                args.qwen_language,
                "--qwen-seed",
                str(args.qwen_seed),
            ]
        )
    if args.system_prompt is not None:
        command.extend(["--system-prompt", args.system_prompt])
    return command


def terminate_processes(records: list[dict[str, Any]]) -> None:
    for record in records:
        process: subprocess.Popen[bytes] = record["process"]
        if process.poll() is None:
            try:
                process.terminate()
            except OSError:
                pass
    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        if all(record["process"].poll() is not None for record in records):
            return
        time.sleep(0.05)
    for record in records:
        process = record["process"]
        if process.poll() is None:
            try:
                process.kill()
            except OSError:
                pass


def read_json_mapping(path: Path) -> Mapping[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, Mapping) else None


def extract_worker_metrics(report: Mapping[str, Any]) -> dict[str, float]:
    metrics = report.get("metrics")
    result: dict[str, float] = {}
    if isinstance(metrics, Mapping):
        for key in SELECTED_METRICS:
            number = finite_number(metrics.get(key))
            if number is not None:
                result[key] = number

    events = report.get("events_seconds_from_T0")
    asr_events = report.get("asr_events_seconds_from_T0")
    if isinstance(events, Mapping):
        first_pcm = finite_number(events.get("T7"))
        asr_complete = finite_number(events.get("T2"))
        if first_pcm is not None and asr_complete is not None and first_pcm >= asr_complete:
            result["post_asr_to_first_pcm_seconds"] = first_pcm - asr_complete
        if isinstance(asr_events, Mapping):
            audio_end = finite_number(asr_events.get("ASR_AUDIO_END"))
            if first_pcm is not None and audio_end is not None and first_pcm >= audio_end:
                result["post_audio_end_to_first_pcm_seconds"] = first_pcm - audio_end
    return result


def worker_result(record: dict[str, Any]) -> dict[str, Any]:
    process: subprocess.Popen[bytes] = record["process"]
    report_path: Path = record["report_path"]
    report = read_json_mapping(report_path)
    report_status = report.get("status") if report else None
    success = process.returncode == 0 and report_status == "ok"
    error_summary: dict[str, Any] | None = None
    if report and isinstance(report.get("error"), Mapping):
        error = report["error"]
        error_summary = {
            "service": error.get("service"),
            "category": error.get("category"),
            "exit_code": error.get("exit_code"),
        }
    return {
        "worker": record["worker"],
        "pid": process.pid,
        "exit_code": process.returncode,
        "success": success,
        "report_status": report_status,
        "duration_seconds": (
            record["finished_ns"] - record["launched_ns"]
        )
        / 1_000_000_000.0,
        "output_pcm": str(record["output_path"]),
        "output_metadata": str(Path(str(record["output_path"]) + ".json")),
        "worker_report": str(report_path),
        "metrics": extract_worker_metrics(report) if report else {},
        "error": error_summary,
    }


def aggregate_worker_metrics(workers: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    collected: dict[str, list[float]] = {key: [] for key in SELECTED_METRICS}
    for worker in workers:
        if worker.get("success") is not True:
            continue
        metrics = worker.get("metrics")
        if not isinstance(metrics, Mapping):
            continue
        for key in SELECTED_METRICS:
            number = finite_number(metrics.get(key))
            if number is not None:
                collected[key].append(number)
    return {
        key: summary
        for key, values in collected.items()
        if (summary := summarize_numbers(values)) is not None
    }


def run_phase(
    args: argparse.Namespace,
    *,
    run_dir: Path,
    concurrency: int,
    repetition: int,
) -> dict[str, Any]:
    phase_name = f"concurrency-{concurrency:02d}-run-{repetition:02d}"
    phase_dir = run_dir / phase_name
    phase_dir.mkdir(parents=False, exist_ok=False)
    print(f"\n=== {phase_name}: starte {concurrency} Worker ===", flush=True)

    phase_start_ns = time.perf_counter_ns()
    monitor = NvidiaMonitor(gpu_index=args.gpu_index, interval_ms=args.gpu_sample_ms)
    monitor.start(phase_start_ns)
    records: list[dict[str, Any]] = []
    timed_out = False
    try:
        for worker_index in range(1, concurrency + 1):
            output_path = phase_dir / f"worker-{worker_index:02d}.pcm"
            report_path = phase_dir / f"worker-{worker_index:02d}-benchmark.json"
            command = build_worker_command(
                args,
                output_path=output_path,
                report_path=report_path,
            )
            launched_ns = time.perf_counter_ns()
            process = subprocess.Popen(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            records.append(
                {
                    "worker": worker_index,
                    "process": process,
                    "launched_ns": launched_ns,
                    "finished_ns": None,
                    "output_path": output_path,
                    "report_path": report_path,
                }
            )
            print(f"Worker {worker_index:02d}: PID {process.pid}", flush=True)

        deadline = time.monotonic() + args.phase_timeout
        while True:
            all_finished = True
            now_ns = time.perf_counter_ns()
            for record in records:
                process = record["process"]
                if process.poll() is None:
                    all_finished = False
                elif record["finished_ns"] is None:
                    record["finished_ns"] = now_ns
            if all_finished:
                break
            if time.monotonic() >= deadline:
                timed_out = True
                terminate_processes(records)
                now_ns = time.perf_counter_ns()
                for record in records:
                    record["process"].wait()
                    if record["finished_ns"] is None:
                        record["finished_ns"] = now_ns
                break
            time.sleep(0.05)
    except KeyboardInterrupt:
        terminate_processes(records)
        for record in records:
            record["process"].wait()
            if record["finished_ns"] is None:
                record["finished_ns"] = time.perf_counter_ns()
        raise
    except OSError as exc:
        terminate_processes(records)
        for record in records:
            record["process"].wait()
            if record["finished_ns"] is None:
                record["finished_ns"] = time.perf_counter_ns()
        raise ParallelTestError(f"Worker-Prozess konnte nicht ausgeführt werden: {exc}") from exc
    finally:
        monitor.stop()

    phase_end_ns = time.perf_counter_ns()
    for record in records:
        process = record["process"]
        if process.returncode is None:
            process.wait()
        if record["finished_ns"] is None:
            record["finished_ns"] = time.perf_counter_ns()

    workers = [worker_result(record) for record in records]
    success_count = sum(1 for worker in workers if worker["success"])
    launch_times = [record["launched_ns"] for record in records]
    phase = {
        "name": phase_name,
        "concurrency": concurrency,
        "repetition": repetition,
        "timed_out": timed_out,
        "expected_workers": concurrency,
        "successful_workers": success_count,
        "failed_workers": concurrency - success_count,
        "wall_seconds": (phase_end_ns - phase_start_ns) / 1_000_000_000.0,
        "worker_start_spread_seconds": (
            (max(launch_times) - min(launch_times)) / 1_000_000_000.0
            if len(launch_times) > 1
            else 0.0
        ),
        "workers": workers,
        "metric_summary": aggregate_worker_metrics(workers),
        "nvidia_gpu": monitor.summary(),
    }
    print_phase_summary(phase)
    return phase


def build_concurrency_summary(phases: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    grouped: dict[int, list[Mapping[str, Any]]] = {}
    for phase in phases:
        concurrency = int(phase["concurrency"])
        grouped.setdefault(concurrency, []).append(phase)

    result: dict[str, Any] = {}
    for concurrency, group in sorted(grouped.items()):
        workers = [
            worker
            for phase in group
            for worker in phase.get("workers", [])
            if isinstance(worker, Mapping)
        ]
        success_count = sum(1 for worker in workers if worker.get("success") is True)
        gpu_maxima: list[float] = []
        for phase in group:
            gpu = phase.get("nvidia_gpu")
            if not isinstance(gpu, Mapping):
                continue
            gpu_summary = gpu.get("summary")
            if not isinstance(gpu_summary, Mapping):
                continue
            memory = gpu_summary.get("memory_used_mib")
            if isinstance(memory, Mapping):
                value = finite_number(memory.get("max"))
                if value is not None:
                    gpu_maxima.append(value)
        result[str(concurrency)] = {
            "repetitions": len(group),
            "expected_worker_runs": len(workers),
            "successful_worker_runs": success_count,
            "failed_worker_runs": len(workers) - success_count,
            "metric_summary": aggregate_worker_metrics(workers),
            "phase_gpu_memory_max_mib": summarize_numbers(gpu_maxima),
        }
    return result


def print_phase_summary(phase: Mapping[str, Any]) -> None:
    print(
        f"Ergebnis: {phase['successful_workers']}/{phase['expected_workers']} Worker erfolgreich; "
        f"Wandzeit {phase['wall_seconds']:.3f} s",
        flush=True,
    )
    summaries = phase.get("metric_summary")
    labels = (
        ("post_audio_end_to_first_pcm_seconds", "Audioende → erster PCM-Block"),
        ("asr_tail_latency_seconds", "ASR-Nachlauf"),
        ("llm_time_to_first_token_seconds", "LLM TTFT"),
        ("tts_time_to_first_audio_seconds", "TTS TTFA"),
        ("tts_realtime_factor", "TTS RTF"),
    )
    if isinstance(summaries, Mapping):
        for key, label in labels:
            summary = summaries.get(key)
            if isinstance(summary, Mapping):
                print(
                    f"  {label}: Median {summary['median']:.3f}, "
                    f"P95 {summary['p95']:.3f}, Max {summary['max']:.3f}",
                    flush=True,
                )
    gpu = phase.get("nvidia_gpu")
    if isinstance(gpu, Mapping) and gpu.get("available") is True:
        gpu_summary = gpu.get("summary")
        if isinstance(gpu_summary, Mapping):
            memory = gpu_summary.get("memory_used_mib")
            power = gpu_summary.get("power_draw_watts")
            utilization = gpu_summary.get("utilization_gpu_percent")
            parts = []
            if isinstance(memory, Mapping):
                parts.append(f"VRAM max {memory['max']:.0f} MiB")
            if isinstance(utilization, Mapping):
                parts.append(f"GPU max {utilization['max']:.0f} %")
            if isinstance(power, Mapping):
                parts.append(f"Power max {power['max']:.1f} W")
            if parts:
                print("  NVIDIA: " + ", ".join(parts), flush=True)


def write_json_atomic(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=path.parent,
            delete=False,
        ) as handle:
            temporary = Path(handle.name)
            json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except OSError as exc:
        if temporary is not None:
            try:
                temporary.unlink()
            except OSError:
                pass
        raise ParallelTestError(f"Sammelbericht konnte nicht geschrieben werden: {exc}") from exc


def configuration_for_report(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "input": str(args.input),
        "pipeline_script": str(args.pipeline_script),
        "python": args.python,
        "concurrency": args.concurrency,
        "repetitions": args.repetitions,
        "tts": args.tts,
        "asr_url": args.asr_url,
        "llm_url": args.llm_url,
        "tts_url": args.tts_url,
        "asr_chunk_ms": args.asr_chunk_ms,
        "realtime_input": args.realtime_input,
        "input_rate": args.input_rate,
        "input_channels": args.input_channels,
        "qwen_speaker": args.qwen_speaker if args.tts == "qwen" else None,
        "qwen_language": args.qwen_language if args.tts == "qwen" else None,
        "qwen_seed": args.qwen_seed if args.tts == "qwen" else None,
        "max_tokens": args.max_tokens,
        "temperature": args.temperature,
        "phase_timeout_seconds": args.phase_timeout,
        "cooldown_seconds": args.cooldown_seconds,
        "gpu_index": args.gpu_index,
        "gpu_sample_ms": args.gpu_sample_ms,
        "playback": False,
    }


def run(args: argparse.Namespace) -> int:
    pipeline_version = validate_inputs(args)
    print(f"Paralleltest v{PROGRAM_VERSION}")
    print(f"Einzeltest: {pipeline_version}")
    print(f"Parallelitätsstufen: {' '.join(str(value) for value in args.concurrency)}")
    print(f"Wiederholungen: {args.repetitions}; TTS: {args.tts}; Echtzeiteingabe: {args.realtime_input}")
    print("Player: deaktiviert; Worker-stdout/stderr wird unterdrückt und nicht gespeichert.")

    if args.dry_run:
        example_output = Path("<run-dir>") / "concurrency-01-run-01" / "worker-01.pcm"
        example_report = Path("<run-dir>") / "concurrency-01-run-01" / "worker-01-benchmark.json"
        command = build_worker_command(
            args,
            output_path=example_output,
            report_path=example_report,
        )
        print("Dry-Run erfolgreich. Beispielkommando:")
        print(" ".join(json.dumps(part) for part in command))
        return 0

    run_dir = create_run_directory(args.output_dir)
    aggregate_path = run_dir / "parallel-benchmark.json"
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    report: dict[str, Any] = {
        "schema_version": 1,
        "program": f"kienzlefon-ai-parallel-test-v{PROGRAM_VERSION}.py",
        "program_version": PROGRAM_VERSION,
        "status": "running",
        "started_at_utc": started_at,
        "finished_at_utc": None,
        "platform": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "python": platform.python_version(),
        },
        "pipeline_version": pipeline_version,
        "configuration": configuration_for_report(args),
        "run_directory": str(run_dir),
        "aggregate_report": str(aggregate_path),
        "privacy": {
            "worker_stdout_stderr_captured": False,
            "worker_stdout_stderr_inherited": False,
            "worker_stdout_stderr_suppressed": True,
            "transcripts_in_aggregate_report": False,
            "llm_text_in_aggregate_report": False,
        },
        "phases": [],
        "concurrency_summary": {},
    }
    write_json_atomic(aggregate_path, report)

    interrupted = False
    try:
        phase_number = 0
        total_phases = len(args.concurrency) * args.repetitions
        for concurrency in args.concurrency:
            for repetition in range(1, args.repetitions + 1):
                phase_number += 1
                phase = run_phase(
                    args,
                    run_dir=run_dir,
                    concurrency=concurrency,
                    repetition=repetition,
                )
                report["phases"].append(phase)
                report["concurrency_summary"] = build_concurrency_summary(report["phases"])
                write_json_atomic(aggregate_path, report)
                if phase_number < total_phases and args.cooldown_seconds > 0:
                    print(f"Cooldown: {args.cooldown_seconds:.1f} s", flush=True)
                    time.sleep(args.cooldown_seconds)
    except KeyboardInterrupt:
        interrupted = True
        print("\nParalleltest durch Benutzer abgebrochen.", file=sys.stderr, flush=True)

    all_successful = all(
        phase.get("failed_workers") == 0 and phase.get("timed_out") is False
        for phase in report["phases"]
    ) and len(report["phases"]) == len(args.concurrency) * args.repetitions
    report["status"] = "interrupted" if interrupted else "ok" if all_successful else "error"
    report["finished_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    report["concurrency_summary"] = build_concurrency_summary(report["phases"])
    write_json_atomic(aggregate_path, report)
    print(f"\nSammelbericht: {aggregate_path}", flush=True)
    if interrupted:
        return 130
    return 0 if all_successful else 1


def main(argv: list[str] | None = None) -> NoReturn:
    try:
        args = parse_args(argv)
        exit_code = run(args)
    except ParallelTestError as exc:
        print(f"[FEHLER] {exc}", file=sys.stderr)
        exit_code = 2
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
