// AgentS runtime for the Swift backend.
//
// Strings are measured and sliced in Unicode scalars, not in Characters: Swift
// counts grapheme clusters where Rust's `chars()` and Python's `len()` count
// scalars, and a backend that disagreed there would fail the differential gate
// on any combining sequence.
//
// Foundation is deliberately not imported. Trim, replace and search are the only
// operations that would need it, they are a dozen lines each, and the generated
// code stays free of any dependency the target platform has to supply.

/// `Result` is hand-rolled because the stdlib's constrains its failure type to
/// `Error`, and AgentS writes `(Result Int64 String)`. Conforming `String` to
/// `Error` retroactively would change an imported type for every module that
/// links this runtime.
public enum ASResult<T, E> {
    case ok(T)
    case err(E)
}

extension ASResult: Equatable where T: Equatable, E: Equatable {}

/// `Pair` is a struct rather than a tuple: Swift tuples cannot conform to
/// protocols, which would leave `list-contains?`, `list-sort` and
/// `map-from-pairs` unusable over pairs.
public struct ASPair<A, B> {
    public let first: A
    public let second: B
    public init(_ a: A, _ b: B) { first = a; second = b }
}

extension ASPair: Equatable where A: Equatable, B: Equatable {}
extension ASPair: Hashable where A: Hashable, B: Hashable {}
extension ASPair: Comparable where A: Comparable, B: Comparable {
    public static func < (l: Self, r: Self) -> Bool {
        if l.first != r.first { return l.first < r.first }
        return l.second < r.second
    }
}

/// Carries an AgentS `err` value out of a `try`. Typed throws let the enclosing
/// function catch exactly this and nothing else, so `try` propagates without the
/// caller-visible colouring that a `throws` signature would impose.
public struct ASThrown<E>: Error {
    public let value: E
    public init(_ value: E) { self.value = value }
}

public enum RT {
    // MARK: arithmetic

    public static func div<T: BinaryInteger>(_ a: T, _ b: T) -> T {
        precondition(b != 0, "division by zero")
        return a / b
    }
    public static func div(_ a: Double, _ b: Double) -> Double { a / b }

    public static func rem<T: BinaryInteger>(_ a: T, _ b: T) -> T {
        precondition(b != 0, "modulo by zero")
        return a % b
    }
    public static func rem(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }

    public static func checkedDiv<T: BinaryInteger>(_ a: T, _ b: T) -> T? { b == 0 ? nil : a / b }
    public static func checkedRem<T: BinaryInteger>(_ a: T, _ b: T) -> T? { b == 0 ? nil : a % b }

    // MARK: strings

    public static func strLen(_ s: String) -> Int64 { Int64(s.unicodeScalars.count) }
    public static func concat(_ parts: [String]) -> String { parts.joined() }
    public static func chars(_ s: String) -> [String] { s.unicodeScalars.map { String($0) } }
    public static func strRev(_ s: String) -> String { fromScalars(Array(s.unicodeScalars).reversed()) }

    public static func trim(_ s: String) -> String {
        var u = Array(s.unicodeScalars)
        while let f = u.first, isSpace(f) { u.removeFirst() }
        while let l = u.last, isSpace(l) { u.removeLast() }
        return fromScalars(u)
    }

    public static func contains(_ s: String, _ sub: String) -> Bool { scalarIndex(s, sub) != nil }

    /// An empty separator yields a leading and trailing empty field, as Rust's
    /// `str::split("")` does. Python raises there instead; the divergence is the
    /// specification's, not this backend's.
    public static func split(_ s: String, _ sep: String) -> [String] {
        let u = Array(s.unicodeScalars)
        let p = Array(sep.unicodeScalars)
        if p.isEmpty { return [""] + u.map { String($0) } + [""] }
        var out: [String] = []
        var start = 0
        var i = 0
        while i + p.count <= u.count {
            if Array(u[i..<(i + p.count)]) == p {
                out.append(fromScalars(Array(u[start..<i])))
                i += p.count
                start = i
            } else {
                i += 1
            }
        }
        out.append(fromScalars(Array(u[start...])))
        return out
    }

    public static func replace(_ s: String, _ from: String, _ to: String) -> String {
        from.isEmpty ? s : split(s, from).joined(separator: to)
    }

    public static func strSlice(_ s: String, _ a: Int64, _ b: Int64) -> String? {
        let u = Array(s.unicodeScalars)
        guard a >= 0, b >= a, b <= Int64(u.count) else { return nil }
        return fromScalars(Array(u[Int(a)..<Int(b)]))
    }

    public static func strIndexOf(_ s: String, _ sub: String) -> Int64? {
        scalarIndex(s, sub).map(Int64.init)
    }

    /// Matches Rust's `{:?}` and Python's `repr` on a float: shortest form that
    /// round-trips, with a decimal point always present.
    public static func fmtF64(_ x: Double) -> String {
        let s = String(x)
        return s.contains(".") || s.contains("e") || s.contains("n") || s.contains("i") ? s : s + ".0"
    }

    public static func toI64(_ s: String) -> Int64? { Int64(trim(s)) }
    public static func toF64(_ s: String) -> Double? { Double(trim(s)) }
    public static func toI32(_ n: Int64) -> Int32? { Int32(exactly: n) }

