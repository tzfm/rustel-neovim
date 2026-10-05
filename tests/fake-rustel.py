#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import signal
import sys
import time


score = next(Path(arg) for arg in sys.argv[1:] if arg.endswith((".strudel", ".rustel")))
log = Path(os.environ["RUSTEL_TEST_LOG"])
running = True
tail_seconds = float(os.environ.get("RUSTEL_TEST_TAIL_SECONDS", "0"))
ignore_stop = os.environ.get("RUSTEL_TEST_IGNORE_STOP") == "1"
interrupts = 0
exit_code = 0


def record(message):
    with log.open("a") as file:
        file.write(f"{message}\n")


def emit(stream, message, notice=None):
    records = [(stream, message)]
    if notice is not None:
        records.append((sys.stderr, notice))
    records = [(target, json.dumps(record, separators=(",", ":")) + "\n")
               for target, record in records]
    for start, end in ((0, 7), (7, 31), (31, None)):
        for target, data in records:
            target.write(data[start:end])
            target.flush()
            time.sleep(0.002)


def stop(signum, _frame):
    global running, interrupts, exit_code
    if ignore_stop:
        record(f"IGNORED {os.getpid()}")
        return
    running = False
    if tail_seconds:
        interrupts += 1
        record(f"{'SOFT' if interrupts == 1 else 'SIGNAL'} {os.getpid()}")
        exit_code = 128 + signum


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
for argument in sys.argv[1:]:
    record(f"ARG {argument}")
record(f"START {os.getpid()}")
started = time.monotonic()
previous = None
revision = None
generation = 0
onset_id = 0


def batch(now, events, source_revision=None, notice=None):
    emit(sys.stdout, {"ui_events": {
        "version": 2, "device_time": now, "cycle": now, "cps": 1,
        "generation": generation, "source_revision": source_revision or revision,
        "events": events, "dropped": 0,
    }}, notice)


try:
    while running:
        source = score.read_bytes()
        now = time.monotonic() - started
        if source != previous:
            previous = source
            if b"BAD" in source:
                emit(sys.stderr, {"reload": {"target": "score", "status": "rejected", "message": "bad score"}})
                emit(sys.stderr, {"reload": {"target": "prebake", "status": "installed"}})
                record("REJECT")
            else:
                generation += 1
                revision = hashlib.sha256(source).hexdigest()
                spans = []
                for token in ("é".encode(), b"c4"):
                    offset = source.rfind(token)
                    if offset >= 0:
                        spans.append([offset, offset + len(token)])
                emit(sys.stdout, {"ui_layout": {
                    "version": 2, "generation": generation, "source_revision": revision,
                    "visuals": [{
                        "kind": "pianoroll", "inline": True, "slot": 0,
                        "from": max(0, source.find(b"note(")), "to": len(source.rstrip(b"\n")),
                        "options": "",
                    }], "sliders": [], "mini_locations": spans,
                }})
                onset_id += 1
                event = {
                    "onset_id": onset_id, "generation": generation,
                    "whole_begin": "0/1", "whole_end": "10/1",
                    "part_begin": "0/1", "part_end": "10/1",
                    "target_time": now, "duration_seconds": 10,
                    "frequency_hz": 261.63, "value": "c4", "context": spans, "ui_visuals": 1,
                }
                batch(now, [event], "0" * 64)
                onset_id += 1
                event = dict(event, onset_id=onset_id, target_time=now + 0.3)
                batch(now, [event], notice={"reload": {
                    "target": "score", "status": "installed", "generation_after": generation,
                    "source_revision": revision,
                }})
                record(f"ACCEPT {generation}")
        if revision:
            batch(time.monotonic() - started, [])
        time.sleep(0.035)
    if tail_seconds and interrupts:
        time.sleep(0.15)
        baseline = interrupts
        deadline = time.monotonic() + tail_seconds
        record(f"ACK {os.getpid()}")
        emit(sys.stderr, {"stopping": {"message": "letting the tail ring out"}})
        while time.monotonic() < deadline and interrupts == baseline:
            time.sleep(0.01)
        if interrupts > baseline:
            record(f"CUT {os.getpid()}")
finally:
    record(f"STOP {os.getpid()}")
sys.exit(exit_code)
