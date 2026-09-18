"""Bounded, dependency-free traffic generator for the Capital Lab services."""
import concurrent.futures
import json
import os
import random
import signal
import threading
import time
import urllib.error
import urllib.request
import uuid
from collections import Counter


def main():
    target = os.getenv("TARGET_URL", "http://localhost:8088").rstrip("/")
    rps = float(os.getenv("LOAD_RPS", "2"))
    workers = int(os.getenv("LOAD_WORKERS", "8"))
    pattern = os.getenv("LOAD_PATTERN", "cycle").lower()
    phase_seconds = int(os.getenv("LOAD_PHASE_SECONDS", "300"))
    duration = int(os.getenv("LOAD_DURATION_SECONDS", "0"))
    phases = ["normal", "peak", "slow", "errors", "recovery"]
    if not (0 < rps <= 50 and 1 <= workers <= 64 and phase_seconds >= 10 and duration >= 0):
        raise SystemExit("Use 0 < LOAD_RPS <= 50, 1 <= LOAD_WORKERS <= 64, phase >= 10s and duration >= 0.")
    if pattern not in phases + ["cycle", "cpu"]:
        raise SystemExit("LOAD_PATTERN must be cycle, normal, peak, slow, errors, recovery or cpu.")

    stop = threading.Event()
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda *_: stop.set())
    slots = threading.BoundedSemaphore(workers)
    lock = threading.Lock()
    counts = Counter()
    started = time.monotonic()

    def request(phase):
        began = time.monotonic()
        try:
            if random.random() < 0.25:
                path = random.choice(["/api/reports/portfolio", "/api/loans/recent"])
                req = urllib.request.Request(target + path)
            else:
                scenario = "NORMAL"
                if phase == "slow":
                    scenario = random.choice(["NORMAL", "SLOW", "SQL_SLOW"])
                elif phase == "errors" and random.random() < 0.25:
                    scenario = "ERROR"
                elif phase == "cpu" or (phase == "peak" and random.random() < 0.20):
                    scenario = "CPU"
                body = dict(requestId=str(uuid.uuid4()), customerId=random.randint(1, 100),
                            amount=random.randrange(100, 30000), termMonths=random.choice([12, 24, 36, 60]),
                            scenario=scenario)
                req = urllib.request.Request(target + "/api/loans/apply", json.dumps(body).encode(),
                                             {"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=20) as response:
                    response.read()
                    status = response.status
            except urllib.error.HTTPError as error:
                error.read()
                status = error.code
            with lock:
                counts[str(status)] += 1
                counts["completed"] += 1
                counts["duration_ms"] += round((time.monotonic() - began) * 1000)
        except (OSError, TimeoutError):
            with lock:
                counts["network_errors"] += 1
        finally:
            slots.release()

    last_phase = None
    next_report = started + 10
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        while not stop.is_set():
            now = time.monotonic()
            if duration and now - started >= duration:
                break
            phase = phases[int((now - started) / phase_seconds) % len(phases)] if pattern == "cycle" else pattern
            if phase != last_phase:
                print(json.dumps({"event": "phase", "phase": phase, "elapsed_seconds": round(now - started)}), flush=True)
                last_phase = phase
            if slots.acquire(blocking=False):
                executor.submit(request, phase)
            else:
                with lock:
                    counts["skipped_at_capacity"] += 1
            if now >= next_report:
                with lock:
                    report = dict(counts)
                report.update(event="traffic", phase=phase, elapsed_seconds=round(now - started))
                print(json.dumps(report), flush=True)
                next_report = now + 10
            stop.wait(1 / (rps * (3 if phase == "peak" else 1)))
    print(json.dumps({"event": "finished", **dict(counts)}), flush=True)


if __name__ == "__main__":
    main()
