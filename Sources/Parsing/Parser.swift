/// A partially-built element while its children stream in. File-scope and
/// private: an internal detail of the tree builder, not part of the namespace.
private struct ElementFrame {
    let name: PureXML.Model.QualifiedName
    let attributes: [PureXML.Model.Attribute]
    var children: [PureXML.Model.Node] = []
}

public extension PureXML.Parsing {
    /// Builds a ``PureXML/Model/Node`` tree by draining the streaming
    /// ``EventReader`` with an explicit element stack. It is iterative, not
    /// recursive, and the streaming core means it never requires the whole input
    /// in memory at once: characters are pulled on demand. Callers that do not
    /// need a full tree should consume ``EventReader`` directly.
    struct Parser: Sendable {
        public init() {}

        /// Parses a single XML document from a string into a document node. Supply
        /// a ``EntityResolver`` to opt into external entities; the default refuses
        /// them, keeping XXE closed.
        public func parse(
            _ xml: String,
            limits: Limits = .default,
            resolver: EntityResolver = .refusing,
        ) throws -> PureXML.Model.Node {
            try build(EventReader(xml, limits: limits, resolver: resolver)).node
        }

        /// Parses a string and surfaces the parsed DTD (entities, element content
        /// models, parameter entities, external identifiers) alongside the tree,
        /// for schema validation.
        public func parseWithDocumentType(
            _ xml: String,
            limits: Limits = .default,
            resolver: EntityResolver = .refusing,
        ) throws -> (node: PureXML.Model.Node, documentType: DocumentType) {
            try build(EventReader(xml, limits: limits, resolver: resolver))
        }

        /// Reads a possibly-invalid document without ever throwing: returns the
        /// maximal best-effort tree and a located ``Diagnostic`` for every problem
        /// found. Well-formed input yields the same tree as ``parse(_:limits:resolver:)``
        /// with no diagnostics. See ``readRecovering(_:)`` for the recovery contract.
        public func read(
            _ xml: String,
            limits: Limits = .default,
            resolver: EntityResolver = .refusing,
        ) -> ReadResult {
            readRecovering(EventReader(xml, limits: limits, resolver: resolver, recovering: true))
        }

        /// Reads a possibly-invalid document into a mutable, parent-aware tree whose
        /// nodes carry source spans, plus located diagnostics. The editor entry
        /// point: never throws, recovers in place, and lets a located finding be
        /// mapped to a source range through ``Model/TreeNode/node(at:)``.
        public func readTree(
            _ xml: String,
            limits: Limits = .default,
            resolver: EntityResolver = .refusing,
        ) -> (tree: PureXML.Model.TreeNode, diagnostics: [Diagnostic]) {
            readTreeRecovering(EventReader(xml, limits: limits, resolver: resolver, recovering: true))
        }

        /// Parses a single XML document from raw bytes, detecting the encoding
        /// (UTF-8 or UTF-16, with or without a byte-order mark) before parsing.
        public func parse(bytes: [UInt8], limits: Limits = .default) throws -> PureXML.Model.Node {
            try parse(ByteDecoder.decode(bytes), limits: limits)
        }

        /// Parses a single XML document from an incremental character source. The
        /// closure returns the next character or nil at end of input, so the
        /// document can arrive in chunks and is never held whole.
        public func parse(
            pulling pull: @escaping () -> Character?,
            limits: Limits = .default,
        ) throws -> PureXML.Model.Node {
            try build(EventReader(pulling: pull, limits: limits)).node
        }

        /// Parses a single XML document from an incremental BYTE source, decoding
        /// the encoding (UTF-8 or UTF-16) on the fly so the bytes are never fully
        /// buffered. The closure returns the next byte or nil at end of input.
        public func parse(
            pullingBytes pull: @escaping () -> UInt8?,
            limits: Limits = .default,
        ) throws -> PureXML.Model.Node {
            var decoder = StreamingDecoder(pullingBytes: pull)
            return try build(EventReader(pulling: { decoder.next() }, limits: limits)).node
        }

        /// Parses a document, delivering SAX-style callbacks instead of building a
        /// tree. The handler's callbacks fire as the parse streams.
        public func parse(
            _ xml: String,
            sax handler: SAXHandler,
            limits: Limits = .default,
            resolver: EntityResolver = .refusing,
        ) throws {
            var reader = EventReader(xml, limits: limits, resolver: resolver)
            handler.startDocument?()
            var produced = false
            while let event = try reader.next() {
                produced = true
                deliver(event, to: handler)
            }
            guard produced else { throw ParseError.emptyDocument }
            handler.endDocument?()
        }

        private func deliver(_ event: Event, to handler: SAXHandler) {
            switch event {
            case let .startElement(name, attributes):
                handler.startElement?(name, attributes)
            case let .endElement(name):
                handler.endElement?(name)
            case let .characters(text):
                handler.characters?(text)
            case let .cdata(text):
                handler.cdata?(text)
            case let .comment(text):
                handler.comment?(text)
            case let .processingInstruction(target, data):
                handler.processingInstruction?(target, data)
            }
        }

