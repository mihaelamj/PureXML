/// Compiles each distinct XPath string once per validation run, so a
/// constraint's selector and field queries are not re-parsed at every element
/// the walk visits. A string that fails to compile caches as nil (no match).
final class XPathQueryCache {
    private var queries: [String: PureXML.XPath.Query?] = [:]

    func query(_ xpath: String) -> PureXML.XPath.Query? {
        if let cached = queries[xpath] { return cached }
        let compiled = try? PureXML.XPath.Query(xpath)
        queries[xpath] = compiled
        return compiled
    }
}
