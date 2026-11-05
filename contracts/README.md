# Gremlets contract

A minimal ERC-721 for 50 one-of-a-kind Gremlets, built on OpenZeppelin Contracts 5.1.0.
Owning token **#N** unlocks Gremlet **#N** (see `../nft/tokens.json`) in the Gremlets desktop app.

```bash
./fetch-deps.sh       # pinned OpenZeppelin 5.1.0 + forge-std 1.9.6, checksum-verified
forge test            # 18 tests (incl. fuzz)
forge coverage        # 100% lines / statements / branches / functions
```

## What it does

| Function | Who | Notes |
|---|---|---|
| `mint(to, id)` | owner | id must be 1–50; each id can only ever be minted once |
| `mintRange(to, first, last)` | owner | mints a contiguous range in one transaction (all-or-nothing) |
| `setBaseURI(uri)` | owner | moves metadata hosting; emits ERC-4906 `BatchMetadataUpdate` so marketplaces refresh; disabled after freezing |
| `freezeMetadata()` | owner | **permanent**: metadata can never change again |
| `tokenURI(id)` | anyone | `baseURI + id + ".json"` |
| standard ERC-721 | holders | transfers, approvals, marketplace listings |

There is **no payment logic**: tokens are minted to the creator's wallet and listed on existing marketplaces, so
the contract never holds funds (no withdraw function to get wrong).

## What is immutable after deployment

- **Max supply is 50.** `MAX_SUPPLY` is a constant; ids outside 1–50 always revert.
- **Each Gremlet is one-of-a-kind.** An id can be minted once; there is no burn-and-remint.
- **The code.** No proxy, no upgrade path. What's deployed is what runs forever.
- **Name/symbol:** "Gremlets" / "GRMLT".
- **After `freezeMetadata()`:** the base URI, and therefore every token's metadata location, is locked forever.

What the owner *can* still do: mint unminted ids, change the metadata URL (until frozen), and transfer or
renounce contract ownership (OpenZeppelin `Ownable`). The owner can never move or take back tokens someone else holds.

## Deployment policy

Testnet only (**Base Sepolia**, chain id 84532) until the creator explicitly approves a mainnet launch.
Deploys and mints are signed in the creator's own browser wallet via `../nft/console.html`; no private key or
seed phrase is ever stored in this repo, an `.env` file, or a script.
