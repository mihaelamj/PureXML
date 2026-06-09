extension PureXML.Schema {
    /// Validates a document against a RELAX NG grammar by Brzozowski-style
    /// derivatives (James Clark's "An algorithm for RELAX NG validation"). The
    /// pattern is repeatedly derived with respect to each event of the instance;
    /// the document is valid when the residual pattern is nullable.
    struct RelaxNGEngine {
        let defines: [String: PureXML.Schema.Pattern]

        /// Whether `root` matches `start`.
        func matches(start: PureXML.Schema.Pattern, root: PureXML.Model.Node) -> Bool {
            nullable(childDeriv(start, root))
        }

        // MARK: Simplifying constructors

        func choice(_ lhs: PureXML.Schema.Pattern, _ rhs: PureXML.Schema.Pattern) -> PureXML.Schema.Pattern {
            if case .notAllowed = lhs { return rhs }
            if case .notAllowed = rhs { return lhs }
            return .choice(lhs, rhs)
        }

        private func group(_ lhs: PureXML.Schema.Pattern, _ rhs: PureXML.Schema.Pattern) -> PureXML.Schema.Pattern {
            if case .notAllowed = lhs { return .notAllowed }
            if case .notAllowed = rhs { return .notAllowed }
            if case .empty = lhs { return rhs }
            if case .empty = rhs { return lhs }
            return .group(lhs, rhs)
        }

        private func interleave(_ lhs: PureXML.Schema.Pattern, _ rhs: PureXML.Schema.Pattern) -> PureXML.Schema.Pattern {
            if case .notAllowed = lhs { return .notAllowed }
            if case .notAllowed = rhs { return .notAllowed }
            if case .empty = lhs { return rhs }
            if case .empty = rhs { return lhs }
            return .interleave(lhs, rhs)
        }

        private func after(_ lhs: PureXML.Schema.Pattern, _ rhs: PureXML.Schema.Pattern) -> PureXML.Schema.Pattern {
            if case .notAllowed = lhs { return .notAllowed }
            if case .notAllowed = rhs { return .notAllowed }
            return .after(lhs, rhs)
        }

        func resolve(_ name: String) -> PureXML.Schema.Pattern {
            defines[name] ?? .notAllowed
        }

        // MARK: Nullability

        func nullable(_ pattern: PureXML.Schema.Pattern, visiting: Set<String> = []) -> Bool {
            switch pattern {
            case .empty, .text: return true
            case let .choice(lhs, rhs): return nullable(lhs, visiting: visiting) || nullable(rhs, visiting: visiting)
            case let .group(lhs, rhs), let .interleave(lhs, rhs):
                return nullable(lhs, visiting: visiting) && nullable(rhs, visiting: visiting)
            case let .oneOrMore(inner), let .list(inner): return nullable(inner, visiting: visiting)
            case let .ref(name):
                guard !visiting.contains(name) else { return false }
                return nullable(resolve(name), visiting: visiting.union([name]))
            default:
                return false
            }
        }

        // MARK: Text and attribute derivatives

        func textDeriv(_ pattern: PureXML.Schema.Pattern, _ string: String) -> PureXML.Schema.Pattern {
            switch pattern {
            case let .choice(lhs, rhs): return choice(textDeriv(lhs, string), textDeriv(rhs, string))
            case let .interleave(lhs, rhs):
                return choice(interleave(textDeriv(lhs, string), rhs), interleave(lhs, textDeriv(rhs, string)))
            case let .group(lhs, rhs):
                let derived = group(textDeriv(lhs, string), rhs)
                return nullable(lhs) ? choice(derived, textDeriv(rhs, string)) : derived
            case let .after(lhs, rhs): return after(textDeriv(lhs, string), rhs)
            case let .oneOrMore(inner):
                return group(textDeriv(inner, string), choice(.oneOrMore(inner), .empty))
            case .text: return .text
            case let .ref(name): return textDeriv(resolve(name), string)
            default: return valueDeriv(pattern, string)
            }
        }

        private func valueDeriv(_ pattern: PureXML.Schema.Pattern, _ string: String) -> PureXML.Schema.Pattern {
            switch pattern {
            case let .value(type, literal):
                type.valueMatches(string, literal: literal) ? .empty : .notAllowed
            case let .data(type): type.validate(string) == nil ? .empty : .notAllowed
            case let .list(inner): listMatches(inner, string) ? .empty : .notAllowed
            default: .notAllowed
            }
        }

        private func listMatches(_ pattern: PureXML.Schema.Pattern, _ string: String) -> Bool {
            var residual = pattern
            for token in string.split(whereSeparator: \.isWhitespace) {
                residual = textDeriv(residual, String(token))
            }
            return nullable(residual)
        }

        func attributeDeriv(_ pattern: PureXML.Schema.Pattern, _ attribute: PureXML.Model.Attribute) -> PureXML.Schema.Pattern {
            switch pattern {
            case let .choice(lhs, rhs): return choice(attributeDeriv(lhs, attribute), attributeDeriv(rhs, attribute))
            case let .group(lhs, rhs):
                return choice(group(attributeDeriv(lhs, attribute), rhs), group(lhs, attributeDeriv(rhs, attribute)))
            case let .interleave(lhs, rhs):
                return choice(interleave(attributeDeriv(lhs, attribute), rhs), interleave(lhs, attributeDeriv(rhs, attribute)))
            case let .oneOrMore(inner):
                return group(attributeDeriv(inner, attribute), choice(.oneOrMore(inner), .empty))
            case let .after(lhs, rhs): return after(attributeDeriv(lhs, attribute), rhs)
            case let .attribute(nameClass, content):
                guard nameClass.contains(attribute.name), valueMatches(content, attribute.value) else { return .notAllowed }
                return .empty
            case let .ref(name): return attributeDeriv(resolve(name), attribute)
            default: return .notAllowed
            }
        }

        private func valueMatches(_ content: PureXML.Schema.Pattern, _ value: String) -> Bool {
            value.isEmpty ? nullable(content) : nullable(textDeriv(content, value))
        }

        private func oneOrMoreP(_ inner: PureXML.Schema.Pattern) -> PureXML.Schema.Pattern {
            if case .notAllowed = inner { return .notAllowed }
            return .oneOrMore(inner)
        }
    }
}