    /// Out-of-range saturates rather than failing, which is what the Rust
    /// backend's `as i64` cast does. Only NaN and infinity are `none`.
    public static func fToI(_ x: Double) -> Int64? {
        if x.isNaN || x.isInfinite { return nil }
        let t = x.rounded(.towardZero)
        if t <= -9223372036854775808.0 { return Int64.min }
        if t >= 9223372036854775807.0 { return Int64.max }
        return Int64(t)
    }

    private static func isSpace(_ u: Unicode.Scalar) -> Bool {
        u == " " || u == "\t" || u == "\n" || u == "\r" || u == "\u{0B}" || u == "\u{0C}"
    }

    private static func fromScalars(_ u: [Unicode.Scalar]) -> String {
        String(String.UnicodeScalarView(u))
    }

    private static func scalarIndex(_ s: String, _ sub: String) -> Int? {
        let u = Array(s.unicodeScalars)
        let p = Array(sub.unicodeScalars)
        if p.isEmpty { return 0 }
        if p.count > u.count { return nil }
        for i in 0...(u.count - p.count) where Array(u[i..<(i + p.count)]) == p { return i }
        return nil
    }

    // MARK: lists

    public static func at<T>(_ xs: [T], _ i: Int64) -> T? {
        i >= 0 && i < Int64(xs.count) ? xs[Int(i)] : nil
    }
    public static func tail<T>(_ xs: [T]) -> [T]? { xs.isEmpty ? nil : Array(xs.dropFirst()) }

    public static func listSlice<T>(_ xs: [T], _ a: Int64, _ b: Int64) -> [T]? {
        guard a >= 0, b >= a, b <= Int64(xs.count) else { return nil }
        return Array(xs[Int(a)..<Int(b)])
    }

    public static func indexOf<T: Equatable>(_ xs: [T], _ x: T) -> Int64? {
        xs.firstIndex(of: x).map(Int64.init)
    }

    public static func sortBy<T, K: Comparable>(_ f: (T) -> K, _ xs: [T]) -> [T] {
        xs.sorted { f($0) < f($1) }
    }

    public static func range(_ a: Int64, _ b: Int64) -> [Int64] { a >= b ? [] : Array(a..<b) }

    public static func zip<A, B>(_ a: [A], _ b: [B]) -> [ASPair<A, B>] {
        Swift.zip(a, b).map { ASPair($0, $1) }
    }

    public static func sum<T: AdditiveArithmetic>(_ xs: [T]) -> T { xs.reduce(.zero, +) }

    // MARK: maps
    //
    // Iteration is sorted by key. The specification orders map-keys/values/pairs,
    // Swift's Dictionary is unordered, and an unspecified order would make the
    // backends disagree on identical input.

    public static func mGet<K: Hashable, V>(_ m: [K: V], _ k: K) -> V? { m[k] }

    public static func mSet<K: Hashable, V>(_ m: [K: V], _ k: K, _ v: V) -> [K: V] {
        var out = m
        out[k] = v
        return out
    }

    public static func mDel<K: Hashable, V>(_ m: [K: V], _ k: K) -> [K: V] {
        var out = m
        out.removeValue(forKey: k)
        return out
    }

    public static func mKeys<K: Hashable & Comparable, V>(_ m: [K: V]) -> [K] { m.keys.sorted() }

    public static func mValues<K: Hashable & Comparable, V>(_ m: [K: V]) -> [V] {
        m.keys.sorted().map { m[$0]! }
    }

    public static func mPairs<K: Hashable & Comparable, V>(_ m: [K: V]) -> [ASPair<K, V>] {
        m.keys.sorted().map { ASPair($0, m[$0]!) }
    }

    public static func mFrom<K: Hashable, V>(_ ps: [ASPair<K, V>]) -> [K: V] {
        var out: [K: V] = [:]
        for p in ps { out[p.first] = p.second }
        return out
    }

    // MARK: option and result

    public static func isOk<T, E>(_ r: ASResult<T, E>) -> Bool {
        if case .ok = r { return true }
        return false
    }

    public static func resOr<T, E>(_ r: ASResult<T, E>, _ d: T) -> T {
        if case .ok(let v) = r { return v }
        return d
    }

    public static func resMap<A, B, E>(_ f: (A) -> B, _ r: ASResult<A, E>) -> ASResult<B, E> {
        switch r {
        case .ok(let v): return .ok(f(v))
        case .err(let e): return .err(e)
        }
    }

    public static func resMapErr<T, E, F>(_ f: (E) -> F, _ r: ASResult<T, E>) -> ASResult<T, F> {
        switch r {
        case .ok(let v): return .ok(v)
        case .err(let e): return .err(f(e))
        }
    }

    public static func optToRes<T, E>(_ o: T?, _ e: E) -> ASResult<T, E> {
        if let v = o { return .ok(v) }
        return .err(e)
    }

    public static func resToOpt<T, E>(_ r: ASResult<T, E>) -> T? {
        if case .ok(let v) = r { return v }
        return nil
    }

    /// The `try` form: yields the ok value, or throws the err value to the
    /// enclosing function's catch.
    public static func unwrap<T, E>(_ r: ASResult<T, E>) throws(ASThrown<E>) -> T {
        switch r {
        case .ok(let v): return v
        case .err(let e): throw ASThrown(e)
        }
    }
}
