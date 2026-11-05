import Testing
@testable import GremletsCore

/// Reference values come from Foundry `cast` (keccak, hash-message, sig, to-check-sum-address, wallet sign with
/// Anvil's public test account #0, 0xf39F…2266).
@Suite struct OwnershipTests {
    @Test func keccakVectors() {
        #expect(Hex.encode(Keccak.hash256("")) == "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        #expect(Hex.encode(Keccak.hash256("abc")) == "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        // The proof message is longer than one 136-byte block, so this also covers multi-block absorption.
        #expect(Hex.encode(Ethereum.personalMessageHash(Ethereum.proofMessage(nonce: "test-nonce-1")))
                == "0x714af2c05920a708a2e8c581ac8fe346d73df67d418ab014418b86c6d3d9c447")
    }

    @Test func messageHashAndCalldata() {
        #expect(Hex.encode(Ethereum.personalMessageHash("hello")) == "0x50b2c43fd39106bafbba0da34fc430e1f91e3c96ea2acee2bc34119f92b37750")
        #expect(Hex.encode(Ethereum.selector("ownerOf(uint256)")) == "0x6352211e")
        #expect(Ethereum.ownerOfCall(50) == "0x6352211e" + String(repeating: "0", count: 62) + "32")
    }

    @Test func addresses() {
        #expect(Ethereum.checksumAddress("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed") == "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
        #expect(Ethereum.normalizeAddress("0x123") == nil)
        #expect(Ethereum.normalizeAddress("0xzz5aaeb6053f3e94c9b9a09f33669435e7ef1bea") == nil)
        #expect(Ethereum.shortAddress("0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266") == "0xf39F…2266")
        let word = "0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266"
        #expect(Ethereum.addressFromWord(word) == "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266")
        #expect(Ethereum.addressFromWord("0x") == nil)
        #expect(Ethereum.addressFromWord("0x" + String(repeating: "0", count: 64)) == nil)
    }

    @Test func ecrecoverInput() throws {
        let hash = Ethereum.personalMessageHash(Ethereum.proofMessage(nonce: "test-nonce-1"))
        let sig = "0xf44bc3a74ed592ff30ed2fef4a297f4d9a987b6b5b04ec7d3b12f633e453c0d605eccff6cc7b2fff9d9159a3e7fab9f97bd5d2344a7ae10cd167368dc503321c1c"
        let input = try #require(Ethereum.ecrecoverInput(hash: hash, signature: sig))
        #expect(input.count == 2 + 128 * 2)
        #expect(Hex.decode(input)?[63] == 28)               // v = 0x1c in the second word
        // v given as 0/1 is normalised to 27/28.
        #expect(Ethereum.ecrecoverInput(hash: hash, signature: String(sig.dropLast(2)) + "01") == input)
        // Malformed / malleable signatures are rejected before touching the network.
        #expect(Ethereum.ecrecoverInput(hash: hash, signature: "0x1234") == nil)
        #expect(Ethereum.ecrecoverInput(hash: hash, signature: String(sig.dropLast(2)) + "1f") == nil)
        let highS = String(sig.prefix(66)) + "ff" + String(sig.dropFirst(68))
        #expect(Ethereum.ecrecoverInput(hash: hash, signature: highS) == nil)
    }

    @Test func ownedIDs() {
        let me = "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
        let owners: [Int: String?] = [1: me.lowercased(), 2: "0x000000000000000000000000000000000000dead", 3: nil, 7: me]
        #expect(Ownership.ownedIDs(owners, by: me) == [1, 7])
        #expect(Ownership.ownedIDs(owners, by: "nope") == [])
    }

    private let tokens: [Int: String] = [1: "flurrie", 2: "kindlet", 3: "dandelet", 4: "mossfawn", 5: "pomble"]

    @Test func accessKinds() {
        var a = Access(tokens: tokens, gatingEnabled: false)
        #expect(a.kind("kindlet") == .unlocked)
        a.gatingEnabled = true
        a.ownership = Ownership(address: "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", ownedTokenIDs: [2])
        #expect(a.kind("kindlet") == .owned)
        #expect(a.kind("flurrie") == .demo)
        #expect(a.kind("my-own-sprite") == .custom)
    }

    @Test func demoLimitAndSession() {
        var a = Access(tokens: tokens, ownership: Ownership(ownedTokenIDs: [2]),
                       policy: DemoPolicy(maxOut: 2, sessionSeconds: 100, cooldownSeconds: 30), gatingEnabled: true)
        var out = ["kindlet"]                                   // owned: doesn't count toward the demo
        #expect(a.canAdd("flurrie", out: out, now: 0) == .ok)
        out.append("flurrie"); a.noteDemoAdded(now: 0)
        #expect(a.canAdd("dandelet", out: out, now: 1) == .ok)
        out.append("dandelet"); a.noteDemoAdded(now: 1)
        #expect(a.canAdd("mossfawn", out: out, now: 2) == .demoFull(max: 2))
        #expect(a.canAdd("kindlet", out: out, now: 2) == .ok)        // owned: always fine
        #expect(a.canAdd("custom-thing", out: out, now: 2) == .ok)   // custom: always fine
        #expect(a.secondsLeft(now: 40) == 60)                         // clock started at the first demo add

        var fired = a.tick(out: out, now: 99)
        #expect(!fired)
        fired = a.tick(out: out, now: 100)
        #expect(fired)                                                // fires once…
        fired = a.tick(out: out, now: 101)
        #expect(!fired)                                               // …not again
        out = ["kindlet"]
        #expect(a.canAdd("pomble", out: out, now: 110) == .cooldown(secondsLeft: 20))
        #expect(a.canAdd("pomble", out: out, now: 131) == .ok)
    }

    @Test func sessionEndsQuietlyWhenDemosSentHome() {
        var a = Access(tokens: tokens, policy: DemoPolicy(maxOut: 3, sessionSeconds: 100), gatingEnabled: true)
        a.noteDemoAdded(now: 0)
        var fired = a.tick(out: ["flurrie"], now: 10)
        #expect(!fired)
        fired = a.tick(out: [], now: 20)
        #expect(!fired)
        #expect(a.secondsLeft(now: 20) == nil)
        a.noteDemoAdded(now: 50)                                      // a fresh session gets the full clock
        #expect(a.secondsLeft(now: 50) == 100)
    }

    @Test func restoreFilterCapsDemos() {
        let a = Access(tokens: tokens, ownership: Ownership(ownedTokenIDs: [1]), policy: DemoPolicy(maxOut: 2), gatingEnabled: true)
        #expect(a.filterRestore(["flurrie", "kindlet", "dandelet", "mossfawn", "custom", "flurrie"])
                == ["flurrie", "kindlet", "dandelet", "custom", "flurrie"])
    }
}
