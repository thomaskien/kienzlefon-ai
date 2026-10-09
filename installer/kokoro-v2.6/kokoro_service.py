#!/usr/bin/env python3
"""Resident German Kokoro service, PCM sentence streaming, bounded concurrency.

API 1.0.0. No request text, phonemes, patient information or response bodies
are logged. Model weights must be present locally before startup.
"""
from __future__ import annotations

import argparse
import contextlib
from dataclasses import dataclass
import json
import logging
import math
import os
from pathlib import Path
import re
import select
import signal
import socket
import threading
import time
import tomllib
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = "1.0.0"
MODEL_REVISION = "734e593d320a3d876bede7020f773dfd481a0cc7"
LOG = logging.getLogger("kienzlefon-kokoro")


def selected_gpu_handle(torch, nvml):
    """Resolve the same physical GPU for Torch and the VRAM guard.

    Installer 2.6 supplies a stable UUID in CUDA_VISIBLE_DEVICES. The old
    single-GPU service remains compatible; ambiguous multi-GPU starts fail.
    """
    visible = os.environ.get("CUDA_VISIBLE_DEVICES", "").strip()
    if torch.cuda.device_count() != 1:
        raise ServiceError("exactly_one_selected_cuda_gpu_required")
    if re.fullmatch(r"GPU-[A-Za-z0-9-]+", visible):
        return nvml.nvmlDeviceGetHandleByUUID(visible)
    if not visible and nvml.nvmlDeviceGetCount() == 1:
        return nvml.nvmlDeviceGetHandleByIndex(0)
    raise ServiceError("stable_cuda_gpu_uuid_required")


class ServiceError(RuntimeError):
    pass


@dataclass(frozen=True)
class Config:
    model_dir: Path
    device: str = "cuda"
    host: str = "127.0.0.1"
    port: int = 8184
    threads: int = 4
    max_concurrent: int = 3
    voice: str = "thorsten"
    speed: float = 1.0
    model_revision: str = MODEL_REVISION
    socket_timeout_seconds: float = 20.0

    @classmethod
    def load(cls, path):
        raw = tomllib.loads(Path(path).read_text())
        c = raw.get("kokoro", {})
        if not isinstance(c, dict):
            raise ServiceError("invalid_kokoro_section")
        valid = set(cls.__dataclass_fields__)
        if set(c)-valid:
            raise ServiceError("unknown_kokoro_option")
        cfg = cls(**dict(c, model_dir=Path(c.get("model_dir", "/opt/kienzlefon-ai/models/kokoro-thorsten"))))
        if cfg.device not in {"cpu", "cuda"} or cfg.voice != "thorsten":
            raise ServiceError("invalid_device_or_voice")
        if cfg.host not in {"127.0.0.1", "::1"}:
            raise ServiceError("bind_must_be_loopback")
        for value, low, high in [(cfg.port,1024,65535),(cfg.threads,1,12),(cfg.max_concurrent,1,4)]:
            if type(value) is not int or not low <= value <= high:
                raise ServiceError("invalid_integer_option")
        if cfg.device=="cpu" and cfg.threads*cfg.max_concurrent>12:
            raise ServiceError("cpu_thread_budget_exceeded")
        for value, low, high in [(cfg.speed,0.5,2.0),(cfg.socket_timeout_seconds,1,120)]:
            if type(value) not in (int,float) or not math.isfinite(value) or not low<=value<=high:
                raise ServiceError("invalid_numeric_option")
        if cfg.model_revision != MODEL_REVISION:
            raise ServiceError("unsupported_model_revision")
        if not cfg.model_dir.is_absolute():
            raise ServiceError("model_dir_must_be_absolute")
        return cfg


def split_text(text, max_chars=240):
    """Split sentences, then long sentences on whitespace without losing words."""
    if not isinstance(text,str) or not text.strip() or len(text)>1000:
        raise ServiceError("invalid_input")
    if any(ord(ch)<32 and ch not in "\n\r\t" for ch in text):
        raise ServiceError("invalid_input")
    phrases=[]
    for sentence in re.split(r"(?<=[.!?])\s+|[\r\n]+",text.strip()):
        current=[]
        for word in sentence.split():
            if len(word)>max_chars:
                raise ServiceError("input_token_too_long")
            if current and len(" ".join(current))+1+len(word)>max_chars:
                phrases.append(" ".join(current))
                current=[]
            current.append(word)
        if current:
            phrases.append(" ".join(current))
    if not phrases:
        raise ServiceError("invalid_input")
    return phrases


