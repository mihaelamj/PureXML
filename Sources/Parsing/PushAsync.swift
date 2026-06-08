public extension PureXML {
    /// Parses an asynchronous sequence of text chunks (a socket, a file read loop)
    /// into a stream of ``Parsing/Event`` values, driving the push parser as each
    /// chunk arrives. The document is never held whole.
    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    static func events<Chunks: AsyncSequence & Sendable>(
        feeding chunks: Chunks,
    ) -> AsyncThrowingStream<Parsing.Event, Error> where Chunks.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = Parsing.PushParser(sax: Self.streamingHandler(continuation))
                    for try await chunk in chunks {
                        try parser.feed(chunk)
                    }
                    try parser.finish()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    private static func streamingHandler(
        _ continuation: AsyncThrowingStream<Parsing.Event, Error>.Continuation,
    ) -> Parsing.SAXHandler {
        Parsing.SAXHandler(
            startElement: { continuation.yield(.startElement(name: $0, attributes: $1)) },
            endElement: { continuation.yield(.endElement(name: $0)) },
            characters: { continuation.yield(.characters($0)) },
            cdata: { continuation.yield(.cdata($0)) },
            comment: { continuation.yield(.comment($0)) },
            processingInstruction: { continuation.yield(.processingInstruction(target: $0, data: $1)) },
        )
    }
}
