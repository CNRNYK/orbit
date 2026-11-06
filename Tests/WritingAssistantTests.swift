import Foundation

@MainActor enum WritingAssistantTests {
    static func run() async {
        precondition(!WritingEngine.valid(" \n"))
        precondition(!WritingEngine.valid(String(repeating:"🙂",count:1001)))
        precondition(WritingEngine.valid("Türkçe metin"))
        let corrected = WritingEngine.proofread("This is a sentnce.",language:"en")
        precondition(corrected == "This is a sentence.")
        precondition(WritingEngine.proofread("This is a sentnce.",language:"en",dictionary:["sentnce"]) == "This is a sentnce.")
        let review = WritingReview(original:"Merhaba, canr! 🙂",revised:"Merhaba Caner! 🙂")
        precondition(review.render(accepting:[]) == "Merhaba, canr! 🙂")
        precondition(review.render(accepting:Set(review.changes.map(\.id))) == "Merhaba Caner! 🙂")
        let partial = WritingReview(original:"A bad sentence. Another typo!",revised:"A good sentence. Another fix!")
        precondition(partial.changes.count == 2)
        precondition(partial.render(accepting:[partial.changes[0].id]) == "A good sentence. Another typo!")
        for (original,revised) in [("", "new"), ("old", ""), ("👩🏽‍💻 A", "👩🏽‍💻 B"), ("cafe\u{301}", "café"), ("A\r\nB", "A\nB")] {
            let diff = WritingReview(original:original,revised:revised)
            precondition(diff.render(accepting:[]).utf8.elementsEqual(original.utf8))
            precondition(diff.render(accepting:Set(diff.changes.map(\.id))).utf8.elementsEqual(revised.utf8))
        }
        precondition(WritingLanguage.detect("Hi") == nil)
        precondition(WritingLanguage.detect("This is an example of a sentence written in English.") == "en")
        precondition(WritingLanguage.detect("Bugün arkadaşlarımla birlikte güzel bir kahvaltı yapmak için dışarı çıktım.") == "tr")
        precondition(!WritingTask.tone.canReplace && !WritingTask.draft.canReplace)
        let display = CGRect(x:-1200,y:120,width:1200,height:800)
        let panel = CGSize(width:740,height:600)
        precondition(WritingPanelPlacement.origin(size:panel,near:CGRect(x:-200,y:860,width:50,height:20),within:display) == CGPoint(x:-740,y:248))
        precondition(WritingPanelPlacement.origin(size:panel,near:CGRect(x:-1150,y:130,width:50,height:20),within:display) == CGPoint(x:-1150,y:162))
        precondition(WritingPanelPlacement.badge(near:CGRect(x:-100,y:800,width:95,height:20),within:display) == CGPoint(x:-132,y:797))
        precondition(WritingPanelPlacement.badge(near:display,within:display) == nil)
        let sample = "🙂 This is a sentnce."
        let corrections = WritingEngine.spellingCorrections(sample,language:"en")
        precondition(corrections.contains { (sample as NSString).substring(with:$0.0) == "sentnce" && $0.1 == "sentence" })
        let state = WritingAssistantState()
        state.input = "Original"
        state.output = "Suggestion"
        precondition(!state.canReplace, "Pasted text must never target another app.")
        state.input = "Changed"
        precondition(state.output.isEmpty)
        state.output = "Suggestion"
        state.task = .friendly
        precondition(state.output.isEmpty)
        state.load(nil)
        precondition(state.input.isEmpty && state.output.isEmpty)
        precondition(CaptureShortcutRoute.resolve(.writing,phase:.idle,blocked:false,dispatching:false,screenshotMode:"Window",recordingMode:"Window") == .writing)
        precondition(CaptureShortcutRoute.resolve(.writing,phase:.recording,blocked:true,dispatching:false,screenshotMode:"Window",recordingMode:"Window") == .ignore)
        print("PASS: writing input limits, offline spelling, stale suggestions, paste-only isolation and shortcut guards")
    }
}
