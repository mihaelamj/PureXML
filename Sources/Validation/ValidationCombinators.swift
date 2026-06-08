// The declarative combinator algebra for ``PureXML/Validation/Validation``.
// Free functions returning closures, so validations compose by value rather than
// through imperative control flow. Generic over both the subject type and the
// document, per the one-framework-parameterized-over-the-document rule.

typealias Validatable = PureXML.Validation.Validatable
typealias VContext<Subject: PureXML.Validation.Validatable, Document> =
    PureXML.Validation.ValidationContext<Subject, Document>
typealias VError = PureXML.Validation.ValidationError
typealias VRule<Subject: PureXML.Validation.Validatable, Document> =
    PureXML.Validation.Validation<Subject, Document>

// MARK: Context -> error array

func && <T: Validatable, D>(
    lhs: @escaping (VContext<T, D>) -> [VError],
    rhs: @escaping (VContext<T, D>) -> [VError],
) -> (VContext<T, D>) -> [VError] {
    { context in lhs(context) + rhs(context) }
}

func || <T: Validatable, D>(
    lhs: @escaping (VContext<T, D>) -> [VError],
    rhs: @escaping (VContext<T, D>) -> [VError],
) -> (VContext<T, D>) -> [VError] {
    { context in
        let left = lhs(context)
        if left.isEmpty { return [] }
        let right = rhs(context)
        return right.isEmpty ? [] : left + right
    }
}

// MARK: Context -> Bool

func && <T: Validatable, D>(
    lhs: @escaping (VContext<T, D>) -> Bool,
    rhs: @escaping (VContext<T, D>) -> Bool,
) -> (VContext<T, D>) -> Bool {
    { context in lhs(context) && rhs(context) }
}

func || <T: Validatable, D>(
    lhs: @escaping (VContext<T, D>) -> Bool,
    rhs: @escaping (VContext<T, D>) -> Bool,
) -> (VContext<T, D>) -> Bool {
    { context in lhs(context) || rhs(context) }
}

// MARK: Subject KeyPath -> Bool

func == <T: Validatable, U: Equatable, D>(lhs: KeyPath<T, U>, rhs: U) -> (VContext<T, D>) -> Bool {
    { $0.subject[keyPath: lhs] == rhs }
}

func != <T: Validatable, U: Equatable, D>(lhs: KeyPath<T, U>, rhs: U) -> (VContext<T, D>) -> Bool {
    { $0.subject[keyPath: lhs] != rhs }
}

func > <T: Validatable, U: Comparable, D>(lhs: KeyPath<T, U>, rhs: U) -> (VContext<T, D>) -> Bool {
    { $0.subject[keyPath: lhs] > rhs }
}

func >= <T: Validatable, U: Comparable, D>(lhs: KeyPath<T, U>, rhs: U) -> (VContext<T, D>) -> Bool {
    { $0.subject[keyPath: lhs] >= rhs }
}

func < <T: Validatable, U: Comparable, D>(lhs: KeyPath<T, U>, rhs: U) -> (VContext<T, D>) -> Bool {
    { $0.subject[keyPath: lhs] < rhs }
}

func <= <T: Validatable, U: Comparable, D>(lhs: KeyPath<T, U>, rhs: U) -> (VContext<T, D>) -> Bool {
    { $0.subject[keyPath: lhs] <= rhs }
}

// MARK: Digging and lifting

/// Dig to a value by KeyPath and run arbitrary logic on it.
func take<T: Validatable, U, D>(_ path: KeyPath<T, U>, check: @escaping (U) -> Bool) -> (VContext<T, D>) -> Bool {
    { check($0.subject[keyPath: path]) }
}

/// Run child-typed validations against a lifted value, keeping the parent path
/// and document.
func lift<T: Validatable, U: Validatable, D>(
    _ path: KeyPath<T, U>,
    into validations: VRule<U, D>...,
) -> (VContext<T, D>) -> [VError] {
    { context in
        validations.flatMap { $0.apply(to: context.subject[keyPath: path], at: context.codingPath, in: context.document) }
    }
}

/// Unwrap an optional, erroring if nil, else run child validations.
func unwrap<T: Validatable, U: Validatable, D>(
    _ path: KeyPath<T, U?>,
    into validations: VRule<U, D>...,
    description: String? = nil,
) -> (VContext<T, D>) -> [VError] {
    { context in
        guard let subject = context.subject[keyPath: path] else {
            let reason = description.map { "Tried to unwrap but found nil: \($0)" } ?? "Tried to unwrap an optional and found nil"
            return [VError(reason: reason, at: context.codingPath)]
        }
        return validations.flatMap { $0.apply(to: subject, at: context.codingPath, in: context.document) }
    }
}

/// Apply many validations to the same context (`lift` with `\.self`).
func all<T: Validatable, D>(_ validations: VRule<T, D>...) -> (VContext<T, D>) -> [VError] {
    { context in validations.flatMap { $0.apply(to: context.subject, at: context.codingPath, in: context.document) } }
}
