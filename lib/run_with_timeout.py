#!/usr/bin/env python3
"""Run a command in its own process group; bound time and clean up descendants."""
import os
import signal
import subprocess
import sys

seconds = float(sys.argv[1])
if seconds <= 0:
    sys.exit('Timeout must be positive.')
child = subprocess.Popen(sys.argv[2:], start_new_session=True)

def stop_group():
    try:
        os.killpg(child.pid, signal.SIGTERM)
        child.wait(timeout=1)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        pass
    finally:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()

def interrupted(signum, _frame):
    stop_group()
    sys.exit(128 + signum)

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
try:
    result = child.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print('AI request timed out. Try again later.', file=sys.stderr)
    result = 124
finally:
    stop_group()
sys.exit(result if result >= 0 else 128 - result)
