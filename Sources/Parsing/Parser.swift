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

        /// Parses a single XML document from a string into a document node.
        public func parse(_ xml: String, limits: Limits = .default) throws -> PureXML.Model.Node {
            try build(EventReader(xml, limits: limits))
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
            try build(EventReader(pulling: pull, limits: limits))
        }

        /// Parses a single XML document from an incremental BYTE source, decoding
        /// the encoding (UTF-8 or UTF-16) on the fly so the bytes are never fully
        /// buffered. The closure returns the next byte or nil at end of input.
        public func parse(
            pullingBytes pull: @escaping () -> UInt8?,
            limits: Limits = .default,
        ) throws -> PureXML.Model.Node {
            var decoder = StreamingDecoder(pullingBytes: pull)
            return try build(EventReader(pulling: { decoder.next() }, limits: limits))
        }

        private func build(_ source: EventReader) throws -> PureXML.Model.Node {
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
            return .document(roots)
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