class KokoroEngine:
    def __init__(self,cfg):
        import os
        for name in ("OMP_NUM_THREADS","MKL_NUM_THREADS","OPENBLAS_NUM_THREADS"):
            os.environ[name]=str(cfg.threads)
        os.environ["HF_HUB_OFFLINE"]="1"
        os.environ["TOKENIZERS_PARALLELISM"]="false"
        cache=os.environ.get("PYTORCH_KERNEL_CACHE_PATH")
        if cache:
            Path(cache).mkdir(parents=True,exist_ok=True)
        start=time.monotonic()
        import numpy as np
        import torch
        from loguru import logger
        logger.disable("kokoro")
        logger.disable("misaki")
        logging.getLogger("phonemizer").setLevel(logging.CRITICAL)
        from kokoro import KModel, KPipeline
        self.cfg,self.np,self.torch=cfg,np,torch
        torch.set_num_threads(cfg.threads)
        torch.set_num_interop_threads(1)
        torch.manual_seed(1234)
        self.g2p_lock=threading.Lock()
        for file in ("config.json","model.pth","voices/thorsten.pt"):
            if not (cfg.model_dir/file).is_file():
                raise ServiceError("local_model_missing")
        if cfg.device=="cuda":
            if not torch.cuda.is_available():
                raise ServiceError("cuda_unavailable")
            import pynvml
            pynvml.nvmlInit()
            mem=pynvml.nvmlDeviceGetMemoryInfo(selected_gpu_handle(torch, pynvml))
            budget=mem.free-640*1024**2
            if budget<768*1024**2:
                raise ServiceError("insufficient_cuda_reserve")
            torch.cuda.set_per_process_memory_fraction(budget/mem.total,0)
            torch.backends.cudnn.benchmark=False
        self.model=KModel(repo_id="hexgrad/Kokoro-82M",config=str(cfg.model_dir/"config.json"),
                          model=str(cfg.model_dir/"model.pth")).to(cfg.device).eval()
        self.pipeline=KPipeline(lang_code="d",repo_id="hexgrad/Kokoro-82M",model=self.model)
        original=self.pipeline.g2p
        def g2p(text):
            with self.g2p_lock:
                ps,tokens=original(text)
            ps=ps.replace("ʏ","y")
            if len(ps)>510:
                raise ServiceError("phonemes_too_long")
            return ps,tokens
        self.pipeline.g2p=g2p
        self.voice=torch.load(cfg.model_dir/"voices/thorsten.pt",map_location="cpu",weights_only=True)
        self.load_s=time.monotonic()-start
        warm=time.monotonic()
        for _ in self.chunks(["Guten Morgen.","Einen kleinen Moment bitte."]):
            pass
        self.warmup_s=time.monotonic()-warm

    def chunks(self,phrases):
        with self.torch.inference_mode():
            for phrase in phrases:
                for result in self.pipeline(phrase,voice=self.voice,speed=self.cfg.speed,split_pattern=None):
                    audio=result.audio.detach().cpu().numpy()
                    pcm=self.np.clip(audio*32767,-32768,32767).astype("<i2").tobytes()
                    if pcm:
                        yield pcm


class Server(ThreadingHTTPServer):
    daemon_threads=True
    allow_reuse_address=True
    def __init__(self,cfg,engine):
        if cfg.host=="::1":
            self.address_family=socket.AF_INET6
        self.cfg,self.engine=cfg,engine
        self.capacity=threading.BoundedSemaphore(cfg.max_concurrent)
        self.lock=threading.Lock()
        self.stopping=threading.Event()
        self.instance_id=str(uuid.uuid4())
        self.started=time.monotonic()
        self.counters={"active":0,"peak_active":0,"accepted":0,"completed":0,"cancelled":0,"failed":0,"overload":0}
        super().__init__((cfg.host,cfg.port),Handler)

    def snapshot(self):
        with self.lock:
            counters=dict(self.counters)
        return dict(status="ok",engine="kokoro",version=VERSION,model_loaded=True,
                    model_instances=1,instance_id=self.instance_id,device=self.cfg.device,
                    voice=self.cfg.voice,model_revision=self.cfg.model_revision,sample_rate=24000,
                    max_concurrent=self.cfg.max_concurrent,threads=self.cfg.threads,
                    load_seconds=self.engine.load_s,warmup_seconds=self.engine.warmup_s,
                    uptime_seconds=time.monotonic()-self.started,**counters)


