import Foundation
import NaturalLanguage

enum WritingProfile: String, CaseIterable {
    case general = "General", email = "Work email", slack = "Slack message", qa = "QA bug report", release = "Release notes"
    var guidance: String {
        switch self {
        case .general: return ""
        case .email: return "Use clear workplace language."
        case .slack: return "Keep it conversational and suitable for a chat message."
        case .qa: return "Preserve reproduction steps, Expected and Actual sections, identifiers and exact error strings. Do not invent missing facts."
        case .release: return "Describe user-visible changes and preserve version numbers. Do not invent features."
        }
    }
}

enum WritingLanguage {
    static func detect(_ text: String) -> String? {
        guard text.split(whereSeparator: \.isWhitespace).count >= 4 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let results = recognizer.languageHypotheses(withMaximum:3).sorted { $0.value > $1.value }
        guard let top = results.first, top.value >= 0.75, top.value - (results.dropFirst().first?.value ?? 0) >= 0.25 else { return nil }
        switch top.key { case .english: return "en"; case .turkish: return "tr"; default: return nil }
    }
}

struct WritingChange: Identifiable, Equatable {
    let id: Int
    let before: String
    let after: String
    var category: String {
        let joined = before + after
        return !joined.isEmpty && joined.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).contains($0)
        } ? "Punctuation & spacing" : "Text"
    }
}

enum WritingReviewPart: Equatable {
    case unchanged(String), change(WritingChange)
}

struct WritingReview {
    let parts: [WritingReviewPart]
    var changes: [WritingChange] { parts.compactMap { if case let .change(change) = $0 { return change }; return nil } }

    init(original: String, revised: String) {
        func tokens(_ text: String) -> [String] {
            let regex = try! NSRegularExpression(pattern:#"[\p{L}\p{M}\p{N}_]+|\s+|\X"#)
            let source = text as NSString
            return regex.matches(in:text,range:NSRange(location:0,length:source.length)).map { source.substring(with:$0.range) }
        }
        let old = tokens(original), new = tokens(revised)
        let difference = new.difference(from:old, by:{ $0.utf8.elementsEqual($1.utf8) })
        var removed = Set<Int>(), inserted = Set<Int>()
        for edit in difference {
            switch edit {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var i = 0, j = 0, id = 0, result: [WritingReviewPart] = []
        var unchanged = "", before = "", after = ""
        while i < old.count || j < new.count {
            if removed.contains(i) || inserted.contains(j) {
                if !unchanged.isEmpty { result.append(.unchanged(unchanged)); unchanged = "" }
                while i < old.count, removed.contains(i) { before += old[i]; i += 1 }
                while j < new.count, inserted.contains(j) { after += new[j]; j += 1 }
                result.append(.change(WritingChange(id:id,before:before,after:after)))
                id += 1; before = ""; after = ""
            } else if i < old.count, j < new.count {
                unchanged += old[i]; i += 1; j += 1
            } else { break }
        }
        if !unchanged.isEmpty { result.append(.unchanged(unchanged)) }
        parts = result
    }

    func render(accepting ids: Set<Int>) -> String {
        parts.map {
            switch $0 { case .unchanged(let text): return text
            case .change(let change): return ids.contains(change.id) ? change.after : change.before }
        }.joined()
    }
}

enum WritingPanelPlacement {
    static func badge(near selection: CGRect, within screen: CGRect) -> CGPoint? {
        let size: CGFloat = 26, gap: CGFloat = 6
        guard screen.width >= size, screen.height >= size else { return nil }
        let y = min(max(selection.midY-size/2,screen.minY),screen.maxY-size)
        let x = min(max(selection.minX,screen.minX),screen.maxX-size)
        let candidates = [
            CGPoint(x:selection.maxX+gap,y:y), CGPoint(x:selection.minX-gap-size,y:y),
            CGPoint(x:x,y:selection.minY-gap-size), CGPoint(x:x,y:selection.maxY+gap)
        ]
        return candidates.first { screen.contains(CGRect(origin:$0,size:CGSize(width:size,height:size))) }
    }

    static func origin(size: CGSize, near anchor: CGRect, within screen: CGRect) -> CGPoint {
        let gap: CGFloat = 12
        let below = anchor.minY - gap - size.height
        let above = anchor.maxY + gap
        let y = below >= screen.minY ? below : above + size.height <= screen.maxY ? above :
            (anchor.minY - screen.minY >= screen.maxY - anchor.maxY ? below : above)
        return CGPoint(
            x:min(max(anchor.minX,screen.minX),max(screen.minX,screen.maxX-size.width)),
            y:min(max(y,screen.minY),max(screen.minY,screen.maxY-size.height))
        )
    }
}
