#!/bin/sh
set -eu

# Default to 45 min (2,700 s) if not overridden
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-2700}"

echo "Running main.py with a ${TIMEOUT_SECONDS}s timeout"
# Use the python interpreter and packages from the virtual environment directly (without poetry run)
timeout --foreground "${TIMEOUT_SECONDS}s" .venv/bin/python3 main.py
STATUS=$?

# Direct to stderr if the process was killed by timeout
if [ "$STATUS" -eq 124 ]; then
    echo "[ERROR] Python process timed out after ${TIMEOUT_SECONDS} seconds" >&2
# Otherwise, propagate the exit code from the Python process
elif [ "$STATUS" -ne 0 ]; then
    echo "[ERROR] Python exited with status ${STATUS}" >&2
fi

exit "$STATUS"