class Handler(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def setup(self):
        super().setup()
        self.connection.settimeout(self.server.cfg.socket_timeout_seconds)
        self.connection.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
    def log_message(self,*args):
        pass
    def json(self,status,payload):
        body=json.dumps(payload,separators=(",",":")).encode()
        self.send_response(status)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(body)))
        self.send_header("Connection","close")
        self.end_headers()
        self.close_connection=True
        self.wfile.write(body)
    def do_GET(self):
        self.json(200,self.server.snapshot()) if self.path in {"/health","/v1/health"} else self.json(404,{"error":"not_found"})
    def disconnected(self):
        if self.server.stopping.is_set():
            return True
        try:
            readable,_,_=select.select([self.connection],[],[],0)
            return bool(readable) and self.connection.recv(1,socket.MSG_PEEK)==b""
        except OSError:
            return True
    def do_POST(self):
        if self.path!="/v1/tts/stream":
            self.json(404,{"error":"not_found"})
            return
        try:
            if self.headers.get("Transfer-Encoding"):
                raise ServiceError("chunked_request_not_supported")
            length=int(self.headers.get("Content-Length","0"))
            if not 0<length<=65536:
                raise ServiceError("invalid_content_length")
            body=self.rfile.read(length)
            if len(body)!=length:
                raise ServiceError("incomplete_request")
            payload=json.loads(body)
            if not isinstance(payload,dict):
                raise ServiceError("invalid_request")
            if payload.get("voice",self.server.cfg.voice)!=self.server.cfg.voice:
                raise ServiceError("unsupported_voice")
            if "speed" in payload and payload["speed"]!=self.server.cfg.speed:
                raise ServiceError("speed_does_not_match_config")
            phrases=split_text(payload.get("text",payload.get("input")))
        except (ValueError,UnicodeError,ServiceError,TimeoutError):
            self.json(400,{"error":"invalid_request"})
            return
        if not self.server.capacity.acquire(blocking=False):
            with self.server.lock:
                self.server.counters["overload"]+=1
            self.json(503,{"error":"all_workers_busy"})
            return
        with self.server.lock:
            c=self.server.counters
            c["active"]+=1
            c["accepted"]+=1
            c["peak_active"]=max(c["peak_active"],c["active"])
        start=time.monotonic()
        sent=False
        chunks=0
        outcome="failed"
        iterator=self.server.engine.chunks(phrases)
        try:
            # Hold headers until first actual PCM, so pre-audio errors yield 503.
            while not self.disconnected():
                try:
                    pcm=next(iterator)
                except StopIteration:
                    if sent:
                        self.wfile.write(b"0\r\n\r\n")
                        self.wfile.flush()
                        outcome="completed"
                    break
                if self.disconnected():
                    outcome="cancelled"
                    break
                if not pcm:
                    continue
                if not sent:
                    self.send_response(200)
                    for key,value in [("Content-Type","audio/pcm"),("X-Sample-Rate","24000"),
                                      ("X-Channels","1"),("X-Sample-Format","s16le"),
                                      ("X-TTS-Engine","kokoro"),("Transfer-Encoding","chunked"),
                                      ("Connection","close")]:
                        self.send_header(key,value)
                    self.end_headers()
                    sent=True
                for offset in range(0,len(pcm),8192):
                    if self.disconnected():
                        outcome="cancelled"
                        break
                    piece=pcm[offset:offset+8192]
                    self.wfile.write(f"{len(piece):X}\r\n".encode()+piece+b"\r\n")
                    self.wfile.flush()
                if outcome=="cancelled":
                    break
                chunks+=1
            else:
                outcome="cancelled"
            if not sent and outcome!="cancelled":
                self.json(503,{"error":"synthesis_failed"})
        except (BrokenPipeError,ConnectionResetError,TimeoutError,OSError):
            outcome="cancelled"
        except Exception:
            if not sent:
                with contextlib.suppress(OSError):
                    self.json(503,{"error":"synthesis_failed"})
            # If audio already started, close without final chunk. Clients see
            # an incomplete response and must not repeat already spoken words.
            LOG.error("event=synthesis_failed")
        finally:
            iterator.close()
            self.close_connection=True
            with self.server.lock:
                self.server.counters["active"]-=1
                self.server.counters[outcome]+=1
            self.server.capacity.release()
            LOG.info("event=request_finished outcome=%s chunks=%d elapsed_ms=%d",outcome,chunks,int((time.monotonic()-start)*1000))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--config",required=True,type=Path)
    parser.add_argument("--check-config",action="store_true")
    args=parser.parse_args()
    cfg=Config.load(args.config)
    if args.check_config:
        print("kokoro configuration valid")
        return
    logging.basicConfig(level=logging.INFO,format="%(asctime)s %(levelname)s %(message)s")
    engine=KokoroEngine(cfg)
    server=Server(cfg,engine)
    def stop(*_):
        server.stopping.set()
        threading.Thread(target=server.shutdown,daemon=True).start()
    signal.signal(signal.SIGTERM,stop)
    signal.signal(signal.SIGINT,stop)
    LOG.info("event=service_ready device=%s models=1 max_concurrent=%d load_ms=%d warmup_ms=%d",cfg.device,cfg.max_concurrent,int(engine.load_s*1000),int(engine.warmup_s*1000))
    try:
        server.serve_forever(poll_interval=0.1)
    finally:
        server.stopping.set()
        server.server_close()


if __name__=="__main__":
    main()
