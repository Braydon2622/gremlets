#!/bin/bash
# Runs the web engine and bonsai/island tests with macOS's built-in JavaScriptCore shell (no Node required).
set -euo pipefail
cd "$(dirname "$0")/.."
JSC=/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc
"$JSC" -m web/tests/engine.test.mjs
"$JSC" -m web/tests/bonsai.test.mjs
