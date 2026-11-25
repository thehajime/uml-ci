#!/bin/bash
set -euo pipefail
mkdir -p results
git init -q linux
git -C linux fetch --depth=1 "$UPSTREAM" "$SHA"
git -C linux checkout -q --detach FETCH_HEAD
test "$(git -C linux rev-parse HEAD)" = "$SHA"
