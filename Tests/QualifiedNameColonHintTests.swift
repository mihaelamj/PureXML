import Testing
@testable import PureXML

/// `QualifiedName(ascii:colonOffset:)` splits a scanned ASCII name using the
/// first-colon offset the byte scanner already found, instead of re-scanning
/// the name with `firstIndex(of:)`. It must produce exactly what
/// `QualifiedName(_:)` produces for the same name. This pins that equivalence
/// across every colon placement: none, leading, trailing, middle, doubled, and
/// a bare colon, so the hint path can never disagree with the scanning path.
@Suite("QualifiedName colon-hint equivalence")
struct QualifiedNameColonHintTests {
    private static let names = [
        "item", "name", "price", "id", "kind", "currency",
        "m:rank", "xml:space", "a:b", "x:y:z",
        ":local", "prefix:", "::", ":", "a:", ":b",
        "_underscore", "with-dash", "with.dot", "n123",
    ]

    /// The offset of the first ':' (a byte offset, which for an ASCII name is a
    /// character offset), or nil. This mirrors what `takeASCIIName` records.
    private func firstColonOffset(_ name: String) -> Int? {
        name.firstIndex(of: ":").map { name.distance(from: name.startIndex, to: $0) }
    }

    @Test("the hint init equals the scanning init for every colon placement")
    func test_equivalence() {
        for name in Self.names {
            let scanned = PureXML.Model.QualifiedName(name)
            let hinted = PureXML.Model.QualifiedName(ascii: name, colonOffset: firstColonOffset(name))
            #expect(hinted.prefix == scanned.prefix, "prefix mismatch for \(name)")
            #expect(hinted.localName == scanned.localName, "localName mismatch for \(name)")
            #expect(hinted == scanned, "qualified name mismatch for \(name)")
        }
    }

    @Test("prefixed and unprefixed ASCII names round-trip through the parser")
    func test_throughParser() throws {
        let node = try PureXML.parse(#"<r xmlns:m="urn:m"><m:child plain="1" m:flag="2"/></r>"#)
        guard case let .document(children) = node, let root = children.compactMap(\.element).first,
              case let .element(child)? = root.children.first
        else {
            Issue.record("no child element")
            return
        }
        #expect(child.name.prefix == "m")
        #expect(child.name.localName == "child")
        let attributeNames = child.attributes.map(\.name)
        #expect(attributeNames.contains { $0.prefix == nil && $0.localName == "plain" })
        #expect(attributeNames.contains { $0.prefix == "m" && $0.localName == "flag" })
    }
}
