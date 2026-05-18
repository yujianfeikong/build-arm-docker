#!/usr/bin/env sh
set -eu

if [ -n "${START_COMMAND:-}" ]; then
  exec sh -lc "${START_COMMAND}"
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

echo "No START_COMMAND or container command provided." >&2
exit 1
