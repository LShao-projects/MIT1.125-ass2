#!/bin/bash
# Generate recommendations from the discovery perspective.
exec bash "$(dirname "$0")/codex_recommend.sh" discovery "${1-}"