extension PureXML.Schema.RelaxNGEngine {
    // MARK: Element derivatives

    func childDeriv(_ pattern: PureXML.Schema.Pattern, _ node: PureXML.Model.Node) -> PureXML.Schema.Pattern {
        switch node {
        case let .text(string), let .cdata(string):
            textDeriv(pattern, string)
        case let .element(element):
            processElement(pattern, element)
        default:
            pattern
        }
    }

    private func processElement(_ pattern: PureXML.Schema.Pattern, _ element: PureXML.Model.Element) -> PureXML.Schema.Pattern {
        let opened = startTagOpenDeriv(pattern, element.name)
        let attributed = element.attributes
            .filter { !Self.isNamespaceDeclaration($0) }
            .reduce(opened) { attributeDeriv($0, $1) }
        let closed = startTagCloseDeriv(attributed)
        let withChildren = childrenDeriv(closed, element.children)
        return endTagDeriv(withChildren)
    }

    func startTagOpenDeriv(_ pattern: PureXML.Schema.Pattern, _ name: PureXML.Model.QualifiedName) -> PureXML.Schema.Pattern {
        switch pattern {
        case let .choice(lhs, rhs):
            return choice(startTagOpenDeriv(lhs, name), startTagOpenDeriv(rhs, name))
        case let .element(nameClass, content):
            return nameClass.contains(name) ? after(content, .empty) : .notAllowed
        case let .interleave(lhs, rhs):
            return choice(
                applyAfter({ interleave($0, rhs) }, startTagOpenDeriv(lhs, name)),
                applyAfter({ interleave(lhs, $0) }, startTagOpenDeriv(rhs, name)),
            )
        case let .group(lhs, rhs):
            let derived = applyAfter({ group($0, rhs) }, startTagOpenDeriv(lhs, name))
            return nullable(lhs) ? choice(derived, startTagOpenDeriv(rhs, name)) : derived
        case let .oneOrMore(inner):
            return applyAfter({ group($0, choice(oneOrMoreP(inner), .empty)) }, startTagOpenDeriv(inner, name))
        case let .after(lhs, rhs):
            return applyAfter({ after($0, rhs) }, startTagOpenDeriv(lhs, name))
        case let .ref(reference):
            return startTagOpenDeriv(resolve(reference), name)
        default:
            return .notAllowed
        }
    }

    private func applyAfter(_ transform: (PureXML.Schema.Pattern) -> PureXML.Schema.Pattern, _ pattern: PureXML.Schema.Pattern) -> PureXML.Schema.Pattern {
        switch pattern {
        case let .after(lhs, rhs): after(lhs, transform(rhs))
        case let .choice(lhs, rhs): choice(applyAfter(transform, lhs), applyAfter(transform, rhs))
        default: .notAllowed
        }
    }

    func startTagCloseDeriv(_ pattern: PureXML.Schema.Pattern) -> PureXML.Schema.Pattern {
        switch pattern {
        case let .choice(lhs, rhs): choice(startTagCloseDeriv(lhs), startTagCloseDeriv(rhs))
        case let .group(lhs, rhs): group(startTagCloseDeriv(lhs), startTagCloseDeriv(rhs))
        case let .interleave(lhs, rhs): interleave(startTagCloseDeriv(lhs), startTagCloseDeriv(rhs))
        case let .oneOrMore(inner): oneOrMoreP(startTagCloseDeriv(inner))
        case let .after(lhs, rhs): after(startTagCloseDeriv(lhs), rhs)
        case .attribute: .notAllowed
        case let .ref(reference): startTagCloseDeriv(resolve(reference))
        default: pattern
        }
    }

    private func childrenDeriv(_ pattern: PureXML.Schema.Pattern, _ children: [PureXML.Model.Node]) -> PureXML.Schema.Pattern {
        let coalesced = Self.coalesceText(children)
        if coalesced.isEmpty { return pattern }
        if coalesced.count == 1, case let .text(string) = coalesced[0] {
            let derived = textDeriv(pattern, string)
            return Self.isWhitespace(string) ? choice(pattern, derived) : derived
        }
        return coalesced.reduce(pattern) { accumulated, node in
            Self.isWhitespaceText(node) ? accumulated : childDeriv(accumulated, node)
        }
    }

