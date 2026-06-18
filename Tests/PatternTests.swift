import Testing
@testable import PureXML

@Suite("Streaming patterns")
struct PatternTests {
    private let xml = "<r>"
        + "<a id=\"1\"><b><c/></b></a>"
        + "<a id=\"2\"><b/></a>"
        + "<d><b/></d>"
        + "</r>"

    private func match(_ pattern: String) throws -> [String] {
        try PureXML.Pattern.matches(pattern, in: xml)
    }

    @Test("A relative name matches that element at any depth")
    func test_relativeName() throws {
        #expect(try match("b") == ["/r/a/b", "/r/a/b", "/r/d/b"])
    }

    @Test("A child path requires the immediate parent")
    func test_childPath() throws {
        #expect(try match("a/b") == ["/r/a/b", "/r/a/b"])
    }

    @Test("An absolute path is anchored at the root")
    func test_absolutePath() throws {
        #expect(try match("/r/a/b") == ["/r/a/b", "/r/a/b"])
        #expect(try match("/a/b").isEmpty)
    }

    @Test("A descendant step matches at any depth below")
    func test_descendant() throws {
        #expect(try match("a//c") == ["/r/a/b/c"])
        #expect(try match("//c") == ["/r/a/b/c"])
    }

    @Test("The wildcard matches any element name")
    func test_wildcard() throws {
        #expect(try match("r/*") == ["/r/a", "/r/a", "/r/d"])
    }

    @Test("An attribute pattern matches attributes of matching elements")
    func test_attributePattern() throws {
        #expect(try match("a/@id") == ["/r/a/@id", "/r/a/@id"])
        #expect(try match("//@id") == ["/r/a/@id", "/r/a/@id"])
    }

    @Test("A non-matching pattern yields nothing")
    func test_noMatch() throws {
        #expect(try match("x").isEmpty)
        #expect(try match("d/c").isEmpty)
    }

    @Test("The compiled matcher tests an explicit path")
    func test_explicitPath() throws {
        let matcher = try PureXML.Pattern.Matcher("a/b")
        let path = [
            PureXML.Model.QualifiedName("r"),
            PureXML.Model.QualifiedName("a"),
            PureXML.Model.QualifiedName("b"),
        ]
        #expect(matcher.matchesElement(path: path))
        #expect(!matcher.matchesElement(path: Array(path.dropLast())))
    }

    @Test("Predicates and parent steps are rejected as unsupported")
    func test_unsupported() {
        #expect(throws: PureXML.Pattern.PatternError.self) {
            _ = try PureXML.Pattern.Matcher("a[1]")
        }
        #expect(throws: PureXML.Pattern.PatternError.self) {
            _ = try PureXML.Pattern.Matcher("..")
        }
    }

    @Test("An empty pattern is rejected")
    func test_empty() {
        #expect(throws: PureXML.Pattern.PatternError.empty) {
            _ = try PureXML.Pattern.Matcher("")
        }
    }
}
