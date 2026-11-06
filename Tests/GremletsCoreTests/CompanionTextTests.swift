import Testing
@testable import GremletsCore

@Suite struct CompanionTextTests {
    @Test func actionTagsAreSplitOffAndChecked() {
        #expect(CompanionText.parseAction("Let's do it! <do>focus</do>") == ("Let's do it!", "focus"))
        #expect(CompanionText.parseAction("Okay <do> Dance </do>").action == "dance")
        #expect(CompanionText.parseAction("Sure <do>delete_files</do>") == ("Sure", nil))     // only known actions
        #expect(CompanionText.parseAction("  Just talking.  ") == ("Just talking.", nil))
    }

    @Test func builtInIntents() {
        #expect(CompanionText.intent("can you help me focus?") == "focus")
        #expect(CompanionText.intent("I have a meeting, hide please") == "hide")
        #expect(CompanionText.intent("how was my day") == "recap")
        #expect(CompanionText.intent("hi") == "hello")
        #expect(CompanionText.intent("this is chill") == nil)     // "chill" contains "hi" but isn't a greeting
        #expect(CompanionText.intent("I'm so stressed") == "sad")
    }
}
