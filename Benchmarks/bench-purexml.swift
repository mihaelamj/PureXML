// PureXML side of the benchmark (scripts/benchmark.sh). Times the same
// operations the C driver times, over the same file, with internal timing.
// Output: CSV lines "library,operation,bytes,seconds".
// Foundation is used for file access and timing only; the measured code is
// the Foundation-free PureXML library.
import Foundation
import PureXML

let arguments = CommandLine.arguments
guard arguments.count >= 3, let iterations = Int(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: bench-purexml <file.xml> <iterations>\n".utf8))
    exit(1)
}

let path = arguments[1]
let source = try String(contentsOfFile: path, encoding: .utf8)
let bytes = source.utf8.count

func best(_ iterations: Int, _ body: () throws -> Void) rethrows -> Double {
    var bestTime = Double.greatestFiniteMagnitude
    for _ in 0 ..< iterations {
        let start = Date()
        try body()
        bestTime = min(bestTime, -start.timeIntervalSinceNow)
    }
    return bestTime
}

// Parse.
var tree: PureXML.Model.TreeNode!
let parseTime = try best(iterations) {
    tree = try PureXML.parseTree(source, limits: .init(allowDoctype: true))
}

print("purexml,parse,\(bytes),\(String(format: "%.6f", parseTime))")

/// SAX (event stream only): isolates scanner cost from tree construction.
let saxTime = try best(iterations) {
    var reader = PureXML.events(source, limits: .init(allowDoctype: true))
    while try reader.next() != nil {}
}

print("purexml,sax,\(bytes),\(String(format: "%.6f", saxTime))")

// Serialize.
let node = tree.node
var serialized = ""
let serializeTime = best(iterations) {
    serialized = PureXML.serialize(node)
}

print("purexml,serialize,\(bytes),\(String(format: "%.6f", serializeTime))")
FileHandle.standardError.write(Data("purexml serialized bytes: \(serialized.utf8.count)\n".utf8))

// XPath: the same broad selection the C driver counts.
let query = try PureXML.XPath.Query("count(//item[@kind='even'])")
var count = 0.0
let xpathTime = try best(iterations) {
    count = try query.value(at: tree).number
}

print("purexml,xpath,\(bytes),\(String(format: "%.6f", xpathTime))")
FileHandle.standardError.write(Data("purexml xpath count: \(Int(count))\n".utf8))
