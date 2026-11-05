#!/usr/bin/env python3
"""Builds ERC-721 metadata for the 50 Gremlets.

Token ids follow the roster order in Species/index.json (1 = first species).
Writes nft/metadata/<id>.json, nft/images/<id>.png and nft/tokens.json (id -> species).

Usage: python3 nft/build_metadata.py --base https://example.github.io/gremlets
  where <base>/nft/images/<id>.png and <base>/web/index.html are publicly hosted.
"""
import argparse, json, os, shutil

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("--base", default="https://REPLACE-WITH-HOSTING-URL", help="public URL where the repo's nft/ and web/ folders are hosted")
args = ap.parse_args()
base = args.base.rstrip("/")

index = json.load(open(os.path.join(root, "Species/index.json")))["species"]
assert len(index) == 50, f"expected 50 species, found {len(index)}"
families = {"animal": "Animal", "insect": "Insect & Bug", "dragon": "Dragon", "dino": "Dinosaur", "mythic": "Mythical Beast", "spirit": "Spirit"}

os.makedirs(os.path.join(root, "nft/metadata"), exist_ok=True)
os.makedirs(os.path.join(root, "nft/images"), exist_ok=True)
tokens = {}
for token_id, entry in enumerate(index, start=1):
    sid = entry["id"]
    info = json.load(open(os.path.join(root, f"Species/{sid}/species.json")))
    shutil.copyfile(os.path.join(root, f"Species/{sid}/portrait.png"), os.path.join(root, f"nft/images/{token_id}.png"))
    meta = {
        "name": f"{info['name']} · Gremlet #{token_id}",
        "description": (f"{info['description']}\n\n"
                        f"One of 50 one-of-a-kind Gremlets. Owning this token unlocks {info['name']} in the Gremlets "
                        f"desktop app, where it walks on your windows, naps, plays with other Gremlets and shows off "
                        f"its signature move."),
        "image": f"{base}/nft/images/{token_id}.png",
        "animation_url": f"{base}/web/index.html?showcase={sid}",
        "external_url": f"{base}/web/index.html?showcase={sid}",
        "attributes": [
            {"trait_type": "Family", "value": families.get(info["family"], info["family"])},
            {"trait_type": "Element", "value": info["element"].title()},
            {"trait_type": "Signature Move", "value": info["special"].title()},
            {"trait_type": "Can Fly", "value": "Yes" if info["flies"] else "No"},
            {"trait_type": "Species", "value": info["name"]},
        ],
    }
    json.dump(meta, open(os.path.join(root, f"nft/metadata/{token_id}.json"), "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    tokens[token_id] = sid

json.dump(tokens, open(os.path.join(root, "nft/tokens.json"), "w"), indent=2)
print(f"wrote metadata for {len(tokens)} tokens (base {base})")
