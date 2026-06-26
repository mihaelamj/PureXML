import Testing
@testable import PureXML

/// Depth safety and value semantics for the immutable value ``Node`` (#341).
/// An element holds its children behind a copy-on-write reference, so a `Node`
/// is a fixed-size value and building, comparing, hashing, and releasing a
/// deeply-nested tree all run in bounded native stack rather than recursing one
/// frame per level. These trees are built bottom-up (not parsed) so the test
/// exercises the value type directly and stays fast.
@Suite("Value Node depth safety")
struct ValueNodeDepthSafetyTests {
    /// A chain of `depth` nested single-child elements with a text leaf.
    private func deepNode(_ depth: Int) -> PureXML.Model.Node {
        var node: PureXML.Model.Node = .text("leaf")
        for _ in 0 ..< depth {
            node = .element(.init("a", attributes: [.init("x", "1")], children: [node]))
        }
        return node
    }

    @Test("building, comparing, hashing, and releasing a 50k-deep tree do not overflow")
    func test_deepTreeIsBounded() {
        var node: PureXML.Model.Node? = deepNode(50000)
        let other = deepNode(50000)
        #expect(node == other) // iterative equality over the whole depth
        var hasher = Hasher()
        node.hash(into: &hasher) // iterative hashing over the whole depth
        _ = hasher.finalize()
        node = nil // iterative release
        #expect(node == nil)
    }

    @Test("equal deep trees hash equally; an unequal one differs")
    func test_hashMatchesEquality() {
        let first = deepNode(2000)
        let second = deepNode(2000)
        let shorter = deepNode(1999)
        #expect(first == second)
        #expect(first != shorter)
        #expect(first.hashValue == second.hashValue)
    }

    @Test("copy-on-write: mutating a copy leaves the original untouched")
    func test_copyOnWriteValueSemantics() {
        var original = PureXML.Model.Element("root", children: [.element(.init("child"))])
        let copy = original
        original.children.append(.text("added"))
        #expect(original.children.count == 2)
        #expect(copy.children.count == 1)
        #expect(original != copy)
    }

    @Test("a shared subtree survives when one owner is released")
    func test_sharedSubtreeSurvivesPartialRelease() {
        let shared = deepNode(3000)
        var holder: PureXML.Model.Node? = .element(.init("wrap", children: [shared]))
        holder = nil // releasing the wrapper must not tear down `shared`
        #expect(holder == nil)
        // `shared` is still usable: walking it does not crash and finds the leaf.
        var current = shared
        var steps = 0
        while case let .element(element) = current, let first = element.children.first {
            current = first
            steps += 1
        }
        #expect(steps == 3000)
        #expect(current == .text("leaf"))
    }
}
