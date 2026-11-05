#!/bin/bash
# Fetches pinned, audited dependencies (OpenZeppelin Contracts 5.1.0, forge-std 1.9.6) and checks their hashes.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dependencies && cd dependencies
fetch() { # url sha256 dir
  [ -d "$3" ] && return
  curl -sSfL "$1" -o pkg.tgz
  echo "$2  pkg.tgz" | shasum -a 256 -c -
  tar xzf pkg.tgz && rm pkg.tgz
}
fetch https://github.com/OpenZeppelin/openzeppelin-contracts/archive/refs/tags/v5.1.0.tar.gz \
  8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686 openzeppelin-contracts-5.1.0
fetch https://github.com/foundry-rs/forge-std/archive/refs/tags/v1.9.6.tar.gz \
  53d2b498183cb7dc62cf726cc6c1a222ad728b0d87976a877ca1f3ed3707b1c6 forge-std-1.9.6
echo "dependencies ready"
