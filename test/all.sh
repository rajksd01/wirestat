#!/bin/sh
# Run the whole suite: renderer unit tests, then shell integration tests.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sh "$ROOT/test/run.sh"
echo
sh "$ROOT/test/shell_test.sh"
