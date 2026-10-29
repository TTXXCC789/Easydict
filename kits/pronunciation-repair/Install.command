#!/bin/bash
set -euo pipefail
kit_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$kit_dir"
/usr/bin/python3 scripts/kit.py install
printf '\nRead docs/USER-NOTEBOOK.zh-CN.md for the required permission refresh and acceptance check.\n'
