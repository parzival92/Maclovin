/// Pure presentation and selection logic for the `cleanup review` picker:
/// grouping candidates by source with stable numbering, and parsing the
/// user's selection line. Kept out of the CLI target so it is unit-testable
/// without standard input.
public enum CleanupReview {
    /// One numbered line in the picker. Numbers are 1-based and sequential
    /// across all groups, so "3" always means the third listed candidate.
    public struct Item: Equatable, Sendable {
        public let number: Int
        public let candidate: CleanupCandidate
    }

    /// Candidates that share a source, ordered for review.
    public struct Group: Equatable, Sendable {
        public let source: String
        public let items: [Item]

        public var totalEstimatedBytes: UInt64 {
            items.reduce(0) { $0 + $1.candidate.estimatedBytes }
        }

        public var totalEstimatedSize: ByteSize { ByteSize(totalEstimatedBytes) }
    }

    /// Groups candidates by source for the picker: groups ordered by total
    /// estimate (largest first), candidates within a group likewise, and
    /// numbering running sequentially through the whole list.
    public static func groups(for candidates: [CleanupCandidate]) -> [Group] {
        var bySource: [String: [CleanupCandidate]] = [:]
        for candidate in candidates {
            bySource[candidate.source, default: []].append(candidate)
        }

        let orderedSources = bySource
            .map { (source: $0.key, total: $0.value.reduce(UInt64(0)) { $0 + $1.estimatedBytes }) }
            .sorted { $0.total == $1.total ? $0.source < $1.source : $0.total > $1.total }

        var number = 0
        return orderedSources.map { source, _ in
            let items = bySource[source, default: []]
                .sorted { $0.estimatedBytes > $1.estimatedBytes }
                .map { candidate -> Item in
                    number += 1
                    return Item(number: number, candidate: candidate)
                }
            return Group(source: source, items: items)
        }
    }

    /// The parsed result of the user's selection line.
    public enum Selection: Equatable, Sendable {
        /// Empty input: the user backed out; nothing runs.
        case cancelled
        /// Valid selection: sorted, de-duplicated 1-based numbers.
        case selected([Int])
        /// Unparsable or out-of-range input, with the reason. Callers abort
        /// rather than re-prompt, matching the confirmation gate's one-shot rule.
        case invalid(String)
    }

    /// Parses a selection line against a list of `count` numbered candidates.
    ///
    /// Accepted forms, separated by commas and/or spaces: single numbers
    /// (`3`), inclusive ranges (`1-3`), and the word `all`. Empty or nil input
    /// cancels.
    public static func parseSelection(_ input: String?, count: Int) -> Selection {
        let trimmed = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .cancelled }

        if trimmed.lowercased() == "all" {
            return count > 0 ? .selected(Array(1...count)) : .invalid("there are no candidates to select")
        }

        var numbers: Set<Int> = []
        let tokens = trimmed
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)

        for token in tokens {
            if let number = Int(token) {
                guard (1...count).contains(number) else {
                    return .invalid("'\(token)' is out of range; pick numbers between 1 and \(count)")
                }
                numbers.insert(number)
            } else if let dash = token.firstIndex(of: "-"),
                      let lower = Int(token[..<dash]),
                      let upper = Int(token[token.index(after: dash)...]) {
                guard lower <= upper else {
                    return .invalid("'\(token)' is not a valid range")
                }
                guard lower >= 1, upper <= count else {
                    return .invalid("'\(token)' is out of range; pick numbers between 1 and \(count)")
                }
                numbers.formUnion(lower...upper)
            } else {
                return .invalid("could not understand '\(token)'; use numbers, ranges like 2-4, or 'all'")
            }
        }

        return .selected(numbers.sorted())
    }
}
