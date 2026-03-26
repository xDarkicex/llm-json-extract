#!/usr/bin/env sh
set -eu

# Example pipeline usage with conservative safety flags.
cat "$1" | perl ./llm-json-extract.pl \
  --meta \
  --fallback-empty \
  --max-size 10M \
  --max-candidate 2M \
  --max-repair-size 1M \
  --timeout 2
