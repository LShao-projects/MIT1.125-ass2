#!/bin/bash
# Generate recommendations from the history perspective.
exec bash "$(dirname "$0")/codex_recommend.sh" history "${1-}"
