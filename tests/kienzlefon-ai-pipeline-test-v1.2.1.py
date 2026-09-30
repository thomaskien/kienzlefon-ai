#!/usr/bin/env python3
"""Kienzlefon AI pipeline test suite.

Tests one complete raw-PCM utterance through the resident Kienzlefon AI services:
    Kienzlefon ASR v1 (WhisperLiveKit gateway, WebSocket stream)
      -> llama-server (OpenAI-compatible SSE stream)
      -> Qwen3-TTS / Piper / optional macOS say
      -> raw PCM file and optional live playback

The input is a file, but it is sent as a real PCM WebSocket stream. No microphone
is required. The core pipeline is platform-neutral and intended for both Linux
and macOS. The ``say`` backend is an optional macOS-only comparison backend.

The program starts or installs no models or services. It intentionally stores
neither transcript nor LLM answer in JSON files or normal program logs.
"""

from __future__ import annotations

import argparse
import array
import base64
import contextlib
import datetime as dt
import http.client
import hashlib
import json
import math
import os
import platform
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
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, BinaryIO, Iterable, Mapping, NoReturn
from urllib.parse import urlsplit, urlunsplit


PROGRAM_VERSION = "1.2.1"
ASR_SAMPLE_RATE = 16_000
ASR_CHANNELS = 1
PCM_SAMPLE_WIDTH_BYTES = 2
ASR_BYTES_PER_SECOND = ASR_SAMPLE_RATE * ASR_CHANNELS * PCM_SAMPLE_WIDTH_BYTES
DEFAULT_ASR_CHUNK_MS = 500
ASR_PROTOCOL = "kienzlefon-asr-v1"
DEFAULT_ASR_URL = "ws://127.0.0.1:8178/v1/asr/stream"

PIPER_SAMPLE_RATE = 22_050
PIPER_CHANNELS = 1
PIPER_VOICE = "de_DE-thorsten-high"
DEFAULT_PIPER_URL = "http://127.0.0.1:8181/v1/audio/speech"

QWEN_SAMPLE_RATE = 24_000
QWEN_CHANNELS = 1
QWEN_FORMAT = "s16le"
QWEN_SPEAKER = "ryan"
QWEN_LANGUAGE = "German"
QWEN_SEED = 42
DEFAULT_QWEN_URL = "http://127.0.0.1:8182/v1/tts/stream"

SAY_SAMPLE_RATE = 16_000
SAY_CHANNELS = 1

DEFAULT_LLM_URL = "http://127.0.0.1:8080/v1/chat/completions"
HTTP_TIMEOUT_SECONDS = 300.0
FALLBACK_CHUNK_WORDS = 15
READ_BLOCK_BYTES = 4 * 1024

DEFAULT_SYSTEM_PROMPT = (
    "Du bist die deutschsprachige Telefonassistenz einer Arztpraxis. "
    "Antworte kurz, freundlich und in gut sprechbaren vollständigen Sätzen. "
    "Erfinde keine Patientendaten, Diagnosen, Verordnungen oder Zusagen. "
    "Bestätige das verstandene Anliegen knapp und stelle höchstens eine "
    "notwendige Rückfrage. Verwende kein Markdown."
)


class PipelineError(RuntimeError):
    """Expected pipeline failure with service and category information."""

    def __init__(
        self,
        service: str,
        message: str,
        *,
        category: str = "error",
        exit_code: int = 1,
    ) -> None:
        super().__init__(message)
        self.service = service
        self.category = category
        self.exit_code = exit_code


