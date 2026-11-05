# Gremlets NFTs (testnet)

50 one-of-a-kind collectibles. Owning Gremlet #N unlocks that Gremlet in the Gremlets desktop app; anyone can
visit all 50 in the free web habitat.

| Path | What |
|---|---|
| `tokens.json` | token id → species (roster order, 1 = Flurrie) |
| `metadata/<id>.json` | ERC-721 metadata: name, description, portrait, live habitat preview (`animation_url`), traits |
| `images/<id>.png` | 512×512 portraits |
| `console.html` | creator console: deploy / mint / update / freeze from your own browser wallet |
| `contract/Gremlets.json` | compiled ABI + bytecode used by the console (`scripts/export-contract.sh`) |
| `build_metadata.py` | regenerates metadata + images: `python3 nft/build_metadata.py --base <hosting URL>` |

## Testnet walkthrough (no real money)

1. **Create a wallet** (Coinbase Wallet or MetaMask browser extension). Write the seed phrase on paper and
   keep it offline. **Never type it into a website or share it with anyone, including an AI assistant.**
2. **Get free test ETH** on *Base Sepolia* from a faucet (Coinbase Wallet has one built in; the Base docs list others).
3. **Host the files** (step not done yet): the `nft/` and `web/` folders need a public URL (e.g. GitHub Pages, free).
   Then run `python3 nft/build_metadata.py --base https://<your-host>` so metadata points there.
4. **Serve the console locally:** `python3 -m http.server 8765` from the repo root, open
   `http://localhost:8765/nft/console.html`, connect your wallet and switch to Base Sepolia.
5. **Deploy** with base URL `https://<your-host>/nft/metadata/`, then **Mint** ids 1–50 to yourself.
6. Check the collection on a testnet marketplace/explorer (e.g. `sepolia.basescan.org`).
7. Only after everything looks right *and* you decide to launch for real does mainnet come into play.
   The console is testnet-only by design.

**Freezing** metadata is permanent. Do it only once images and metadata are final and hosted somewhere durable.
