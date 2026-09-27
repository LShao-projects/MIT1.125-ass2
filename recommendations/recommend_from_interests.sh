#!/bin/bash
# Generate recommendations from the interests perspective.
exec bash "$(dirname "$0")/codex_recommend.sh" interests "${1-}"