        private func build(_ source: EventReader) throws -> (node: PureXML.Model.Node, documentType: DocumentType) {
            var reader = source
            var roots: [PureXML.Model.Node] = []
            var stack: [ElementFrame] = []
            var produced = false

            while let event = try reader.next() {
                produced = true
                switch event {
                case let .startElement(name, attributes):
                    stack.append(ElementFrame(name: name, attributes: attributes))
                case .endElement:
                    guard let frame = stack.popLast() else {
                        throw ParseError.unexpectedEndOfInput(.start)
                    }
                    let element = PureXML.Model.Element(
                        name: frame.name,
                        attributes: frame.attributes,
                        children: frame.children,
                    )
                    attach(.element(element), to: &stack, roots: &roots)
                case let .characters(text):
                    attach(.text(text), to: &stack, roots: &roots)
                case let .cdata(text):
                    attach(.cdata(text), to: &stack, roots: &roots)
                case let .comment(text):
                    attach(.comment(text), to: &stack, roots: &roots)
                case let .processingInstruction(target, data):
                    attach(.processingInstruction(target: target, data: data), to: &stack, roots: &roots)
                }
            }

            guard produced else {
                throw ParseError.emptyDocument
            }
            return (.document(roots), reader.documentType)
        }

        /// Drains a recovering ``EventReader`` (which repairs malformed input in
        /// place and never throws), then closes any elements the input left open by
        /// truncation, innermost first. The reader's diagnostics carry every
        /// problem found. The transformation is deterministic: the same input
        /// always produces the same tree and the same diagnostics.
        func readRecovering(_ source: EventReader) -> ReadResult {
            var reader = source
            var roots: [PureXML.Model.Node] = []
            var stack: [ElementFrame] = []

            while let event = try? reader.next() {
                consume(event, into: &stack, roots: &roots)
            }

            while !stack.isEmpty {
                let frame = stack.removeLast()
                let element = PureXML.Model.Element(name: frame.name, attributes: frame.attributes, children: frame.children)
                attach(.element(element), to: &stack, roots: &roots)
            }
            return ReadResult(node: .document(roots), diagnostics: reader.diagnostics)
        }

        /// Like ``readRecovering(_:)`` but builds a mutable, parent-aware
        /// ``PureXML/Model/TreeNode`` whose every node carries its source span, for
        /// editor use. Never throws; returns the best-effort tree and the
        /// diagnostics. Each element spans from the `<` of its start tag to just
        /// past its end tag (or `/>`); leaf nodes span the text they consumed.
        func readTreeRecovering(_ source: EventReader) -> (tree: PureXML.Model.TreeNode, diagnostics: [Diagnostic]) {
            var reader = source
            let document = PureXML.Model.TreeNode.document()
            var stack: [(node: PureXML.Model.TreeNode, start: PureXML.Parsing.Mark)] = []

            func attach(_ node: PureXML.Model.TreeNode) {
                (stack.last?.node ?? document).append(node)
            }

            while true {
                let start = reader.mark
                guard let event = try? reader.next() else { break }
                switch event {
                case let .startElement(name, attributes):
                    stack.append((PureXML.Model.TreeNode.element(name, attributes: attributes), start))
                case .endElement:
                    guard let (element, openMark) = stack.popLast() else { continue }
                    element.sourceRange = PureXML.Parsing.SourceRange(start: openMark, end: reader.mark)
                    attach(element)
                case let .characters(text):
                    attach(ranged(.text(text), from: start, to: reader.mark))
                case let .cdata(text):
                    attach(ranged(.cdata(text), from: start, to: reader.mark))
                case let .comment(text):
                    attach(ranged(.comment(text), from: start, to: reader.mark))
                case let .processingInstruction(target, data):
                    attach(ranged(.processingInstruction(target: target, data: data), from: start, to: reader.mark))
                }
            }
            while let (element, openMark) = stack.popLast() {
                element.sourceRange = PureXML.Parsing.SourceRange(start: openMark, end: reader.mark)
                attach(element)
            }
            return (document, reader.diagnostics)
        }

        private func ranged(_ node: PureXML.Model.TreeNode, from start: PureXML.Parsing.Mark, to end: PureXML.Parsing.Mark) -> PureXML.Model.TreeNode {
            node.sourceRange = PureXML.Parsing.SourceRange(start: start, end: end)
            return node
        }

        private func consume(_ event: Event, into stack: inout [ElementFrame], roots: inout [PureXML.Model.Node]) {
            switch event {
            case let .startElement(name, attributes):
                stack.append(ElementFrame(name: name, attributes: attributes))
            case .endElement:
                // The recovering reader only emits an end tag for an element it
                // actually closed, so the builder stack stays in step; a stray one
                // (already diagnosed) is simply dropped.
                guard let frame = stack.popLast() else { return }
                let element = PureXML.Model.Element(name: frame.name, attributes: frame.attributes, children: frame.children)
                attach(.element(element), to: &stack, roots: &roots)
            case let .characters(text):
                attach(.text(text), to: &stack, roots: &roots)
            case let .cdata(text):
                attach(.cdata(text), to: &stack, roots: &roots)
            case let .comment(text):
                attach(.comment(text), to: &stack, roots: &roots)
            case let .processingInstruction(target, data):
                attach(.processingInstruction(target: target, data: data), to: &stack, roots: &roots)
            }
        }

        private func attach(
            _ node: PureXML.Model.Node,
            to stack: inout [ElementFrame],
            roots: inout [PureXML.Model.Node],
        ) {
            if stack.isEmpty {
                roots.append(node)
            } else {
                stack[stack.count - 1].children.append(node)
            }
        }
    }
}