    private func endTagDeriv(_ pattern: PureXML.Schema.Pattern) -> PureXML.Schema.Pattern {
        switch pattern {
        case let .choice(lhs, rhs): choice(endTagDeriv(lhs), endTagDeriv(rhs))
        case let .after(lhs, rhs): nullable(lhs) ? rhs : .notAllowed
        case let .ref(reference): endTagDeriv(resolve(reference))
        default: .notAllowed
        }
    }

    // MARK: Helpers

    /// Merges adjacent text and CDATA nodes into single text nodes.
    static func coalesceText(_ children: [PureXML.Model.Node]) -> [PureXML.Model.Node] {
        var result: [PureXML.Model.Node] = []
        var run = ""
        for child in children {
            switch child {
            case let .text(value), let .cdata(value):
                run += value
            case .comment, .processingInstruction:
                continue
            default:
                if !run.isEmpty { result.append(.text(run))
                    run = ""
                }
                result.append(child)
            }
        }
        if !run.isEmpty { result.append(.text(run)) }
        return result
    }

    private static func isWhitespace(_ string: String) -> Bool {
        string.allSatisfy(\.isWhitespace)
    }

    static func isWhitespaceText(_ node: PureXML.Model.Node) -> Bool {
        if case let .text(value) = node { return isWhitespace(value) }
        return false
    }

    static func isNamespaceDeclaration(_ attribute: PureXML.Model.Attribute) -> Bool {
        attribute.name.prefix == "xmlns" || (attribute.name.prefix == nil && attribute.name.localName == "xmlns")
    }

    static func elementNameCounts(_ children: [PureXML.Model.Node]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for case let .element(element) in children {
            counts[element.name.description, default: 0] += 1
        }
        return counts
    }
}

/// One open element while streaming a RELAX NG derivative: whether it has had an
/// element child yet, and the text buffered since the last structural event. The
/// `after`-threaded pattern is the validation stack; this frame only carries the
/// bookkeeping `childrenDeriv` needs to treat ignorable whitespace correctly.
private struct RelaxNGStreamFrame {
    var hadElementChild = false
    var pendingText = ""
}

public extension PureXML.Schema {
    /// The residual derivative plus per-element whitespace bookkeeping carried
    /// across the events of a streamed RELAX NG validation.
    struct RelaxNGStreamingState {
        var current: PureXML.Schema.Pattern
        fileprivate var frames: [RelaxNGStreamFrame]
    }
}

extension PureXML.Schema.RelaxNGEngine {
    /// The initial streaming state for a start pattern, with a document-level frame.
    func streamingStart(_ start: PureXML.Schema.Pattern) -> PureXML.Schema.RelaxNGStreamingState {
        PureXML.Schema.RelaxNGStreamingState(current: start, frames: [RelaxNGStreamFrame()])
    }

    /// Derives the state by one parse event, the streaming form of `childDeriv`.
    /// Text is buffered and applied at structural boundaries so ignorable
    /// whitespace is treated exactly as the tree walk's `childrenDeriv` does.
    func streamingConsume(_ event: PureXML.Parsing.Event, into state: inout PureXML.Schema.RelaxNGStreamingState) {
        switch event {
        case let .startElement(name, attributes):
            flushText(&state, closing: false)
            if !state.frames.isEmpty { state.frames[state.frames.count - 1].hadElementChild = true }
            let opened = startTagOpenDeriv(state.current, name)
            let attributed = attributes
                .filter { !Self.isNamespaceDeclaration($0) }
                .reduce(opened) { attributeDeriv($0, $1) }
            state.current = startTagCloseDeriv(attributed)
            state.frames.append(RelaxNGStreamFrame())
        case let .characters(text), let .cdata(text):
            if !state.frames.isEmpty { state.frames[state.frames.count - 1].pendingText += text }
        case .endElement:
            flushText(&state, closing: true)
            state.current = endTagDeriv(state.current)
            if !state.frames.isEmpty { state.frames.removeLast() }
        case .comment, .processingInstruction:
            break
        }
    }

    /// Whether the streamed document satisfied the schema (the residual is nullable).
    func streamingValid(_ state: PureXML.Schema.RelaxNGStreamingState) -> Bool {
        nullable(state.current)
    }

    private func flushText(_ state: inout PureXML.Schema.RelaxNGStreamingState, closing: Bool) {
        guard let index = state.frames.indices.last else { return }
        let text = state.frames[index].pendingText
        guard !text.isEmpty else { return }
        state.frames[index].pendingText = ""
        if !Self.isWhitespace(text) {
            state.current = textDeriv(state.current, text)
        } else if closing, !state.frames[index].hadElementChild {
            // A lone whitespace text child is optional, the `childrenDeriv` rule.
            state.current = choice(state.current, textDeriv(state.current, text))
        }
        // Whitespace among element siblings is ignorable and skipped.
    }
}
