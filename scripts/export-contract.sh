#!/bin/bash
# Builds the contract and exports its ABI + bytecode for the creator console (nft/console.html).
set -euo pipefail
cd "$(dirname "$0")/../contracts"
export PATH="$PATH:$HOME/.foundry/bin"
./fetch-deps.sh >/dev/null
forge build --silent
python3 - <<'PY'
import json
a = json.load(open("out/Gremlets.sol/Gremlets.json"))
json.dump({"abi": a["abi"], "bytecode": a["bytecode"]["object"]}, open("../nft/contract/Gremlets.json", "w"))
print("exported nft/contract/Gremlets.json")
PY
