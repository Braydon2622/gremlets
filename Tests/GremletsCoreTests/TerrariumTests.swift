import Foundation
import CryptoKit
import Testing
@testable import GremletsCore

/// The Terrarium's status note and note sealing (TerrariumNote.swift; the browser side is web/js/seal.js).
@Suite struct TerrariumTests {
    @Test func theBoardTracksSessionsAndHidesNamesUnlessAsked() throws {
        let b = TerrariumBoard()
        #expect(b.record(session: "abc", project: "Gremlets", state: .thinking, at: 100))
        #expect(!b.record(session: "abc", project: "Gremlets", state: .thinking, at: 101), "no change")
        b.record(session: "xyz", project: "PhotoToPart", state: .waiting, at: 102)
        b.record(session: "abc", project: "Gremlets", state: .done, at: 103)
        let hidden = b.snapshot(showNames: false)
        #expect(hidden.sessions.map(\.project) == ["Project 1", "Project 2"])
        #expect(hidden.sessions.map(\.state) == [.done, .waiting])
        #expect(!hidden.sessions.contains { $0.id == "abc" || $0.id == "xyz" }, "Claude's own session ids stay on the Mac")
        #expect(b.snapshot(showNames: true).sessions.map(\.project) == ["Gremlets", "PhotoToPart"])
        for i in 0..<8 { b.record(session: "q\(i)", project: "P\(i)", state: .thinking, at: 200 + Double(i)) }
        #expect(b.snapshot(showNames: true).recent.count == 5 && b.snapshot(showNames: true).recent.last?.project == "P7")
        #expect(b.prune(now: 103 + TerrariumBoard.doneLinger + 1))
        #expect(!b.snapshot(showNames: true).sessions.contains { $0.project == "Gremlets" })
        b.record(session: "xyz", project: "PhotoToPart", state: nil, at: 300)
        #expect(!b.snapshot(showNames: true).sessions.contains { $0.project == "PhotoToPart" })
    }

    @Test func theStatusNoteRoundTrips() throws {
        let s = TerrariumStatus(sessions: [.init(id: "s1", project: "Project 1", state: .waiting)], recent: [.init(project: "Project 1", state: .waiting, at: 1_700_000_000.5)])
        let data = try JSONSerialization.data(withJSONObject: s.json())
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let back = try #require(TerrariumStatus(json: obj))
        #expect(back == s)
        #expect(TerrariumStatus(json: ["type": "walk"]) == nil)
    }

    @Test func sealedNotesOpenOnlyWithTheRightKeyAndRoom() throws {
        let key = NoteSeal.key(secret: "pairing-secret", room: "room1234")
        let note = Data(#"{"type":"status"}"#.utf8)
        let sealed = try NoteSeal.seal(note, key: key, room: "room1234")
        #expect(!sealed.contains("status"), "nothing readable on the relay")
        #expect(NoteSeal.open(sealed, key: key, room: "room1234") == note)
        #expect(NoteSeal.open(sealed, key: NoteSeal.key(secret: "other", room: "room1234"), room: "room1234") == nil)
        #expect(NoteSeal.open(sealed, key: key, room: "another") == nil, "bound to its room")
        #expect(NoteSeal.open(#"{"v":1,"type":"walk"}"#, key: key, room: "room1234") == nil)
        #expect(NoteSeal.newSecret() != NoteSeal.newSecret())
    }

    /// The same vector web/tests/terrarium.spec.py checks in the browser, so the Mac and WebCrypto agree.
    @Test func matchesTheBrowserVector() throws {
        let key = NoteSeal.key(secret: "testsecret123", room: "abcdefgh1234")
        let nonce = try AES.GCM.Nonce(data: Data(0..<12))
        let sealed = try NoteSeal.seal(Data(#"{"type":"status"}"#.utf8), key: key, room: "abcdefgh1234", nonce: nonce)
        #expect(sealed == TerrariumTests.vector, "\(sealed)")
    }
    static let vector = #"{"c":"NyCt06mnt07Px1XuJui3cYzyyKYkKpwfWg921+7zsHKC","n":"AAECAwQFBgcICQoL","v":2}"#
}
