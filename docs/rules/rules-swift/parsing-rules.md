# Parsing Rules

When parsing any strings, data files (CSV, XML, JSON, Excel), or structured text, follow the **OpenAPIKit idiom** by [Matt Polzin](https://github.com/mattpolzin/OpenAPIKit).

## Reference Repository

**https://github.com/mattpolzin/OpenAPIKit**

Key files to study:
- `Document.swift` - Root document structure, Codable implementation
- `JSONSchema.swift` - Enum-based type representation
- `JSONSchemaContext.swift` - Protocol-driven context pattern

## Core Principles

### 1. Protocol-First Design

Define shared behavior in protocols before concrete types:

```swift
/// All parsed items share these properties
protocol ParsedItemContext {
    var id: String { get }
    var rawValue: String { get }
}

/// Type-specific contexts extend the base
protocol ProductContext: ParsedItemContext {
    var name: String { get }
    var price: Decimal { get }
}
```

### 2. Codable-Based Parsing

Use Swift's built-in `Codable` with custom `init(from decoder:)`:

```swift
struct Product: Decodable {
    let name: String
    let price: Decimal

    enum CodingKeys: String, CodingKey {
        case name = "NAZIV PROIZVODA"
        case price = "MALOPRODAJNA CIJENA"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)

        // Custom parsing for complex types
        let priceString = try container.decode(String.self, forKey: .price)
        price = try Self.parsePrice(priceString)
    }
}
```

### 3. Enum with Associated Values

Represent variants using enums with associated values:

```swift
enum ParsedDocument: Sendable {
    case csv(CSVDocument)
    case xml(XMLDocument)
    case json(JSONDocument)
    case excel(ExcelDocument)

    var unified: UnifiedDocument {
        switch self {
        case .csv(let doc): return doc.toUnified()
        case .xml(let doc): return doc.toUnified()
        case .json(let doc): return doc.toUnified()
        case .excel(let doc): return doc.toUnified()
        }
    }
}
```

### 4. Context Objects with CoreContext Pattern

Separate core context from type-specific extensions:

```swift
/// Core context all items have
struct CoreContext<Format: DataFormat>: ParsedItemContext {
    let id: String
    let rawValue: String
    let format: Format
    let warnings: [ParseWarning]
}

/// Type-specific context
struct PriceContext {
    let value: Decimal
    let currency: Currency
    let isSpecialOffer: Bool
}
```

### 5. Module Isolation per Format/Provider

Separate modules for different data sources:

```
MyParser/
├── Sources/
│   ├── ParserCore/        # Unified types, protocols
│   ├── ParserCSV/         # CSV-specific parsing
│   ├── ParserXML/         # XML-specific parsing
│   ├── ParserJSON/        # JSON-specific parsing
│   └── ParserCompat/      # Convert between formats
```

### 6. Validation Separate from Parsing

Parse first, validate second:

```swift
struct ParsedItem {
    // ... properties

    func validate() throws -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []

        if id.isEmpty {
            warnings.append(.missingId)
        }
        if !isValidFormat {
            warnings.append(.invalidFormat(raw: rawValue))
        }

        return warnings
    }
}
```

The snippet above is the minimal shape. The **full, MANDATORY validation idiom**
(composable `Validation<Subject>` values, the combinator algebra, errors with a
coding-path context, the default-plus-blank `Validator`, and the test style) lives
in its own rule: see `universal/validation-rules.md`. A monolithic
`func validate()` that appends to a `var warnings` through a tree of `if`
statements is the anti-pattern that rule replaces; use it only as throwaway
pseudocode, never as the shipped validator.

### 7. Builder Pattern for Transformations

Immutable transformations with fluent API:

```swift
extension CoreContext {
    func with(id newId: String) -> Self {
        var copy = self
        copy.id = newId
        return copy
    }

    func addingWarning(_ warning: ParseWarning) -> Self {
        var copy = self
        copy.warnings.append(warning)
        return copy
    }
}
```

### 8. Type-Safe References

Use typed references for lookups:

```swift
struct ItemReference: Hashable, Codable {
    let source: DataSource
    let id: String
}

extension Document {
    subscript(item ref: ItemReference) -> ParsedItem? {
        items.first { $0.source == ref.source && $0.id == ref.id }
    }
}
```

## Price/Number Parsing Helper

Common price parsing that handles European formats:

```swift
extension Decimal {
    /// Parse price string: "7,99", "7.99", "7,99€", "7.99 EUR"
    static func parsePrice(_ string: String) throws -> Decimal {
        var cleaned = string
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "EUR", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Handle European format (comma as decimal)
        if cleaned.contains(",") && cleaned.contains(".") {
            // "1.234,56" -> "1234.56"
            if cleaned.firstIndex(of: ",")! > cleaned.firstIndex(of: ".")! {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")

        guard let value = Decimal(string: cleaned) else {
            throw ParseError.invalidPrice(string)
        }
        return value
    }
}
```

## Text Encoding Handling

Always handle multiple encodings:

```swift
func decodeText(from data: Data) -> String? {
    let encodings: [String.Encoding] = [
        .utf8,
        .windowsCP1250,  // Croatian/Central European
        .isoLatin2,      // ISO-8859-2
        .isoLatin1       // Fallback
    ]

    for encoding in encodings {
        if let text = String(data: data, encoding: encoding) {
            return text
        }
    }
    return nil
}
```

## DO

- Define protocols for shared parsing behavior
- Use Codable with custom `init(from decoder:)`
- Separate parsing from validation
- Use enums with associated values for variants
- Create type-safe references
- Handle multiple text encodings
- Use builder pattern for transformations

## DO NOT

- Parse and validate in the same step
- Use raw string manipulation without protocols
- Ignore text encoding issues
- Create tightly-coupled parsers
- Skip the validation layer
- Use force unwrapping in parsers