class Console:
    """Thread-safe console writer that keeps streaming LLM output readable."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._llm_line_open = False

    def log(self, message: str) -> None:
        with self._lock:
            if self._llm_line_open:
                sys.stdout.write("\n")
                self._llm_line_open = False
            sys.stdout.write(message + "\n")
            sys.stdout.flush()

    def llm(self, text: str) -> None:
        if not text:
            return
        with self._lock:
            if not self._llm_line_open:
                sys.stdout.write("[LLM] ")
                self._llm_line_open = True
            sys.stdout.write(text)
            sys.stdout.flush()

    def llm_end(self) -> None:
        with self._lock:
            if self._llm_line_open:
                sys.stdout.write("\n")
                sys.stdout.flush()
                self._llm_line_open = False

    def error(self, message: str) -> None:
        with self._lock:
            if self._llm_line_open:
                sys.stdout.write("\n")
                self._llm_line_open = False
            sys.stderr.write(message + "\n")
            sys.stderr.flush()


@dataclass
class BenchmarkClock:
    console: Console
    t0_ns: int | None = None
    events_ns: dict[str, int] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def start(self) -> None:
        now = time.perf_counter_ns()
        with self._lock:
            self.t0_ns = now
            self.events_ns["T0"] = now

    def mark(self, event: str, message: str | None = None) -> int:
        now = time.perf_counter_ns()
        with self._lock:
            if self.t0_ns is None:
                raise RuntimeError("Benchmark clock has not been started")
            is_new = event not in self.events_ns
            if is_new:
                self.events_ns[event] = now
            stored = self.events_ns[event]
        if message is not None and is_new:
            self.console.log(f"[+{self.seconds_from_t0(stored):.3f} s] {message}")
        return stored

    def elapsed_log(self, message: str) -> None:
        now = time.perf_counter_ns()
        self.console.log(f"[+{self.seconds_from_t0(now):.3f} s] {message}")

    def get(self, event: str) -> int | None:
        with self._lock:
            return self.events_ns.get(event)

    def seconds_from_t0(self, timestamp_ns: int) -> float:
        if self.t0_ns is None:
            return 0.0
        return (timestamp_ns - self.t0_ns) / 1_000_000_000.0

    def event_seconds(self) -> dict[str, float | None]:
        with self._lock:
            base = self.t0_ns
            snapshot = dict(self.events_ns)
        return {
            f"T{i}": (
                None
                if base is None or f"T{i}" not in snapshot
                else round((snapshot[f"T{i}"] - base) / 1_000_000_000.0, 9)
            )
            for i in range(12)
        }


@dataclass
class InputAudio:
    source_path: Path
    raw_bytes: bytes
    input_rate: int
    input_channels: int
    input_frames: int
    duration_seconds: float
    asr_pcm_bytes: bytes
    asr_frames: int
    asr_duration_seconds: float


@dataclass
class ASRStats:
    chunks_sent: int = 0
    bytes_sent: int = 0
    partial_count: int = 0
    confirmed_count: int = 0
    confirmed_segment_count: int = 0
    confirmed_revision_count: int = 0
    last_partial: str | None = None


@dataclass
class ConfirmedSegment:
    start: float | None
    end: float | None
    text: str
    sequence: int


class ConfirmedTranscriptAssembler:
    """Assemble revision-style ASR confirmed events into one final transcript.

    WhisperLiveKit full-mode snapshots may repeatedly revise the same timestamped
    line while decoding progresses (for example ``Europa und`` -> ``Europa und
    Asien``).  The Kienzlefon gateway forwards those revisions as ``confirmed``
    events with ``start``/``end`` metadata.  Treating every event as a new segment
    duplicates the transcript, so revisions replace the matching segment here.
    """

    START_TOLERANCE_SECONDS = 0.08

    def __init__(self) -> None:
        self._segments: list[ConfirmedSegment] = []
        self._sequence = 0
        self.revision_count = 0

    @staticmethod
    def _time_value(value: Any) -> float | None:
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            result = float(value)
            return result if math.isfinite(result) else None
        return None

    @staticmethod
    def _is_text_revision(old: str, new: str) -> bool:
        old = old.strip()
        new = new.strip()
        return bool(old and new and (old.startswith(new) or new.startswith(old)))

    @staticmethod
    def _intervals_overlap(a: ConfirmedSegment, start: float | None, end: float | None) -> bool:
        if a.start is None or a.end is None or start is None or end is None:
            return False
        return min(a.end, end) >= max(a.start, start) - ConfirmedTranscriptAssembler.START_TOLERANCE_SECONDS

    def add(self, *, text: str, start: Any, end: Any) -> str:
        text = text.strip()
        start_f = self._time_value(start)
        end_f = self._time_value(end)
        self._sequence += 1

        match_index: int | None = None
        if start_f is not None:
            for index, segment in enumerate(self._segments):
                if segment.start is not None and abs(segment.start - start_f) <= self.START_TOLERANCE_SECONDS:
                    match_index = index
                    break

        if match_index is None:
            for index, segment in enumerate(self._segments):
                if self._is_text_revision(segment.text, text) and self._intervals_overlap(segment, start_f, end_f):
                    match_index = index
                    break

        # Gateways/backends that omit timestamps can still expose growing-prefix
        # revisions. Restrict this fallback to the latest segment to avoid merging
        # distinct, coincidentally similar sentences.
        if match_index is None and start_f is None and self._segments:
            last = self._segments[-1]
            if last.start is None and self._is_text_revision(last.text, text):
                match_index = len(self._segments) - 1

        replacement = ConfirmedSegment(start=start_f, end=end_f, text=text, sequence=self._sequence)
        if match_index is None:
            self._segments.append(replacement)
            action = "new"
        else:
            previous = self._segments[match_index]
            # Keep the newest non-empty revision even when it becomes shorter; ASR
            # decoders may retract a mistaken suffix before extending it again.
            if start_f is None:
                replacement.start = previous.start
            if end_f is None:
                replacement.end = previous.end
            replacement.sequence = previous.sequence
            self._segments[match_index] = replacement
            self.revision_count += 1
            action = "revision"

        return action

    @property
    def segment_count(self) -> int:
        return len(self._segments)

    def transcript(self) -> str:
        def sort_key(segment: ConfirmedSegment) -> tuple[int, float, int]:
            if segment.start is None:
                return (1, 0.0, segment.sequence)
            return (0, segment.start, segment.sequence)

        ordered = sorted(self._segments, key=sort_key)
        return " ".join(segment.text for segment in ordered if segment.text).strip()


@dataclass
class LLMStats:
    completion_tokens: int | None = None
    predicted_tokens: int | None = None
    server_tokens_per_second: float | None = None
    finish_reason: str | None = None
    output_characters: int = 0


@dataclass
class TTSStats:
    backend: str = "qwen"
    section_count: int = 0
    output_bytes: int = 0
    output_opened: bool = False
    output_complete: bool = False
    request_durations_seconds: list[float] = field(default_factory=list)
    response_sample_rate: int = QWEN_SAMPLE_RATE
    response_channels: int = QWEN_CHANNELS


@dataclass
class PlayerStats:
    enabled: bool = False
    command: str | None = None
    process_started_ns: int | None = None
    first_block_queued_ns: int | None = None
    first_block_written_ns: int | None = None
    process_finished_ns: int | None = None
    bytes_queued: int = 0
    bytes_written: int = 0
    exit_code: int | None = None
    stderr: str | None = None


@dataclass
class SharedWorkerError:
    error: PipelineError | None = None
    lock: threading.Lock = field(default_factory=threading.Lock)

    def set(self, error: PipelineError) -> None:
        with self.lock:
            if self.error is None:
                self.error = error

    def get(self) -> PipelineError | None:
        with self.lock:
            return self.error


class SpeakableChunker:
    """Build ordered TTS sections from incremental LLM text."""

    _TERMINATORS = frozenset(".?!:;")
    _TRAILING_CLOSERS = frozenset('"\'»”’)]}')
    _WORD_RE = re.compile(r"\S+")

    def __init__(self, fallback_words: int = FALLBACK_CHUNK_WORDS) -> None:
        if fallback_words < 1:
            raise ValueError("fallback_words must be positive")
        self._fallback_words = fallback_words
        self._buffer = ""

    def feed(self, text: str) -> list[str]:
        if text:
            self._buffer += text
        chunks: list[str] = []

        while True:
            punctuation_end = self._find_punctuation_end(self._buffer)
            if punctuation_end is not None:
                candidate = self._buffer[:punctuation_end]
                self._buffer = self._buffer[punctuation_end:]
                cleaned = clean_for_tts(candidate)
                if cleaned:
                    chunks.append(cleaned)
                continue

            fallback_end = self._find_fallback_end(self._buffer)
            if fallback_end is not None:
                candidate = self._buffer[:fallback_end]
                self._buffer = self._buffer[fallback_end:]
                cleaned = clean_for_tts(candidate)
                if cleaned:
                    chunks.append(cleaned)
                continue
            break

        return chunks

    def flush(self) -> list[str]:
        cleaned = clean_for_tts(self._buffer)
        self._buffer = ""
        return [cleaned] if cleaned else []

    @classmethod
    def _find_punctuation_end(cls, text: str) -> int | None:
        for index, char in enumerate(text):
            if char not in cls._TERMINATORS:
                continue
            end = index + 1
            while end < len(text) and text[end] in cls._TRAILING_CLOSERS:
                end += 1
            return end
        return None

    def _find_fallback_end(self, text: str) -> int | None:
        matches = list(self._WORD_RE.finditer(text))
        if len(matches) < self._fallback_words:
            return None
        end = matches[self._fallback_words - 1].end()
        # If the last visible word may still be growing, emit the preceding
        # complete words instead of waiting past the 12-to-15-word window.
        if end == len(text) and text and not text[-1].isspace():
            previous_index = self._fallback_words - 2
            if previous_index >= 0:
                return matches[previous_index].end()
            return None
        return end


class PlaybackController:
    """Asynchronously forwards exact PCM blocks to an ffplay process."""

    def __init__(
        self,
        *,
        command: str,
        sample_rate: int,
        channels: int,
        clock: BenchmarkClock,
        stats: PlayerStats,
    ) -> None:
        self.command = command
        self.sample_rate = sample_rate
        self.channels = channels
        self.clock = clock
        self.stats = stats
        self._queue: queue.Queue[bytes | None] = queue.Queue()
        self._process: subprocess.Popen[bytes] | None = None
        self._thread: threading.Thread | None = None
        self._stderr_file: BinaryIO | None = None
        self._error: PipelineError | None = None
        self._error_lock = threading.Lock()

    def start(self) -> None:
        executable = resolve_executable(self.command, service="Player")
        self.stats.enabled = True
        self.stats.command = executable
        self._stderr_file = tempfile.TemporaryFile(mode="w+b")
        argv = [
            executable,
            "-nodisp",
            "-autoexit",
            "-loglevel",
            "warning",
            "-fflags",
            "nobuffer",
            "-f",
            "s16le",
            "-ar",
            str(self.sample_rate),
            "-ac",
            str(self.channels),
            "-i",
            "pipe:0",
        ]
        try:
            self._process = subprocess.Popen(
                argv,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=self._stderr_file,
                bufsize=0,
            )
        except OSError as exc:
            self._close_stderr_file()
            raise PipelineError("Player", f"ffplay konnte nicht gestartet werden: {exc}", exit_code=6) from exc
        self.stats.process_started_ns = time.perf_counter_ns()
        self._thread = threading.Thread(
            target=self._writer,
            name="kienzlefon-player-writer",
            daemon=True,
        )
        self._thread.start()

    def enqueue(self, block: bytes) -> None:
        failure = self.error()
        if failure is not None:
            raise failure
        now = time.perf_counter_ns()
        if self.stats.first_block_queued_ns is None:
            self.stats.first_block_queued_ns = now
        self.stats.bytes_queued += len(block)
        self._queue.put(bytes(block))

    def finish(self) -> None:
        if self._thread is None:
            return
        self._queue.put(None)
        self._thread.join()
        self._thread = None
        self._capture_process_result()
        if self.error() is None and self.stats.bytes_written != self.stats.bytes_queued:
            self._set_error(
                PipelineError(
                    "Player",
                    "Nicht alle PCM-Daten wurden an ffplay übergeben: "
                    f"{self.stats.bytes_written} von {self.stats.bytes_queued} Byte",
                    exit_code=6,
                )
            )
        failure = self.error()
        if failure is not None:
            raise failure

    def abort(self) -> None:
        process = self._process
        if process is not None and process.poll() is None:
            with contextlib.suppress(OSError):
                process.terminate()
        if self._thread is not None:
            self._queue.put(None)
            self._thread.join(timeout=2.0)
            self._thread = None
        if process is not None and process.poll() is None:
            with contextlib.suppress(OSError):
                process.kill()
        self._capture_process_result()

    def error(self) -> PipelineError | None:
        with self._error_lock:
            return self._error

    def _set_error(self, error: PipelineError) -> None:
        with self._error_lock:
            if self._error is None:
                self._error = error

    def _writer(self) -> None:
        process = self._process
        if process is None or process.stdin is None:
            self._set_error(PipelineError("Player", "Player-stdin ist nicht verfügbar", exit_code=6))
            return
        try:
            while True:
                block = self._queue.get()
                try:
                    if block is None:
                        break
                    view = memoryview(block)
                    while view:
                        written = process.stdin.write(view)
                        if written is None or written <= 0:
                            raise BrokenPipeError("ffplay nahm keine weiteren PCM-Daten an")
                        view = view[written:]
                    self.stats.bytes_written += len(block)
                    if self.stats.first_block_written_ns is None:
                        self.stats.first_block_written_ns = time.perf_counter_ns()
                        self.clock.elapsed_log("Erster PCM-Block an Player übergeben")
                finally:
                    self._queue.task_done()
        except (BrokenPipeError, OSError) as exc:
            self._set_error(PipelineError("Player", f"Wiedergabestream abgebrochen: {exc}", exit_code=6))
        finally:
            with contextlib.suppress(OSError):
                process.stdin.close()

    def _capture_process_result(self) -> None:
        process = self._process
        if process is None or self.stats.process_finished_ns is not None:
            self._close_stderr_file()
            return
        try:
            return_code = process.wait(timeout=HTTP_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(OSError):
                process.terminate()
            try:
                return_code = process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                with contextlib.suppress(OSError):
                    process.kill()
                return_code = process.wait()
            self._set_error(
                PipelineError(
                    "Player",
                    "ffplay beendete sich nicht ordnungsgemäß",
                    category="timeout",
                    exit_code=6,
                )
            )
        self.stats.exit_code = return_code
        self.stats.process_finished_ns = time.perf_counter_ns()
        self.stats.stderr = self._read_stderr_file()
        if return_code != 0 and self.error() is None:
            detail = self.stats.stderr or "keine Fehlerausgabe"
            self._set_error(PipelineError("Player", f"ffplay endete mit Status {return_code}: {detail}", exit_code=6))

    def _read_stderr_file(self) -> str | None:
        stderr_file = self._stderr_file
        if stderr_file is None:
            return None
        try:
            stderr_file.flush()
            stderr_file.seek(0)
            data = stderr_file.read(4096)
            return data.decode("utf-8", errors="replace").strip() or None
        except OSError:
            return None
        finally:
            self._close_stderr_file()

    def _close_stderr_file(self) -> None:
        if self._stderr_file is not None:
            with contextlib.suppress(OSError):
                self._stderr_file.close()
            self._stderr_file = None


def resolve_executable(command: str, *, service: str) -> str:
    """Resolve a command name or explicit path and return an executable path."""
    candidate = Path(command).expanduser()
    if candidate.parent != Path(".") or os.sep in command:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
        raise PipelineError(service, f"Programm nicht ausführbar oder nicht gefunden: {command}", exit_code=6)
    resolved = shutil.which(command)
    if resolved is None:
        raise PipelineError(service, f"Programm nicht im PATH gefunden: {command}", exit_code=6)
    return resolved


def clean_for_tts(text: str) -> str:
    """Remove common non-speakable formatting without changing wording."""
    text = text.replace("```", " ").replace("`", "")
    text = re.sub(r"(?m)^\s{0,3}(?:#{1,6}|[-*+]\s+|\d+[.)]\s+)", "", text)
    text = text.replace("**", "").replace("__", "").replace("*", "")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


PCM_HELP = r"""
RAW-PCM-TESTDATEIEN

Erwartetes Eingabeformat (Standard):
  signed PCM 16 Bit little-endian, 16.000 Hz, mono, ohne WAV-Kopf

Die Datei wird intern als echter Audio-Stream an Kienzlefon-ASR gesendet.
Ein Mikrofon ist für den Pipeline-Test nicht erforderlich.

1. Vorhandene Aufnahme konvertieren (macOS und Linux; WAV/M4A/MP3/AAC usw.):

  ffmpeg -y -i aufnahme.m4a -vn -ac 1 -ar 16000 \
    -c:a pcm_s16le -f s16le test.pcm

2. macOS: direkt vom Mikrofon aufnehmen (nur falls gewünscht):

  ffmpeg -f avfoundation -list_devices true -i ""

  ffmpeg -y -f avfoundation -i ":0" -ac 1 -ar 16000 \
    -c:a pcm_s16le -f s16le test.pcm

3. Linux: direkt vom Mikrofon aufnehmen (nur falls gewünscht):

  ALSA:
    ffmpeg -y -f alsa -i default -ac 1 -ar 16000 \
      -c:a pcm_s16le -f s16le test.pcm

  PulseAudio/PipeWire-Pulse:
    ffmpeg -y -f pulse -i default -ac 1 -ar 16000 \
      -c:a pcm_s16le -f s16le test.pcm

4. macOS: reproduzierbare synthetische Testäußerung:

  say -v Anna -o /tmp/kienzlefon-test.aiff \
    "Ich benötige ein Rezept für Ramipril."

  ffmpeg -y -i /tmp/kienzlefon-test.aiff -ac 1 -ar 16000 \
    -c:a pcm_s16le -f s16le test.pcm

5. Raw-PCM probeweise anhören (macOS und Linux):

  ffplay -nodisp -autoexit -f s16le -ar 16000 -ac 1 test.pcm

6. Dateidauer portabel kontrollieren (16 kHz/mono/PCM16 = 32.000 Byte/s):

  python3 -c 'import os; print("%%.3f Sekunden" %% (os.path.getsize("test.pcm") / 32000))'

STREAMING-ASR

Standardmäßig wird die Datei blockweise ohne künstliche Wartezeit gesendet.
Für eine realistische Telefon-Simulation mit natürlicher Audiodauer:

  --realtime-input

Die Blockgröße wird mit --asr-chunk-ms festgelegt (Standard: 500 ms).
Die stabile Schnittstelle ist kienzlefon-asr-v1 auf /v1/asr/stream.

BEISPIELE

Qwen3-TTS 0.6B (Standard), Datei speichern und gleichzeitig wiedergeben:

  %(prog)s --input test.pcm --tts qwen --play \
    --output antwort-qwen.pcm --report benchmark-qwen.json

Piper-Fallback testen:

  %(prog)s --input test.pcm --tts piper --play \
    --output antwort-piper.pcm --report benchmark-piper.json

Realistische ASR-Zuführung in Echtzeit:

  %(prog)s --input test.pcm --realtime-input --tts qwen --play \
    --output antwort-realtime.pcm --report benchmark-realtime.json

