import Testing
@testable import GremletsCore

@Suite struct PresenceTests {
    @Test func hidesDuringCallsAndWaitsOutMicBlips() {
        var p = PresenceTracker()
        #expect(p.update(PresenceInput(now: 0)).isEmpty)
        #expect(p.update(PresenceInput(now: 1, inCall: true)) == [.hide(.call)])
        #expect(p.update(PresenceInput(now: 2, inCall: true)).isEmpty)
        // Mic drops for a moment: stay hidden through the grace period.
        #expect(p.update(PresenceInput(now: 3, inCall: false)).isEmpty)
        #expect(p.update(PresenceInput(now: 6, inCall: true)).isEmpty)
        #expect(p.update(PresenceInput(now: 7, inCall: false)).isEmpty)
        #expect(p.update(PresenceInput(now: 14, inCall: false)).isEmpty)
        #expect(p.update(PresenceInput(now: 15.1, inCall: false)) == [.show])
        #expect(!p.isHidden)
    }

    @Test func callHidingCanBeTurnedOff() {
        var p = PresenceTracker()
        #expect(p.update(PresenceInput(now: 0, inCall: true, hideDuringCalls: false)).isEmpty)
        #expect(p.update(PresenceInput(now: 1, inCall: true)) == [.hide(.call)])
        // Turning the option off mid-call brings them straight back.
        #expect(p.update(PresenceInput(now: 2, inCall: true, hideDuringCalls: false)) == [.show])
    }

    @Test func manualHideWinsOverCalls() {
        var p = PresenceTracker()
        #expect(p.update(PresenceInput(now: 0, manuallyHidden: true, inCall: true)) == [.hide(.manual)])
        #expect(p.update(PresenceInput(now: 1, manuallyHidden: false, inCall: true)) == [.hide(.call)])
        #expect(p.maxTickRate(PresenceInput(now: 1)) == 2)
    }

    @Test func awayAndWelcomeBack() {
        var p = PresenceTracker()
        #expect(p.update(PresenceInput(now: 0, idleSeconds: 299)).isEmpty)
        #expect(p.update(PresenceInput(now: 1, idleSeconds: 300)) == [.away])
        #expect(p.maxTickRate(PresenceInput(now: 1)) == 12)
        #expect(p.update(PresenceInput(now: 2, idleSeconds: 400)).isEmpty)
        #expect(p.update(PresenceInput(now: 3, idleSeconds: 0.5)) == [.welcomeBack])
        #expect(p.update(PresenceInput(now: 4, idleSeconds: 0.5)).isEmpty)
    }

    @Test func noWelcomeWhileHidden() {
        var p = PresenceTracker()
        _ = p.update(PresenceInput(now: 0, manuallyHidden: true))
        #expect(p.update(PresenceInput(now: 1, manuallyHidden: true, idleSeconds: 600)).isEmpty)
        #expect(p.update(PresenceInput(now: 2, manuallyHidden: true, idleSeconds: 0)).isEmpty)
    }

    @Test func lowPowerCapsTheLoop() {
        let p = PresenceTracker()
        #expect(p.maxTickRate(PresenceInput(now: 0, lowPower: true)) == 30)
        #expect(p.maxTickRate(PresenceInput(now: 0)) == nil)
    }

    private func prev(_ d: String) -> String {
        // Test calendar: days are "d<N>".
        "d\(Int(d.dropFirst())! - 1)"
    }

    @Test func focusLogTotalsAndStreak() {
        var log = FocusLog()
        log.record(minutes: 25, day: "d8")
        log.record(minutes: 25, day: "d9")
        log.record(minutes: 50, day: "d10")
        log.record(minutes: 25, day: "d10")
        log.record(minutes: 0, day: "d10")        // ignored
        #expect(log.minutes(on: "d10") == 75)
        #expect(log.sessions == 4)
        #expect(log.streak(today: "d10", previousDay: prev) == 3)
        #expect(log.streak(today: "d11", previousDay: prev) == 3)   // not broken until today ends
        #expect(log.streak(today: "d12", previousDay: prev) == 0)
    }

    @Test func focusTogetherGrowsTheBond() {
        #expect(Bond(focusSessions: 4).level == 1)
        #expect(Bond(focusSessions: 4).score > Bond(pets: 4).score)
    }

    @Test func siriListeningIsNotACall() {
        #expect(CallDetection.isBackgroundListener(path: "/System/Library/PrivateFrameworks/CoreSpeech.framework/corespeechd"))
        #expect(CallDetection.isBackgroundListener(path: "/usr/libexec/someaudiod"))
        #expect(!CallDetection.isBackgroundListener(path: "/System/Applications/FaceTime.app/Contents/MacOS/FaceTime"))
        #expect(!CallDetection.isBackgroundListener(path: "/Applications/zoom.us.app/Contents/MacOS/zoom.us"))
        #expect(!CallDetection.isBackgroundListener(path: ""))   // unknown process: assume it's a call
    }
}
