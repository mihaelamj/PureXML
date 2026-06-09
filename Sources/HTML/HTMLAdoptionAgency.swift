extension HTMLDocument {
    /// The formatting elements tracked on the active-formatting list and recovered
    /// by the adoption agency.
    private static let formatting: Set<String> = [
        "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u",
    ]

    /// The "special" category: an element of this kind, open below a formatting
    /// element, is the furthest block that triggers reparenting.
    private static let special: Set<String> = [
        "address", "applet", "area", "article", "aside", "blockquote", "body", "br", "button", "caption",
        "center", "col", "colgroup", "dd", "details", "dir", "div", "dl", "dt", "embed", "fieldset",
        "figcaption", "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hgroup", "hr", "html", "iframe", "img", "input", "li", "listing", "main", "marquee",
        "menu", "nav", "object", "ol", "p", "plaintext", "pre", "section", "select", "summary", "table",
        "tbody", "td", "textarea", "tfoot", "th", "thead", "title", "tr", "ul", "wbr", "xmp",
    ]

    /// The elements that bound "element in scope" lookups.
    private static let scopeBoundaries: Set<String> = [
        "applet", "caption", "html", "table", "td", "th", "marquee", "object",
    ]

    func isFormatting(_ name: String) -> Bool {
        Self.formatting.contains(name)
    }

    private func openIndex(_ node: PureXML.Model.TreeNode) -> Int? {
        openBody.firstIndex { $0 === node }
    }

    private func formattingIndex(_ node: PureXML.Model.TreeNode) -> Int? {
        activeFormatting.firstIndex { $0 === node }
    }

    /// Whether `target` is in scope: reachable up the open stack without crossing a
    /// scope boundary.
    private func hasInScope(_ target: PureXML.Model.TreeNode) -> Bool {
        for node in openBody.reversed() {
            if node === target { return true }
            if Self.scopeBoundaries.contains(tagName(node)) { return false }
        }
        return false
    }

    /// The HTML5 "reconstruct the active formatting elements" step: re-open any
    /// formatting elements that were closed out of order, so content after them is
    /// re-wrapped (the `<b><i></b>X</i>` -> `<b><i></i></b><i>X</i>` behavior).
    func reconstructActiveFormatting() {
        guard var index = activeFormatting.indices.last else { return }
        if activeFormatting[index] == nil || isOpen(activeFormatting[index]) { return }
        while index > 0 {
            index -= 1
            if activeFormatting[index] == nil || isOpen(activeFormatting[index]) {
                index += 1
                break
            }
        }
        while index < activeFormatting.count {
            if let template = activeFormatting[index] {
                let clone = template.shallowCopy()
                openBody.last?.append(clone)
                openBody.append(clone)
                activeFormatting[index] = clone
            }
            index += 1
        }
    }

    private func isOpen(_ node: PureXML.Model.TreeNode?) -> Bool {
        guard let node else { return false }
        return openBody.contains { $0 === node }
    }

    /// The HTML5 adoption agency algorithm: recovers a misnested formatting element
    /// end tag, reparenting the intervening block (the "furthest block") and
    /// cloning the formatting element around it.
    func adoptionAgency(_ subject: String) {
        if let current = openBody.last, current !== bodyRoot, tagName(current) == subject, formattingIndex(current) == nil {
            openBody.removeLast()
            return
        }
        var outer = 0
        while outer < 8 {
            outer += 1
            guard let formattingIndexInList = lastFormatting(tag: subject), let formattingElement = activeFormatting[formattingIndexInList] else {
                bodyClose(subject)
                return
            }
            guard let formattingOpenIndex = openIndex(formattingElement) else {
                activeFormatting.remove(at: formattingIndexInList)
                return
            }
            if !hasInScope(formattingElement) { return }
            guard let furthestBlockIndex = openBody[(formattingOpenIndex + 1)...].firstIndex(where: { Self.special.contains(tagName($0)) }) else {
                openBody.removeLast(openBody.count - formattingOpenIndex)
                activeFormatting.remove(at: formattingIndexInList)
                return
            }
            reparent(formattingElement: formattingElement, formattingIndexInList: formattingIndexInList, furthestBlockIndex: furthestBlockIndex)
        }
    }

    private func lastFormatting(tag: String) -> Int? {
        for index in activeFormatting.indices.reversed() {
            guard let entry = activeFormatting[index] else { return nil } // a marker bounds the search
            if tagName(entry) == tag { return index }
        }
        return nil
    }

    /// Steps 8-19 of the algorithm: walk the open elements between the formatting
    /// element and the furthest block, cloning formatting nodes, then clone the
    /// formatting element around the furthest block's content.
    private func reparent(formattingElement: PureXML.Model.TreeNode, formattingIndexInList: Int, furthestBlockIndex: Int) {
        let furthestBlock = openBody[furthestBlockIndex]
        guard let formattingOpenIndex = openIndex(formattingElement), formattingOpenIndex >= 1 else { return }
        let commonAncestor = openBody[formattingOpenIndex - 1]
        var bookmark = formattingIndexInList
        var lastNode = furthestBlock
        var nodeIndex = furthestBlockIndex
        var inner = 0
        while inner < 3 {
            inner += 1
            nodeIndex -= 1
            let node = openBody[nodeIndex]
            if node === formattingElement { break }
            guard let activeIndex = formattingIndex(node) else {
                openBody.remove(at: nodeIndex)
                continue
            }
            let clone = node.shallowCopy()
            activeFormatting[activeIndex] = clone
            openBody[nodeIndex] = clone
            if lastNode === furthestBlock { bookmark = activeIndex + 1 }
            clone.append(lastNode)
            lastNode = clone
        }
        commonAncestor.append(lastNode)
        let formattingClone = formattingElement.shallowCopy()
        for child in furthestBlock.children {
            formattingClone.append(child)
        }
        furthestBlock.append(formattingClone)
        if let removeIndex = formattingIndex(formattingElement) {
            activeFormatting.remove(at: removeIndex)
            if removeIndex < bookmark { bookmark -= 1 }
        }
        activeFormatting.insert(formattingClone, at: min(bookmark, activeFormatting.count))
        if let removeOpen = openIndex(formattingElement) { openBody.remove(at: removeOpen) }
        // The clone becomes a child of the furthest block, so it sits immediately
        // above it on the open-elements stack; inserting below would re-find the
        // same furthest block and loop.
        if let blockIndex = openIndex(furthestBlock) { openBody.insert(formattingClone, at: blockIndex + 1) }
    }
}