macOS say als optionaler Vergleichstest:

  %(prog)s --input test.pcm --tts say --say-voice Anna --say-rate 170 --play \
    --output antwort-say.pcm --report benchmark-say.json

HINWEISE

  Kernfunktionen laufen unter Linux und macOS. --tts say ist ausschließlich
  unter macOS verfügbar und benötigt zusätzlich FFmpeg. --play benötigt ffplay.
  Wiedergabe und Datei enthalten exakt dieselben PCM-Blöcke in derselben Reihenfolge.
  Qwen3-TTS streamt nativ mit 24 kHz; Piper de_DE-thorsten-high mit
  22,05 kHz; say wird für den Vergleich auf 16 kHz konvertiert.
"""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Testet eine Raw-PCM-Datei als Streaming-Audio durch "
            "Kienzlefon-ASR -> LLM-Stream -> TTS -> Raw-PCM."
        ),
        epilog=PCM_HELP,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {PROGRAM_VERSION}")
    parser.add_argument("--input", required=True, type=Path, help="Raw-PCM-Eingabe")
    parser.add_argument(
        "--asr-url",
        default=DEFAULT_ASR_URL,
        help=f"Kienzlefon-ASR-v1-WebSocket (Standard: {DEFAULT_ASR_URL})",
    )
    parser.add_argument(
        "--asr-chunk-ms",
        type=int,
        default=DEFAULT_ASR_CHUNK_MS,
        help=f"PCM-Blockdauer für ASR in ms (Standard: {DEFAULT_ASR_CHUNK_MS})",
    )
    parser.add_argument(
        "--realtime-input",
        action="store_true",
        help="Datei mit natürlicher Audiodauer statt maximal schnell an ASR senden",
    )
    parser.add_argument(
        "--llm-url",
        default=DEFAULT_LLM_URL,
        help=f"llama-server-Endpunkt (Standard: {DEFAULT_LLM_URL})",
    )
    parser.add_argument(
        "--tts",
        choices=("qwen", "piper", "say"),
        default="qwen",
        help="TTS-Backend (Standard: qwen; say nur macOS)",
    )
    parser.add_argument(
        "--tts-url",
        help=(
            "TTS-Endpunkt überschreiben; Standard: Qwen "
            f"{DEFAULT_QWEN_URL}, Piper {DEFAULT_PIPER_URL}"
        ),
    )
    parser.add_argument("--qwen-speaker", default=QWEN_SPEAKER, help=f"Qwen-Sprecher (Standard: {QWEN_SPEAKER})")
    parser.add_argument("--qwen-language", default=QWEN_LANGUAGE, help=f"Qwen-Sprache (Standard: {QWEN_LANGUAGE})")
    parser.add_argument("--qwen-seed", type=int, default=QWEN_SEED, help=f"Qwen-Seed (Standard: {QWEN_SEED})")
    parser.add_argument("--say-voice", help="macOS-say-Stimme; ohne Angabe Systemstimme")
    parser.add_argument("--say-rate", type=int, help="Sprechtempo für macOS say in Wörtern pro Minute")
    parser.add_argument("--play", action="store_true", help="PCM zusätzlich sofort über ffplay wiedergeben")
    parser.add_argument("--player", default="ffplay", help="Pfad oder Name von ffplay (Standard: ffplay)")
    parser.add_argument("--output", required=True, type=Path, help="Raw-PCM-Ausgabe")
    parser.add_argument("--report", required=True, type=Path, help="Benchmarkbericht JSON")
    parser.add_argument("--input-rate", type=int, default=16_000)
    parser.add_argument("--input-channels", type=int, default=1)
    parser.add_argument("--system-prompt", default=DEFAULT_SYSTEM_PROMPT)
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--temperature", type=float, default=0.2)
    args = parser.parse_args(argv)

    if args.input_rate <= 0:
        parser.error("--input-rate muss größer als 0 sein")
    if not 1 <= args.input_channels <= 32:
        parser.error("--input-channels muss zwischen 1 und 32 liegen")
    if not 20 <= args.asr_chunk_ms <= 2000:
        parser.error("--asr-chunk-ms muss zwischen 20 und 2000 ms liegen")
    if args.max_tokens <= 0:
        parser.error("--max-tokens muss größer als 0 sein")
    if not math.isfinite(args.temperature) or args.temperature < 0:
        parser.error("--temperature muss eine endliche Zahl >= 0 sein")
    if args.say_rate is not None and args.say_rate <= 0:
        parser.error("--say-rate muss größer als 0 sein")
    if args.qwen_seed < 0:
        parser.error("--qwen-seed muss >= 0 sein")
    for name in ("qwen_speaker", "qwen_language"):
        value = getattr(args, name).strip()
        if not value:
            parser.error(f"--{name.replace('_', '-')} darf nicht leer sein")
        setattr(args, name, value)
    if args.say_voice is not None:
        args.say_voice = args.say_voice.strip()
        if not args.say_voice:
            parser.error("--say-voice darf nicht leer sein")
    if args.tts != "say" and (args.say_voice is not None or args.say_rate is not None):
        parser.error("--say-voice und --say-rate dürfen nur mit --tts say verwendet werden")
    if args.tts == "say" and sys.platform != "darwin":
        parser.error("--tts say ist ausschließlich unter macOS verfügbar")
    if not args.player.strip():
        parser.error("--player darf nicht leer sein")

    try:
        args.asr_url = normalize_ws_endpoint(args.asr_url, "/v1/asr/stream")
        args.llm_url = normalize_http_endpoint(args.llm_url, "/v1/chat/completions")
        if args.tts == "qwen":
            args.tts_url = normalize_http_endpoint(args.tts_url or DEFAULT_QWEN_URL, "/v1/tts/stream")
        elif args.tts == "piper":
            args.tts_url = normalize_http_endpoint(args.tts_url or DEFAULT_PIPER_URL, "/v1/audio/speech")
        else:
            if args.tts_url is not None:
                parser.error("--tts-url ist mit --tts say nicht zulässig")
            args.tts_url = None
    except argparse.ArgumentTypeError as exc:
        parser.error(str(exc))
    return args


def normalize_http_endpoint(url: str, default_path: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise argparse.ArgumentTypeError(f"Ungültige HTTP-URL: {url}")
    path = parsed.path or ""
    if path in {"", "/"}:
        path = default_path
    elif default_path == "/v1/chat/completions" and path.rstrip("/") == "/v1":
        path = default_path
    return urlunsplit((parsed.scheme, parsed.netloc, path, parsed.query, ""))


def normalize_ws_endpoint(url: str, default_path: str) -> str:
    parsed = urlsplit(url)
    if parsed.scheme not in {"ws", "wss"} or not parsed.netloc:
        raise argparse.ArgumentTypeError(f"Ungültige WebSocket-URL: {url}")
    path = parsed.path or ""
    if path in {"", "/"}:
        path = default_path
    return urlunsplit((parsed.scheme, parsed.netloc, path, parsed.query, ""))


def prepare_input_audio(args: argparse.Namespace, clock: BenchmarkClock) -> InputAudio:
    try:
        raw = args.input.read_bytes()
    except OSError as exc:
        raise PipelineError("Eingabe", f"PCM-Datei kann nicht gelesen werden: {exc}", exit_code=2) from exc

    frame_size = PCM_SAMPLE_WIDTH_BYTES * args.input_channels
    if not raw:
        raise PipelineError("Eingabe", "PCM-Datei ist leer", exit_code=2)
    if len(raw) % frame_size != 0:
        raise PipelineError(
            "Eingabe",
            f"PCM-Dateigröße {len(raw)} ist nicht durch die Framegröße {frame_size} teilbar",
            exit_code=2,
        )

    input_frames = len(raw) // frame_size
    duration = input_frames / args.input_rate
    if duration <= 0:
        raise PipelineError("Eingabe", "PCM-Datei enthält keine vollständigen Frames", exit_code=2)

    clock.start()
    clock.console.log(f"[+0.000 s] PCM übernommen: {format_decimal(duration)} Sekunden")

    asr_pcm = convert_pcm16le_to_mono_16k(raw, args.input_rate, args.input_channels)
    if not asr_pcm or len(asr_pcm) % PCM_SAMPLE_WIDTH_BYTES:
        raise PipelineError("Eingabe", "Normalisierte ASR-PCM-Daten sind ungültig", exit_code=2)
    asr_frames = len(asr_pcm) // PCM_SAMPLE_WIDTH_BYTES
    asr_duration = asr_frames / ASR_SAMPLE_RATE

    return InputAudio(
        source_path=args.input,
        raw_bytes=raw,
        input_rate=args.input_rate,
        input_channels=args.input_channels,
        input_frames=input_frames,
        duration_seconds=duration,
        asr_pcm_bytes=asr_pcm,
        asr_frames=asr_frames,
        asr_duration_seconds=asr_duration,
    )


def convert_pcm16le_to_mono_16k(raw: bytes, sample_rate: int, channels: int) -> bytes:
    """Convert signed PCM16 little-endian to mono PCM16 at 16 kHz."""
    samples = array.array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()

    if channels == 1:
        mono = [int(value) for value in samples]
    else:
        frame_count = len(samples) // channels
        mono = []
        append = mono.append
        for frame_index in range(frame_count):
            base = frame_index * channels
            total = sum(int(samples[base + channel_index]) for channel_index in range(channels))
            append(clamp_int16(round(total / channels)))

    if sample_rate != ASR_SAMPLE_RATE:
        mono = linear_resample_int16(mono, sample_rate, ASR_SAMPLE_RATE)

    output = array.array("h", (clamp_int16(value) for value in mono))
    if sys.byteorder != "little":
        output.byteswap()
    return output.tobytes()


def linear_resample_int16(samples: list[int], source_rate: int, target_rate: int) -> list[int]:
    if not samples:
        return []
    target_length = max(1, round(len(samples) * target_rate / source_rate))
    if target_length == 1 or len(samples) == 1:
        return [samples[0]] * target_length

    scale = source_rate / target_rate
    result: list[int] = []
    append = result.append
    last_index = len(samples) - 1
    for target_index in range(target_length):
        source_position = target_index * scale
        left = min(int(source_position), last_index)
        right = min(left + 1, last_index)
        fraction = source_position - left
        value = round(samples[left] + (samples[right] - samples[left]) * fraction)
        append(clamp_int16(value))
    return result


def clamp_int16(value: int) -> int:
    return max(-32_768, min(32_767, value))


def format_decimal(value: float) -> str:
    return f"{value:.2f}".replace(".", ",")


def open_http_connection(url: str, timeout: float = HTTP_TIMEOUT_SECONDS) -> tuple[http.client.HTTPConnection, str]:
    parsed = urlsplit(url)
    host = parsed.hostname
    if host is None:
        raise PipelineError("HTTP", f"URL ohne Host: {url}")
    port = parsed.port
    if parsed.scheme == "https":
        connection: http.client.HTTPConnection = http.client.HTTPSConnection(host, port, timeout=timeout)
    else:
        connection = http.client.HTTPConnection(host, port, timeout=timeout)
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    return connection, path


class WebSocketClient:
    """Minimal RFC 6455 client for the dependency-free Kienzlefon ASR test."""

    def __init__(self, url: str, timeout: float = HTTP_TIMEOUT_SECONDS) -> None:
        self.url = url
        self.timeout = timeout
        self._sock: socket.socket | ssl.SSLSocket | None = None
        self._recv_buffer = bytearray()
        self._send_lock = threading.Lock()

    def connect(self) -> None:
        parsed = urlsplit(self.url)
        host = parsed.hostname
        if host is None:
            raise PipelineError("ASR", f"WebSocket-URL ohne Host: {self.url}", exit_code=3)
        secure = parsed.scheme == "wss"
        port = parsed.port or (443 if secure else 80)
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        try:
            sock = socket.create_connection((host, port), timeout=self.timeout)
            if secure:
                context = ssl.create_default_context()
                sock = context.wrap_socket(sock, server_hostname=host)
            sock.settimeout(self.timeout)
            self._sock = sock
            key = base64.b64encode(os.urandom(16)).decode("ascii")
            default_port = 443 if secure else 80
            host_header = host if port == default_port else f"{host}:{port}"
            request = (
                f"GET {path} HTTP/1.1\r\n"
                f"Host: {host_header}\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Key: {key}\r\n"
                "Sec-WebSocket-Version: 13\r\n"
                "User-Agent: kienzlefon-ai-pipeline-test\r\n"
                "\r\n"
            ).encode("ascii")
            sock.sendall(request)
            header = self._read_http_header()
            lines = header.decode("iso-8859-1", errors="replace").split("\r\n")
            if not lines or " 101 " not in f" {lines[0]} ":
                raise PipelineError("ASR", f"WebSocket-Upgrade fehlgeschlagen: {lines[0] if lines else '<leer>'}", exit_code=3)
            headers: dict[str, str] = {}
            for line in lines[1:]:
                if ":" in line:
                    name, value = line.split(":", 1)
                    headers[name.strip().lower()] = value.strip()
            expected = base64.b64encode(
                hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
            ).decode("ascii")
            if headers.get("sec-websocket-accept") != expected:
                raise PipelineError("ASR", "Ungültige Sec-WebSocket-Accept-Antwort", exit_code=3)
        except PipelineError:
            self.close()
            raise
        except (socket.timeout, TimeoutError) as exc:
            self.close()
            raise PipelineError("ASR", f"Zeitüberschreitung beim WebSocket-Aufbau zu {self.url}", category="timeout", exit_code=3) from exc
        except (OSError, ssl.SSLError) as exc:
            self.close()
            raise PipelineError("ASR", f"WebSocket-Verbindungsfehler bei {self.url}: {exc}", exit_code=3) from exc

    def _read_http_header(self) -> bytes:
        limit = 64 * 1024
        while b"\r\n\r\n" not in self._recv_buffer:
            if len(self._recv_buffer) > limit:
                raise PipelineError("ASR", "WebSocket-Handshake-Header ist zu groß", exit_code=3)
            self._recv_buffer.extend(self._recv_socket(4096))
        marker = self._recv_buffer.index(b"\r\n\r\n") + 4
        header = bytes(self._recv_buffer[:marker])
        del self._recv_buffer[:marker]
        return header

    def _recv_socket(self, size: int) -> bytes:
        sock = self._sock
        if sock is None:
            raise PipelineError("ASR", "WebSocket ist nicht verbunden", exit_code=3)
        data = sock.recv(size)
        if not data:
            raise PipelineError("ASR", "WebSocket wurde unerwartet geschlossen", exit_code=3)
        return data

    def _recv_exact(self, size: int) -> bytes:
        while len(self._recv_buffer) < size:
            self._recv_buffer.extend(self._recv_socket(max(4096, size - len(self._recv_buffer))))
        data = bytes(self._recv_buffer[:size])
        del self._recv_buffer[:size]
        return data

    def send_binary(self, payload: bytes) -> None:
        self._send_frame(0x2, payload)

    def send_pong(self, payload: bytes) -> None:
        self._send_frame(0xA, payload)

    def _send_frame(self, opcode: int, payload: bytes) -> None:
        sock = self._sock
        if sock is None:
            raise PipelineError("ASR", "WebSocket ist nicht verbunden", exit_code=3)
        length = len(payload)
        if length < 126:
            length_field = bytes([0x80 | length])
        elif length <= 0xFFFF:
            length_field = bytes([0x80 | 126]) + struct.pack("!H", length)
        else:
            length_field = bytes([0x80 | 127]) + struct.pack("!Q", length)
        mask = os.urandom(4)
        masked = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))
        frame = bytes([0x80 | opcode]) + length_field + mask + masked
        try:
            with self._send_lock:
                sock.sendall(frame)
        except (socket.timeout, TimeoutError) as exc:
            raise PipelineError("ASR", "Zeitüberschreitung beim Senden des Audiostreams", category="timeout", exit_code=3) from exc
        except OSError as exc:
            raise PipelineError("ASR", f"Fehler beim Senden des Audiostreams: {exc}", exit_code=3) from exc

    def recv_text(self) -> str:
        fragments = bytearray()
        fragmented_opcode: int | None = None
        try:
            while True:
                first, second = self._recv_exact(2)
                fin = bool(first & 0x80)
                opcode = first & 0x0F
                masked = bool(second & 0x80)
                length = second & 0x7F
                if length == 126:
                    length = struct.unpack("!H", self._recv_exact(2))[0]
                elif length == 127:
                    length = struct.unpack("!Q", self._recv_exact(8))[0]
                mask = self._recv_exact(4) if masked else None
                payload = self._recv_exact(length) if length else b""
                if mask is not None:
                    payload = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))

                if opcode == 0x8:
                    raise PipelineError("ASR", "WebSocket wurde vor ASR-Ende geschlossen", exit_code=3)
                if opcode == 0x9:
                    self.send_pong(payload)
                    continue
                if opcode == 0xA:
                    continue
                if opcode in {0x1, 0x2}:
                    if fragmented_opcode is not None:
                        raise PipelineError("ASR", "Ungültige verschachtelte WebSocket-Fragmente", exit_code=3)
                    if fin:
                        if opcode != 0x1:
                            raise PipelineError("ASR", "Unerwarteter binärer Serverframe", exit_code=3)
                        return payload.decode("utf-8")
                    fragmented_opcode = opcode
                    fragments.extend(payload)
                    continue
                if opcode == 0x0:
                    if fragmented_opcode is None:
                        raise PipelineError("ASR", "Unerwarteter WebSocket-Continuation-Frame", exit_code=3)
                    fragments.extend(payload)
                    if fin:
                        if fragmented_opcode != 0x1:
                            raise PipelineError("ASR", "Unerwartete binäre Servernachricht", exit_code=3)
                        fragmented_opcode = None
                        return bytes(fragments).decode("utf-8")
                    continue
                raise PipelineError("ASR", f"Nicht unterstützter WebSocket-Opcode {opcode}", exit_code=3)
        except UnicodeDecodeError as exc:
            raise PipelineError("ASR", "ASR-WebSocket lieferte ungültiges UTF-8", exit_code=3) from exc
        except (socket.timeout, TimeoutError) as exc:
            raise PipelineError("ASR", f"Zeitüberschreitung beim Empfang von {self.url}", category="timeout", exit_code=3) from exc

    def recv_json(self) -> Mapping[str, Any]:
        text = self.recv_text()
        try:
            value = json.loads(text)
        except json.JSONDecodeError as exc:
            raise PipelineError("ASR", f"Ungültiges ASR-WebSocket-JSON: {exc}", exit_code=3) from exc
        if not isinstance(value, Mapping):
            raise PipelineError("ASR", "ASR-WebSocket-JSON ist kein Objekt", exit_code=3)
        return value

    def close(self) -> None:
        sock, self._sock = self._sock, None
        if sock is None:
            return
        with contextlib.suppress(OSError):
            sock.shutdown(socket.SHUT_RDWR)
        with contextlib.suppress(OSError):
            sock.close()


def stream_asr(
    *,
    url: str,
    input_audio: InputAudio,
    chunk_ms: int,
    realtime: bool,
    clock: BenchmarkClock,
    console: Console,
    stats: ASRStats,
) -> str:
    ws = WebSocketClient(url)
    sender_error: list[PipelineError] = []
    stop_sender = threading.Event()
    sender_thread: threading.Thread | None = None
    confirmed = ConfirmedTranscriptAssembler()
    try:
        ws.connect()
        ready = ws.recv_json()
        if ready.get("type") != "ready" or ready.get("protocol") != ASR_PROTOCOL:
            raise PipelineError("ASR", f"Ungültiges ready-Ereignis: {safe_mapping_detail(ready)}", exit_code=3)
        audio = ready.get("audio")
        if not isinstance(audio, Mapping) or (
            audio.get("encoding") != "pcm_s16le"
            or audio.get("sample_rate") != ASR_SAMPLE_RATE
            or audio.get("channels") != ASR_CHANNELS
        ):
            raise PipelineError("ASR", f"ASR meldet unerwartetes Audioformat: {safe_mapping_detail(audio)}", exit_code=3)
        clock.mark("ASR_READY", f"ASR bereit ({ASR_PROTOCOL})")

        chunk_bytes = max(
            PCM_SAMPLE_WIDTH_BYTES,
            round(ASR_BYTES_PER_SECOND * chunk_ms / 1000),
        )
        chunk_bytes -= chunk_bytes % PCM_SAMPLE_WIDTH_BYTES
        pcm = input_audio.asr_pcm_bytes

        def sender() -> None:
            try:
                stream_start_ns: int | None = None
                sent_bytes = 0
                for offset in range(0, len(pcm), chunk_bytes):
                    if stop_sender.is_set():
                        return
                    block = pcm[offset : offset + chunk_bytes]
                    ws.send_binary(block)
                    now_ns = time.perf_counter_ns()
                    if stream_start_ns is None:
                        stream_start_ns = now_ns
                        clock.mark("T1", "Erster ASR-PCM-Block gesendet")
                    stats.chunks_sent += 1
                    stats.bytes_sent += len(block)
                    sent_bytes += len(block)
                    if realtime and stream_start_ns is not None:
                        target_ns = stream_start_ns + round(sent_bytes / ASR_BYTES_PER_SECOND * 1_000_000_000)
                        while not stop_sender.is_set():
                            remaining = (target_ns - time.perf_counter_ns()) / 1_000_000_000
                            if remaining <= 0:
                                break
                            stop_sender.wait(min(remaining, 0.05))
                if stop_sender.is_set():
                    return
                ws.send_binary(b"")
                clock.mark("ASR_AUDIO_END", "ASR-Audioende gesendet")
            except PipelineError as exc:
                sender_error.append(exc)
                stop_sender.set()
                ws.close()

        sender_thread = threading.Thread(target=sender, name="kienzlefon-asr-sender", daemon=True)
        sender_thread.start()

        while True:
            try:
                event = ws.recv_json()
            except PipelineError:
                if sender_error:
                    raise sender_error[0]
                raise
            event_type = event.get("type")
            if event_type == "partial":
                text = event.get("text")
                if isinstance(text, str):
                    text = text.strip()
                    if text and text != stats.last_partial:
                        stats.last_partial = text
                        stats.partial_count += 1
                        clock.mark("ASR_FIRST_PARTIAL", "Erstes ASR-Partial")
                        console.log(f"[ASR partial] {text}")
            elif event_type == "confirmed":
                text = event.get("text")
                if isinstance(text, str) and text.strip():
                    text = text.strip()
                    action = confirmed.add(text=text, start=event.get("start"), end=event.get("end"))
                    stats.confirmed_count += 1
                    stats.confirmed_segment_count = confirmed.segment_count
                    stats.confirmed_revision_count = confirmed.revision_count
                    clock.mark("ASR_FIRST_CONFIRMED", "Erstes ASR-Confirmed")
                    label = "ASR confirmed revision" if action == "revision" else "ASR confirmed"
                    console.log(f"[{label}] {text}")
            elif event_type == "end":
                clock.mark("T2", "ASR vollständig")
                break
            elif event_type == "error":
                code = event.get("code")
                raise PipelineError("ASR", f"ASR-Stream meldete Fehler{': ' + str(code) if code else ''}", exit_code=3)
            elif event_type == "ready":
                continue
            else:
                raise PipelineError("ASR", f"Unbekanntes ASR-Ereignis: {safe_mapping_detail(event)}", exit_code=3)

        stop_sender.set()
        if sender_thread is not None:
            sender_thread.join(timeout=2.0)
        if sender_error:
            raise sender_error[0]
        transcript = confirmed.transcript()
        stats.confirmed_segment_count = confirmed.segment_count
        stats.confirmed_revision_count = confirmed.revision_count
        if not transcript:
            raise PipelineError("ASR", "ASR lieferte kein bestätigtes Transkript", exit_code=3)
        clock.elapsed_log(f"Transkript: {transcript}")
        return transcript
    except PipelineError:
        raise
    except (OSError, ssl.SSLError) as exc:
        raise PipelineError("ASR", f"WebSocket-Fehler bei {url}: {exc}", exit_code=3) from exc
    finally:
        stop_sender.set()
        ws.close()
        if sender_thread is not None and sender_thread.is_alive():
            sender_thread.join(timeout=2.0)


def safe_mapping_detail(value: Any, limit: int = 400) -> str:
    try:
        text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    except (TypeError, ValueError):
        text = repr(value)
    return text if len(text) <= limit else text[:limit] + "…"


def stream_llm(
    url: str,
    transcript: str,
    system_prompt: str,
    max_tokens: int,
    temperature: float,
    clock: BenchmarkClock,
    console: Console,
    tts_queue: queue.Queue[str | None],
    worker_error: SharedWorkerError,
) -> LLMStats:
    payload = {
        "model": "default",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": transcript},
        ],
        "stream": True,
        "stream_options": {"include_usage": True},
        "max_tokens": max_tokens,
        "temperature": temperature,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    connection, path = open_http_connection(url)
    chunker = SpeakableChunker()
    stats = LLMStats()
    first_token_seen = False

    try:
        connection.putrequest("POST", path)
        connection.putheader("Content-Type", "application/json; charset=utf-8")
        connection.putheader("Accept", "text/event-stream")
        connection.putheader("Authorization", "Bearer no-key")
        connection.putheader("Content-Length", str(len(body)))
        connection.endheaders()
        connection.send(body)
        clock.mark("T3", "LLM-Anfrage gesendet")
        response = connection.getresponse()

        if not 200 <= response.status < 300:
            response_body = response.read()
            raise PipelineError(
                "LLM",
                f"HTTP {response.status} {response.reason}: {safe_response_detail(response_body)}",
                exit_code=4,
            )
        content_type = response.getheader("Content-Type", "").lower()
        if "text/event-stream" not in content_type:
            response_body = response.read()
            raise PipelineError(
                "LLM",
                (
                    "Streaming wurde angefordert, aber der Server lieferte "
                    f"Content-Type {content_type or '<leer>'}: {safe_response_detail(response_body)}"
                ),
                exit_code=4,
            )

        while True:
            thread_failure = worker_error.get()
            if thread_failure is not None:
                raise thread_failure

            raw_line = response.readline()
            if not raw_line:
                break
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line or line.startswith(":") or not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                event = json.loads(data)
            except json.JSONDecodeError as exc:
                raise PipelineError("LLM", f"Ungültiges SSE-JSON: {exc}", exit_code=4) from exc

            update_llm_stats(event, stats)
            for text_piece in extract_llm_text(event):
                if not text_piece:
                    continue
                if not first_token_seen:
                    first_token_seen = True
                    clock.mark("T4", "LLM erstes Token")
                stats.output_characters += len(text_piece)
                console.llm(text_piece)
                for section in chunker.feed(text_piece):
                    enqueue_tts_section(section, tts_queue, clock, worker_error)

        for section in chunker.flush():
            enqueue_tts_section(section, tts_queue, clock, worker_error)

        if not first_token_seen:
            raise PipelineError("LLM", "LLM-Stream enthielt keinen Antworttext", exit_code=4)
        clock.mark("T9", "LLM vollständig")
        return stats
    except (socket.timeout, TimeoutError) as exc:
        raise PipelineError(
            "LLM",
            f"Zeitüberschreitung bei {url}",
            category="timeout",
            exit_code=4,
        ) from exc
    except PipelineError:
        raise
    except http.client.HTTPException as exc:
        raise PipelineError("LLM", f"Ungültige HTTP-/SSE-Antwort bei {url}: {exc}", exit_code=4) from exc
    except OSError as exc:
        raise PipelineError("LLM", f"Verbindungsfehler bei {url}: {exc}", exit_code=4) from exc
    finally:
        console.llm_end()
        connection.close()


def extract_llm_text(event: Any) -> Iterable[str]:
    if not isinstance(event, Mapping):
        return []
    choices = event.get("choices")
    if not isinstance(choices, list):
        return []
    pieces: list[str] = []
    for choice in choices:
        if not isinstance(choice, Mapping):
            continue
        delta = choice.get("delta")
        if isinstance(delta, Mapping):
            content = delta.get("content")
            if isinstance(content, str):
                pieces.append(content)
            elif isinstance(content, list):
                for item in content:
                    if isinstance(item, Mapping) and isinstance(item.get("text"), str):
                        pieces.append(item["text"])
        text = choice.get("text")
        if isinstance(text, str):
            pieces.append(text)
    return pieces


def update_llm_stats(event: Any, stats: LLMStats) -> None:
    if not isinstance(event, Mapping):
        return
    usage = event.get("usage")
    if isinstance(usage, Mapping):
        completion_tokens = usage.get("completion_tokens")
        if isinstance(completion_tokens, int):
            stats.completion_tokens = completion_tokens

    timings = event.get("timings")
    if isinstance(timings, Mapping):
        predicted_n = timings.get("predicted_n")
        if isinstance(predicted_n, int):
            stats.predicted_tokens = predicted_n
        predicted_per_second = timings.get("predicted_per_second")
        if isinstance(predicted_per_second, (int, float)):
            stats.server_tokens_per_second = float(predicted_per_second)

    choices = event.get("choices")
    if isinstance(choices, list):
        for choice in choices:
            if isinstance(choice, Mapping) and isinstance(choice.get("finish_reason"), str):
                stats.finish_reason = choice["finish_reason"]


def enqueue_tts_section(
    section: str,
    tts_queue: queue.Queue[str | None],
    clock: BenchmarkClock,
    worker_error: SharedWorkerError,
) -> None:
    failure = worker_error.get()
    if failure is not None:
        raise failure
    if clock.get("T5") is None:
        clock.mark("T5", f"Erster TTS-Abschnitt: {section}")
    tts_queue.put(section)


def tts_worker(
    *,
    args: argparse.Namespace,
    output_path: Path,
    sections: queue.Queue[str | None],
    clock: BenchmarkClock,
    stats: TTSStats,
    player_stats: PlayerStats,
    worker_error: SharedWorkerError,
    run_id: str,
) -> None:
    output_file: BinaryIO | None = None
    playback: PlaybackController | None = None
    synthesis_succeeded = False
    try:
        stats.backend = args.tts
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_file = open(output_path, "wb", buffering=0)
        stats.output_opened = True

        expected_rate, expected_channels = expected_tts_format(args.tts)
        stats.response_sample_rate = expected_rate
        stats.response_channels = expected_channels
        if args.play:
            playback = PlaybackController(
                command=args.player,
                sample_rate=expected_rate,
                channels=expected_channels,
                clock=clock,
                stats=player_stats,
            )
            playback.start()

        section_index = 0
        while True:
            section = sections.get()
            try:
                if section is None:
                    break
                section_index += 1
                if args.tts == "qwen":
                    synthesize_qwen_section(
                        url=args.tts_url,
                        text=section,
                        output_file=output_file,
                        playback=playback,
                        section_index=section_index,
                        speaker=args.qwen_speaker,
                        language=args.qwen_language,
                        seed=args.qwen_seed,
                        clock=clock,
                        stats=stats,
                    )
                elif args.tts == "piper":
                    synthesize_piper_section(
                        url=args.tts_url,
                        text=section,
                        output_file=output_file,
                        playback=playback,
                        section_index=section_index,
                        clock=clock,
                        stats=stats,
                    )
                else:
                    synthesize_say_section(
                        text=section,
                        output_file=output_file,
                        playback=playback,
                        section_index=section_index,
                        run_id=run_id,
                        voice=args.say_voice,
                        rate=args.say_rate,
                        clock=clock,
                        stats=stats,
                    )
            finally:
                sections.task_done()

        if stats.section_count == 0 or stats.output_bytes == 0:
            raise PipelineError(
                tts_service_name(args.tts),
                "Es wurde keine Audioausgabe erzeugt",
                exit_code=5,
            )
        if stats.output_bytes % PCM_SAMPLE_WIDTH_BYTES != 0:
            raise PipelineError(
                tts_service_name(args.tts),
                "TTS-Ausgabe endet nicht auf einer vollständigen PCM16-Probe",
                exit_code=5,
            )
        stats.output_complete = True
        synthesis_succeeded = True
        clock.mark("T10", f"TTS vollständig ({args.tts})")
    except PipelineError as exc:
        worker_error.set(exc)
    except OSError as exc:
        worker_error.set(
            PipelineError(tts_service_name(args.tts), f"Ausgabedatei-Fehler: {exc}", exit_code=5)
        )
    except Exception as exc:  # Defensive boundary for the worker thread.
        worker_error.set(
            PipelineError(
                tts_service_name(args.tts),
                f"Unerwarteter Worker-Fehler: {exc}",
                exit_code=5,
            )
        )
    finally:
        if output_file is not None:
            with contextlib.suppress(OSError):
                output_file.flush()
                os.fsync(output_file.fileno())
            with contextlib.suppress(OSError):
                output_file.close()
        if clock.t0_ns is not None:
            clock.mark("T11", "Ausgabedatei geschlossen")

        if playback is not None:
            try:
                if synthesis_succeeded:
                    playback.finish()
                else:
                    playback.abort()
            except PipelineError as exc:
                worker_error.set(exc)


def tts_service_name(backend: str) -> str:
    return {"qwen": "Qwen3-TTS", "piper": "Piper", "say": "macOS say"}.get(backend, "TTS")


def write_all(stream: BinaryIO, data: bytes, *, service: str) -> None:
    """Write every byte or raise instead of accepting a short write."""
    view = memoryview(data)
    while view:
        written = stream.write(view)
        if written is None or written <= 0:
            raise PipelineError(service, "Unvollständiger Schreibvorgang", exit_code=5)
        view = view[written:]


def emit_pcm_block(
    *,
    block: bytes,
    output_file: BinaryIO,
    playback: PlaybackController | None,
    clock: BenchmarkClock,
    stats: TTSStats,
) -> None:
    if not block:
        return
    if clock.get("T7") is None:
        clock.mark("T7", "Erster TTS-PCM-Block empfangen")
    write_all(output_file, block, service="Ausgabedatei")
    stats.output_bytes += len(block)
    if clock.get("T8") is None:
        clock.mark("T8", "Erster PCM-Block geschrieben")
    if playback is not None:
        playback.enqueue(block)


def expected_tts_format(backend: str) -> tuple[int, int]:
    if backend == "qwen":
        return QWEN_SAMPLE_RATE, QWEN_CHANNELS
    if backend == "piper":
        return PIPER_SAMPLE_RATE, PIPER_CHANNELS
    if backend == "say":
        return SAY_SAMPLE_RATE, SAY_CHANNELS
    raise PipelineError("TTS", f"Unbekanntes TTS-Backend: {backend}", exit_code=5)


def synthesize_qwen_section(
    *,
    url: str,
    text: str,
    output_file: BinaryIO,
    playback: PlaybackController | None,
    section_index: int,
    speaker: str,
    language: str,
    seed: int,
    clock: BenchmarkClock,
    stats: TTSStats,
) -> None:
    payload = {"text": text, "speaker": speaker, "language": language, "seed": seed}
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    connection, path = open_http_connection(url)
    request_start_ns = time.perf_counter_ns()
    try:
        connection.putrequest("POST", path)
        connection.putheader("Content-Type", "application/json; charset=utf-8")
        connection.putheader("Accept", "audio/pcm")
        connection.putheader("Content-Length", str(len(body)))
        connection.endheaders()
        connection.send(body)
        if clock.get("T6") is None:
            clock.mark("T6", "Erster Qwen3-TTS-Auftrag")
        response = connection.getresponse()
        if not 200 <= response.status < 300:
            response_body = response.read()
            raise PipelineError(
                "Qwen3-TTS",
                f"HTTP {response.status} {response.reason}: {safe_response_detail(response_body)}",
                exit_code=5,
            )
        content_type = response.getheader("Content-Type", "").lower()
        if "audio/pcm" not in content_type and "application/octet-stream" not in content_type:
            response_body = response.read(500)
            raise PipelineError(
                "Qwen3-TTS",
                f"Raw-PCM erwartet, Content-Type {content_type or '<leer>'}: {safe_response_detail(response_body)}",
                exit_code=5,
            )
        validate_qwen_audio_headers(response, stats)
        received_any = False
        read_method = getattr(response, "read1", response.read)
        while True:
            block = read_method(READ_BLOCK_BYTES)
            if not block:
                break
            if not received_any:
                if len(block) >= 12 and block[:4] == b"RIFF" and block[8:12] == b"WAVE":
                    raise PipelineError("Qwen3-TTS", "Raw-PCM erwartet, aber WAV erhalten", exit_code=5)
                received_any = True
            emit_pcm_block(
                block=block,
                output_file=output_file,
                playback=playback,
                clock=clock,
                stats=stats,
            )
        if not received_any:
            raise PipelineError("Qwen3-TTS", f"Abschnitt {section_index} lieferte kein PCM", exit_code=5)
        stats.section_count += 1
    except (socket.timeout, TimeoutError) as exc:
        raise PipelineError(
            "Qwen3-TTS",
            f"Zeitüberschreitung bei Abschnitt {section_index} ({url})",
            category="timeout",
            exit_code=5,
        ) from exc
    except PipelineError:
        raise
    except http.client.HTTPException as exc:
        raise PipelineError("Qwen3-TTS", f"Ungültige HTTP-/Audioantwort ({url}): {exc}", exit_code=5) from exc
    except OSError as exc:
        raise PipelineError("Qwen3-TTS", f"Verbindungsfehler ({url}): {exc}", exit_code=5) from exc
    finally:
        stats.request_durations_seconds.append((time.perf_counter_ns() - request_start_ns) / 1_000_000_000.0)
        connection.close()


def validate_qwen_audio_headers(response: http.client.HTTPResponse, stats: TTSStats) -> None:
    rate = response.getheader("X-Sample-Rate")
    fmt = response.getheader("X-Sample-Format")
    channels = response.getheader("X-Channels")
    if rate is None or fmt is None or channels is None:
        raise PipelineError(
            "Qwen3-TTS",
            "Streaming-Antwort enthält nicht alle PCM-Formatheader "
            "(X-Sample-Rate/X-Sample-Format/X-Channels)",
            exit_code=5,
        )
    try:
        detected_rate = int(rate)
        detected_channels = int(channels)
    except ValueError as exc:
        raise PipelineError("Qwen3-TTS", "Ungültige numerische PCM-Formatheader", exit_code=5) from exc
    if detected_rate != QWEN_SAMPLE_RATE or detected_channels != QWEN_CHANNELS or fmt.lower() != QWEN_FORMAT:
        raise PipelineError(
            "Qwen3-TTS",
            f"Unerwartetes PCM-Format: {detected_rate} Hz, {detected_channels} Kanal/Kanäle, {fmt}; "
            f"erwartet {QWEN_SAMPLE_RATE} Hz, {QWEN_CHANNELS} Kanal, {QWEN_FORMAT}",
            exit_code=5,
        )
    stats.response_sample_rate = detected_rate
    stats.response_channels = detected_channels


def synthesize_piper_section(
    *,
    url: str,
    text: str,
    output_file: BinaryIO,
    playback: PlaybackController | None,
    section_index: int,
    clock: BenchmarkClock,
    stats: TTSStats,
) -> None:
    # Aktueller Kienzlefon-Piper-Dienst: Raw-PCM wird explizit über
    # response_format=pcm angefordert. Ohne diese Angabe wäre WAV der Default.
    payload = {"input": text, "response_format": "pcm"}
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    connection, path = open_http_connection(url)
    request_start_ns = time.perf_counter_ns()
    try:
        connection.putrequest("POST", path)
        connection.putheader("Content-Type", "application/json; charset=utf-8")
        connection.putheader("Accept", "audio/pcm, application/octet-stream")
        connection.putheader("Content-Length", str(len(body)))
        connection.endheaders()
        connection.send(body)
        if clock.get("T6") is None:
            clock.mark("T6", "Erster Piper-Auftrag")
        response = connection.getresponse()

        if not 200 <= response.status < 300:
            response_body = response.read()
            raise PipelineError(
                "Piper",
                f"HTTP {response.status} {response.reason}: {safe_response_detail(response_body)}",
                exit_code=5,
            )
        content_type = response.getheader("Content-Type", "").lower()
        if "wav" in content_type or "wave" in content_type:
            response.read(500)
            raise PipelineError(
                "Piper",
                "Raw-PCM erwartet, aber Piper lieferte WAV-Audio",
                exit_code=5,
            )
        if "json" in content_type:
            response_body = response.read()
            raise PipelineError(
                "Piper",
                f"Audio erwartet, JSON erhalten: {safe_response_detail(response_body)}",
                exit_code=5,
            )

        update_audio_format_from_headers(response, stats)
        received_any = False
        read_method = getattr(response, "read1", response.read)
        while True:
            block = read_method(READ_BLOCK_BYTES)
            if not block:
                break
            if not received_any:
                if len(block) >= 12 and block[:4] == b"RIFF" and block[8:12] == b"WAVE":
                    raise PipelineError(
                        "Piper",
                        "Raw-PCM erwartet, aber Piper lieferte einen WAV-Dateikopf",
                        exit_code=5,
                    )
                received_any = True
            emit_pcm_block(
                block=block,
                output_file=output_file,
                playback=playback,
                clock=clock,
                stats=stats,
            )

        if not received_any:
            raise PipelineError("Piper", f"Abschnitt {section_index} lieferte kein PCM", exit_code=5)
        stats.section_count += 1
    except (socket.timeout, TimeoutError) as exc:
        raise PipelineError(
            "Piper",
            f"Zeitüberschreitung bei Abschnitt {section_index} ({url})",
            category="timeout",
            exit_code=5,
        ) from exc
    except PipelineError:
        raise
    except http.client.HTTPException as exc:
        raise PipelineError(
            "Piper",
            f"Ungültige HTTP-/Audioantwort bei Abschnitt {section_index} ({url}): {exc}",
            exit_code=5,
        ) from exc
    except OSError as exc:
        raise PipelineError(
            "Piper",
            f"Verbindungsfehler bei Abschnitt {section_index} ({url}): {exc}",
            exit_code=5,
        ) from exc
    finally:
        stats.request_durations_seconds.append(
            (time.perf_counter_ns() - request_start_ns) / 1_000_000_000.0
        )
        connection.close()


def synthesize_say_section(
    *,
    text: str,
    output_file: BinaryIO,
    playback: PlaybackController | None,
    section_index: int,
    run_id: str,
    voice: str | None,
    rate: int | None,
    clock: BenchmarkClock,
    stats: TTSStats,
) -> None:
    say_command = resolve_executable("say", service="macOS say")
    ffmpeg_command = resolve_executable("ffmpeg", service="macOS say")
    request_start_ns = time.perf_counter_ns()
    try:
        with tempfile.TemporaryDirectory(prefix=f"kienzlefon-say-{run_id[:8]}-") as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            text_path = temp_dir / f"section-{section_index:04d}.txt"
            aiff_path = temp_dir / f"section-{section_index:04d}.aiff"
            text_path.write_text(text, encoding="utf-8")

            command = [say_command]
            if voice:
                command.extend(["-v", voice])
            if rate is not None:
                command.extend(["-r", str(rate)])
            command.extend(["-o", str(aiff_path), "-f", str(text_path)])
            if clock.get("T6") is None:
                clock.mark("T6", "Erster macOS-say-Auftrag")
            try:
                completed = subprocess.run(
                    command,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    timeout=HTTP_TIMEOUT_SECONDS,
                    check=False,
                )
            except subprocess.TimeoutExpired as exc:
                raise PipelineError(
                    "macOS say",
                    f"Zeitüberschreitung bei Abschnitt {section_index}",
                    category="timeout",
                    exit_code=5,
                ) from exc
            if completed.returncode != 0:
                detail = completed.stderr.decode("utf-8", errors="replace").strip()
                raise PipelineError(
                    "macOS say",
                    f"say endete bei Abschnitt {section_index} mit Status "
                    f"{completed.returncode}: {detail or 'keine Fehlerausgabe'}",
                    exit_code=5,
                )
            if not aiff_path.is_file() or aiff_path.stat().st_size == 0:
                raise PipelineError(
                    "macOS say",
                    f"say erzeugte für Abschnitt {section_index} keine Audiodatei",
                    exit_code=5,
                )

            with tempfile.TemporaryFile(mode="w+b") as ffmpeg_stderr:
                ffmpeg_command_line = [
                    ffmpeg_command,
                    "-v",
                    "error",
                    "-nostdin",
                    "-i",
                    str(aiff_path),
                    "-vn",
                    "-ac",
                    str(SAY_CHANNELS),
                    "-ar",
                    str(SAY_SAMPLE_RATE),
                    "-c:a",
                    "pcm_s16le",
                    "-f",
                    "s16le",
                    "pipe:1",
                ]
                try:
                    process = subprocess.Popen(
                        ffmpeg_command_line,
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.PIPE,
                        stderr=ffmpeg_stderr,
                        bufsize=0,
                    )
                except OSError as exc:
                    raise PipelineError(
                        "macOS say",
                        f"FFmpeg konnte nicht gestartet werden: {exc}",
                        exit_code=5,
                    ) from exc
                if process.stdout is None:
                    process.kill()
                    raise PipelineError("macOS say", "FFmpeg-stdout ist nicht verfügbar", exit_code=5)

                received_any = False
                try:
                    while True:
                        block = process.stdout.read(READ_BLOCK_BYTES)
                        if not block:
                            break
                        received_any = True
                        emit_pcm_block(
                            block=block,
                            output_file=output_file,
                            playback=playback,
                            clock=clock,
                            stats=stats,
                        )
                finally:
                    with contextlib.suppress(OSError):
                        process.stdout.close()
                try:
                    return_code = process.wait(timeout=HTTP_TIMEOUT_SECONDS)
                except subprocess.TimeoutExpired as exc:
                    with contextlib.suppress(OSError):
                        process.kill()
                    process.wait()
                    raise PipelineError(
                        "macOS say",
                        f"Zeitüberschreitung bei der PCM-Konvertierung von Abschnitt {section_index}",
                        category="timeout",
                        exit_code=5,
                    ) from exc
                if return_code != 0:
                    ffmpeg_stderr.flush()
                    ffmpeg_stderr.seek(0)
                    detail = ffmpeg_stderr.read(4096).decode("utf-8", errors="replace").strip()
                    raise PipelineError(
                        "macOS say",
                        f"FFmpeg endete bei Abschnitt {section_index} mit Status "
                        f"{return_code}: {detail or 'keine Fehlerausgabe'}",
                        exit_code=5,
                    )
                if not received_any:
                    raise PipelineError(
                        "macOS say",
                        f"Abschnitt {section_index} lieferte kein PCM",
                        exit_code=5,
                    )
            stats.section_count += 1
    except PipelineError:
        raise
    except OSError as exc:
        raise PipelineError(
            "macOS say",
            f"Datei- oder Prozessfehler bei Abschnitt {section_index}: {exc}",
            exit_code=5,
        ) from exc
    finally:
        stats.request_durations_seconds.append(
            (time.perf_counter_ns() - request_start_ns) / 1_000_000_000.0
        )


def update_audio_format_from_headers(response: http.client.HTTPResponse, stats: TTSStats) -> None:
    detected_rate = PIPER_SAMPLE_RATE
    detected_channels = PIPER_CHANNELS

    sample_rate_header = response.getheader("X-Sample-Rate")
    channels_header = response.getheader("X-Channels")
    if sample_rate_header and sample_rate_header.isdigit():
        detected_rate = int(sample_rate_header)
    if channels_header and channels_header.isdigit():
        detected_channels = int(channels_header)

    content_type = response.getheader("Content-Type", "")
    rate_match = re.search(r"(?:rate|sample_rate)\s*=\s*(\d+)", content_type, re.IGNORECASE)
    channels_match = re.search(r"channels\s*=\s*(\d+)", content_type, re.IGNORECASE)
    if rate_match:
        detected_rate = int(rate_match.group(1))
    if channels_match:
        detected_channels = int(channels_match.group(1))

    if detected_rate != PIPER_SAMPLE_RATE or detected_channels != PIPER_CHANNELS:
        raise PipelineError(
            "Piper",
            (
                "Unerwartetes PCM-Format: "
                f"{detected_rate} Hz, {detected_channels} Kanal/Kanäle; "
                f"erwartet sind {PIPER_SAMPLE_RATE} Hz, {PIPER_CHANNELS} Kanal"
            ),
            exit_code=5,
        )
    stats.response_sample_rate = detected_rate
    stats.response_channels = detected_channels


def safe_response_detail(body: bytes, limit: int = 500) -> str:
    text = body.decode("utf-8", errors="replace")
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > limit:
        text = text[:limit] + "…"
    return text or "keine Fehlerdetails"


def seconds_between(clock: BenchmarkClock, start: str, end: str) -> float | None:
    start_ns = clock.get(start)
    end_ns = clock.get(end)
    if start_ns is None or end_ns is None:
        return None
    return (end_ns - start_ns) / 1_000_000_000.0


def safe_ratio(numerator: float | None, denominator: float | None) -> float | None:
    if numerator is None or denominator is None or denominator <= 0:
        return None
    return numerator / denominator


def build_report(
    *,
    status: str,
    args: argparse.Namespace,
    input_audio: InputAudio | None,
    asr_stats: ASRStats,
    clock: BenchmarkClock,
    llm_stats: LLMStats,
    tts_stats: TTSStats,
    player_stats: PlayerStats,
    run_id: str,
    started_at_utc: str,
    error: PipelineError | None,
    metadata_path: Path,
    actual_output_path: Path | None,
) -> dict[str, Any]:
    input_duration = input_audio.duration_seconds if input_audio else None
    asr_duration = input_audio.asr_duration_seconds if input_audio else None
    asr_total = seconds_between(clock, "T1", "T2")
    asr_feed = seconds_between(clock, "T1", "ASR_AUDIO_END")
    asr_tail = seconds_between(clock, "ASR_AUDIO_END", "T2")
    asr_first_partial = seconds_between(clock, "T1", "ASR_FIRST_PARTIAL")
    asr_first_confirmed = seconds_between(clock, "T1", "ASR_FIRST_CONFIRMED")
    llm_ttft = seconds_between(clock, "T3", "T4")
    first_speakable = seconds_between(clock, "T3", "T5")
    tts_ttfa = seconds_between(clock, "T6", "T7")
    first_pcm_total = seconds_between(clock, "T0", "T7")
    first_pcm_written_total = seconds_between(clock, "T0", "T8")
    llm_total = seconds_between(clock, "T3", "T9")
    tts_request_total = sum(tts_stats.request_durations_seconds) if tts_stats.request_durations_seconds else None
    tts_wall = seconds_between(clock, "T6", "T10")
    bytes_per_second = tts_stats.response_sample_rate * tts_stats.response_channels * PCM_SAMPLE_WIDTH_BYTES
    generated_duration = tts_stats.output_bytes / bytes_per_second if bytes_per_second > 0 else None
    pipeline_total = seconds_between(clock, "T0", "T11")

    token_count = llm_stats.completion_tokens if llm_stats.completion_tokens is not None else llm_stats.predicted_tokens
    token_rate = llm_stats.server_tokens_per_second
    token_rate_source = "llama_server_timings" if token_rate is not None else None
    if token_rate is None and token_count is not None:
        generation_seconds = seconds_between(clock, "T4", "T9")
        token_rate = safe_ratio(float(token_count), generation_seconds)
        if token_rate is not None:
            token_rate_source = "completion_tokens_over_T4_T9"

    player_started = relative_seconds(clock, player_stats.process_started_ns)
    player_first_queued = relative_seconds(clock, player_stats.first_block_queued_ns)
    player_first_written = relative_seconds(clock, player_stats.first_block_written_ns)
    player_finished = relative_seconds(clock, player_stats.process_finished_ns)
    player_handoff = timestamp_delta_seconds(player_stats.first_block_queued_ns, player_stats.first_block_written_ns)

    extra_events = {
        name: round(clock.seconds_from_t0(ts), 9)
        for name, ts in clock.events_ns.items()
        if not re.fullmatch(r"T\d+", name)
    }
    return {
        "schema_version": 3,
        "program": f"kienzlefon-ai-pipeline-test-v{PROGRAM_VERSION}.py",
        "program_version": PROGRAM_VERSION,
        "run_id": run_id,
        "status": status,
        "started_at_utc": started_at_utc,
        "finished_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "platform": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "python": platform.python_version(),
            "sys_platform": sys.platform,
        },
        "configuration": {
            "asr_protocol": ASR_PROTOCOL,
            "asr_url": args.asr_url,
            "asr_chunk_ms": args.asr_chunk_ms,
            "realtime_input": args.realtime_input,
            "llm_url": args.llm_url,
            "tts_backend": args.tts,
            "tts_url": args.tts_url,
            "input_rate_hz": args.input_rate,
            "input_channels": args.input_channels,
            "asr_rate_hz": ASR_SAMPLE_RATE,
            "asr_channels": ASR_CHANNELS,
            "qwen_speaker": args.qwen_speaker if args.tts == "qwen" else None,
            "qwen_language": args.qwen_language if args.tts == "qwen" else None,
            "qwen_seed": args.qwen_seed if args.tts == "qwen" else None,
            "tts_voice": PIPER_VOICE if args.tts == "piper" else (args.say_voice if args.tts == "say" else args.qwen_speaker),
            "piper_response_format": "pcm" if args.tts == "piper" else None,
            "say_rate_words_per_minute": args.say_rate if args.tts == "say" else None,
            "tts_format": "pcm_s16le",
            "tts_sample_rate_hz": tts_stats.response_sample_rate,
            "playback_enabled": args.play,
            "player": args.player if args.play else None,
            "stream_read_block_bytes": READ_BLOCK_BYTES,
            "max_tokens": args.max_tokens,
            "temperature": args.temperature,
        },
        "files": {
            "input": str(args.input),
            "output": str(actual_output_path) if actual_output_path else None,
            "pcm_metadata": str(metadata_path),
            "benchmark_report": str(args.report),
        },
        "input": {
            "source_bytes": len(input_audio.raw_bytes) if input_audio else None,
            "source_frames": input_audio.input_frames if input_audio else None,
            "source_duration_seconds": input_duration,
            "asr_pcm_bytes": len(input_audio.asr_pcm_bytes) if input_audio else None,
            "asr_frames": input_audio.asr_frames if input_audio else None,
            "asr_duration_seconds": asr_duration,
        },
        "events_seconds_from_T0": clock.event_seconds(),
        "asr_events_seconds_from_T0": extra_events,
        "metrics": {
            "input_audio_duration_seconds": input_duration,
            "asr_audio_duration_seconds": asr_duration,
            "asr_total_latency_seconds": asr_total,
            "asr_realtime_factor": safe_ratio(asr_total, asr_duration),
            "asr_feed_duration_seconds": asr_feed,
            "asr_feed_realtime_factor": safe_ratio(asr_feed, asr_duration),
            "asr_tail_latency_seconds": asr_tail,
            "asr_time_to_first_partial_seconds": asr_first_partial,
            "asr_time_to_first_confirmed_seconds": asr_first_confirmed,
            "asr_chunks_sent": asr_stats.chunks_sent,
            "asr_bytes_sent": asr_stats.bytes_sent,
            "asr_partial_count": asr_stats.partial_count,
            "asr_confirmed_count": asr_stats.confirmed_count,
            "asr_confirmed_segment_count": asr_stats.confirmed_segment_count,
            "asr_confirmed_revision_count": asr_stats.confirmed_revision_count,
            "llm_time_to_first_token_seconds": llm_ttft,
            "time_to_first_speakable_section_seconds": first_speakable,
            "tts_time_to_first_audio_seconds": tts_ttfa,
            "qwen_time_to_first_audio_seconds": tts_ttfa if args.tts == "qwen" else None,
            "piper_time_to_first_audio_seconds": tts_ttfa if args.tts == "piper" else None,
            "total_time_to_first_pcm_block_seconds": first_pcm_total,
            "total_time_to_first_pcm_written_seconds": first_pcm_written_total,
            "llm_total_seconds": llm_total,
            "llm_output_tokens": token_count,
            "llm_output_tokens_per_second": token_rate,
            "llm_output_tokens_per_second_source": token_rate_source,
            "llm_output_characters": llm_stats.output_characters,
            "tts_total_seconds": tts_request_total,
            "tts_request_total_seconds": tts_request_total,
            "tts_wall_seconds": tts_wall,
            "generated_audio_duration_seconds": generated_duration,
            "tts_realtime_factor": safe_ratio(tts_request_total, generated_duration),
            "tts_wall_realtime_factor": safe_ratio(tts_wall, generated_duration),
            "pipeline_total_seconds": pipeline_total,
            "tts_section_count": tts_stats.section_count,
            "qwen_section_count": tts_stats.section_count if args.tts == "qwen" else None,
            "piper_section_count": tts_stats.section_count if args.tts == "piper" else None,
            "output_pcm_bytes": tts_stats.output_bytes,
            "player_started_seconds_from_T0": player_started,
            "player_first_block_queued_seconds_from_T0": player_first_queued,
            "player_first_block_written_seconds_from_T0": player_first_written,
            "player_handoff_delay_seconds": player_handoff,
            "player_finished_seconds_from_T0": player_finished,
            "player_pcm_bytes_queued": player_stats.bytes_queued if args.play else None,
            "player_pcm_bytes_written": player_stats.bytes_written if args.play else None,
        },
        "llm": {
            "finish_reason": llm_stats.finish_reason,
            "completion_tokens_from_usage": llm_stats.completion_tokens,
            "predicted_tokens_from_timings": llm_stats.predicted_tokens,
            "predicted_tokens_per_second_from_timings": llm_stats.server_tokens_per_second,
        },
        "tts": {"backend": args.tts, "sections": tts_stats.section_count, "output_complete": tts_stats.output_complete},
        "player": {"enabled": args.play, "command": player_stats.command, "exit_code": player_stats.exit_code, "stderr": player_stats.stderr},
        "error": None if error is None else {"service": error.service, "category": error.category, "message": str(error), "exit_code": error.exit_code},
    }


def relative_seconds(clock: BenchmarkClock, timestamp_ns: int | None) -> float | None:
    if timestamp_ns is None or clock.t0_ns is None:
        return None
    return (timestamp_ns - clock.t0_ns) / 1_000_000_000.0


def timestamp_delta_seconds(start_ns: int | None, end_ns: int | None) -> float | None:
    if start_ns is None or end_ns is None:
        return None
    return (end_ns - start_ns) / 1_000_000_000.0


def build_pcm_metadata(
    *,
    status: str,
    tts_stats: TTSStats,
    run_id: str,
    output_path: Path | None,
) -> dict[str, Any]:
    bytes_per_second = (
        tts_stats.response_sample_rate * tts_stats.response_channels * PCM_SAMPLE_WIDTH_BYTES
    )
    duration = tts_stats.output_bytes / bytes_per_second if bytes_per_second > 0 else None
    return {
        "schema_version": 3,
        "run_id": run_id,
        "status": status,
        "file": str(output_path) if output_path else None,
        "encoding": "signed PCM",
        "sample_format": "s16le",
        "sample_rate_hz": tts_stats.response_sample_rate,
        "channels": tts_stats.response_channels,
        "sample_width_bits": 16,
        "byte_order": "little-endian",
        "bytes": tts_stats.output_bytes,
        "duration_seconds": duration,
        "tts_backend": tts_stats.backend,
        "tts_sections": tts_stats.section_count,
        "qwen_sections": tts_stats.section_count if tts_stats.backend == "qwen" else None,
        "piper_sections": tts_stats.section_count if tts_stats.backend == "piper" else None,
        "output_complete": tts_stats.output_complete,
        "created_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }


def write_json_atomic(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=path.parent,
            delete=False,
        ) as temp_file:
            temp_path = Path(temp_file.name)
            json.dump(payload, temp_file, ensure_ascii=False, indent=2, sort_keys=True)
            temp_file.write("\n")
            temp_file.flush()
            os.fsync(temp_file.fileno())
        os.replace(temp_path, path)
    except OSError as exc:
        if temp_path is not None:
            with contextlib.suppress(OSError):
                temp_path.unlink()
        raise PipelineError("Datei", f"JSON-Datei {path} konnte nicht geschrieben werden: {exc}") from exc


def finalize_failed_output(output_path: Path, *, output_complete: bool) -> Path | None:
    """Delete empty output, mark incomplete audio, preserve complete audio."""
    if not output_path.exists():
        return None
    try:
        if output_path.stat().st_size == 0:
            output_path.unlink()
            return None
    except OSError:
        return output_path
    if output_complete:
        return output_path
    return mark_partial_output(output_path)


def mark_partial_output(output_path: Path) -> Path | None:
    if not output_path.exists():
        return None
    try:
        if output_path.stat().st_size == 0:
            output_path.unlink()
            return None
        partial_path = output_path.with_name(output_path.name + ".partial")
        if partial_path.exists():
            partial_path.unlink()
        output_path.replace(partial_path)
        return partial_path
    except OSError:
        # Leaving the file in place is safer than silently deleting data when marking fails.
        return output_path


def print_benchmark_summary(console: Console, report: Mapping[str, Any], clock: BenchmarkClock) -> None:
    metrics = report.get("metrics", {})
    console.log("Benchmark:")
    labels = [
        ("Audiodauer Eingabe", "input_audio_duration_seconds", "s"),
        ("ASR-Gesamtlatenz", "asr_total_latency_seconds", "s"),
        ("ASR-Echtzeitfaktor", "asr_realtime_factor", "x"),
        ("ASR-Zuführdauer", "asr_feed_duration_seconds", "s"),
        ("ASR-Nachlauf nach Audioende", "asr_tail_latency_seconds", "s"),
        ("ASR erstes Partial", "asr_time_to_first_partial_seconds", "s"),
        ("ASR erstes Confirmed", "asr_time_to_first_confirmed_seconds", "s"),
        ("LLM Time to First Token", "llm_time_to_first_token_seconds", "s"),
        ("Erster sprechbarer Abschnitt", "time_to_first_speakable_section_seconds", "s"),
        ("TTS Time to First Audio", "tts_time_to_first_audio_seconds", "s"),
        ("Gesamtzeit bis erster PCM-Block", "total_time_to_first_pcm_block_seconds", "s"),
        ("LLM-Gesamtdauer", "llm_total_seconds", "s"),
        ("LLM-Ausgabetoken pro Sekunde", "llm_output_tokens_per_second", "tok/s"),
        ("TTS-Gesamtdauer (Auftragssumme)", "tts_request_total_seconds", "s"),
        ("TTS-Wandzeit", "tts_wall_seconds", "s"),
        ("Erzeugte Audiodauer", "generated_audio_duration_seconds", "s"),
        ("TTS-Echtzeitfaktor", "tts_realtime_factor", "x"),
        ("Pipeline-Gesamtdauer", "pipeline_total_seconds", "s"),
        ("TTS-Abschnitte", "tts_section_count", ""),
    ]
    if report.get("configuration", {}).get("playback_enabled"):
        labels.extend(
            [
                ("Player-Übergabeverzögerung", "player_handoff_delay_seconds", "s"),
                ("PCM-Bytes an Player", "player_pcm_bytes_written", "Byte"),
            ]
        )
    for label, key, unit in labels:
        value = metrics.get(key) if isinstance(metrics, Mapping) else None
        if value is None:
            rendered = "nicht verfügbar"
        elif isinstance(value, int):
            rendered = str(value)
        else:
            rendered = f"{float(value):.3f}"
        suffix = f" {unit}" if unit else ""
        console.log(f"  {label}: {rendered}{suffix}")
    if report.get("status") == "ok":
        clock.elapsed_log("Verarbeitung abgeschlossen")


def run(args: argparse.Namespace) -> int:
    console = Console()
    clock = BenchmarkClock(console=console)
    input_audio: InputAudio | None = None
    asr_stats = ASRStats()
    llm_stats = LLMStats()
    tts_stats = TTSStats(backend=args.tts)
    expected_rate, expected_channels = expected_tts_format(args.tts)
    tts_stats.response_sample_rate = expected_rate
    tts_stats.response_channels = expected_channels
    player_stats = PlayerStats(enabled=args.play)
    worker_error = SharedWorkerError()
    sections: queue.Queue[str | None] = queue.Queue()
    run_id = uuid.uuid4().hex
    started_at_utc = dt.datetime.now(dt.timezone.utc).isoformat()
    metadata_path = Path(str(args.output) + ".json")
    tts_thread: threading.Thread | None = None
    pipeline_error: PipelineError | None = None
    actual_output_path: Path | None = args.output

    try:
        if args.output.resolve() == args.input.resolve():
            raise PipelineError("Eingabe", "--output darf nicht dieselbe Datei wie --input sein", exit_code=2)
        if args.report.resolve() in {args.input.resolve(), args.output.resolve()}:
            raise PipelineError("Eingabe", "--report muss eine separate Datei sein", exit_code=2)
        if args.report.resolve() == metadata_path.resolve():
            raise PipelineError(
                "Eingabe",
                "--report darf nicht der automatisch erzeugten PCM-Metadatendatei entsprechen",
                exit_code=2,
            )

        input_audio = prepare_input_audio(args, clock)
        transcript = stream_asr(
            url=args.asr_url,
            input_audio=input_audio,
            chunk_ms=args.asr_chunk_ms,
            realtime=args.realtime_input,
            clock=clock,
            console=console,
            stats=asr_stats,
        )

        tts_thread = threading.Thread(
            target=tts_worker,
            name=f"kienzlefon-{args.tts}-worker",
            daemon=True,
            kwargs={
                "args": args,
                "output_path": args.output,
                "sections": sections,
                "clock": clock,
                "stats": tts_stats,
                "player_stats": player_stats,
                "worker_error": worker_error,
                "run_id": run_id,
            },
        )
        tts_thread.start()

        llm_stats = stream_llm(
            url=args.llm_url,
            transcript=transcript,
            system_prompt=args.system_prompt,
            max_tokens=args.max_tokens,
            temperature=args.temperature,
            clock=clock,
            console=console,
            tts_queue=sections,
            worker_error=worker_error,
        )
        sections.put(None)
        tts_thread.join()
        tts_thread = None

        thread_failure = worker_error.get()
        if thread_failure is not None:
            raise thread_failure
        if tts_stats.section_count == 0 or tts_stats.output_bytes == 0:
            raise PipelineError(tts_service_name(args.tts), "Es wurde keine Audioausgabe erzeugt", exit_code=5)

    except PipelineError as exc:
        pipeline_error = exc
    except KeyboardInterrupt:
        pipeline_error = PipelineError("Programm", "Durch Benutzer abgebrochen", category="interrupted", exit_code=130)
    except Exception as exc:
        pipeline_error = PipelineError("Programm", f"Unerwarteter Fehler: {exc}", exit_code=1)
    finally:
        if tts_thread is not None:
            with contextlib.suppress(Exception):
                sections.put_nowait(None)
            tts_thread.join()

    if pipeline_error is not None:
        actual_output_path = (
            finalize_failed_output(
                args.output,
                output_complete=tts_stats.output_complete,
            )
            if tts_stats.output_opened
            else None
        )
        console.error(
            f"[FEHLER] {pipeline_error.service} ({pipeline_error.category}): {pipeline_error}"
        )
        status = "error"
    else:
        status = "ok"

    metadata = build_pcm_metadata(
        status=(
            "partial"
            if pipeline_error and actual_output_path and not tts_stats.output_complete
            else status
        ),
        tts_stats=tts_stats,
        run_id=run_id,
        output_path=actual_output_path,
    )
    report = build_report(
        status=status,
        args=args,
        input_audio=input_audio,
        asr_stats=asr_stats,
        clock=clock,
        llm_stats=llm_stats,
        tts_stats=tts_stats,
        player_stats=player_stats,
        run_id=run_id,
        started_at_utc=started_at_utc,
        error=pipeline_error,
        metadata_path=metadata_path,
        actual_output_path=actual_output_path,
    )

    try:
        write_json_atomic(metadata_path, metadata)
        write_json_atomic(args.report, report)
    except PipelineError as json_error:
        console.error(f"[FEHLER] {json_error.service}: {json_error}")
        if pipeline_error is None:
            pipeline_error = json_error

    print_benchmark_summary(console, report, clock)
    return pipeline_error.exit_code if pipeline_error is not None else 0


def main(argv: list[str] | None = None) -> NoReturn:
    try:
        args = parse_args(argv)
        exit_code = run(args)
    except argparse.ArgumentTypeError as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        exit_code = 2
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
