#!/bin/bash
set -euo pipefail
exec /usr/bin/env python3 "$(cd -- "$(dirname -- "$0")" && pwd)/build.py" "$@"
