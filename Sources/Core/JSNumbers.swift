import Foundation

// The generator's numbers, as JavaScript has them: the landscape of a seed is
// the same as the original's only when every power and every printed number is.

/// Math.pow as JavaScriptCore computes it: a whole exponent up to 1000 by
/// repeated squaring, a half by the square root, and the C library otherwise.
func jsPow(_ x: Double, _ y: Double) -> Double {
  if y.isInfinite, abs(x) == 1 { return .nan }
  if y == 0.5 { return x == 0 ? 0 : (x == -.infinity ? .infinity : x.squareRoot()) }
  if y == -0.5 { return x == 0 ? .infinity : (x == -.infinity ? 0 : 1 / x.squareRoot()) }
  if y >= 0, y <= 1000, y == y.rounded(.towardZero) {
    var n = Int(y), r = 1.0, b = x
    while n != 0 {
      if n & 1 != 0 { r *= b }
      b *= b
      n >>= 1
    }
    return r
  }
  return pow(x, y)
}

/// A number as JavaScript prints it (Number::toString).
func jsString(_ v: Double) -> String {
  if v.isNaN { return "NaN" }
  if v == 0 { return "0" }
  if v.isInfinite { return v < 0 ? "-Infinity" : "Infinity" }
  if v < 0 { return "-" + jsString(-v) }
  // Swift prints the same shortest digits; only where the point goes differs.
  var digits = "", exp = 0
  let d = "\(v)"
  let parts = d.split(separator: "e")
  if parts.count == 2 { exp = Int(parts[1])! }
  let m = parts[0].split(separator: ".", omittingEmptySubsequences: false)
  var whole = String(m[0]), frac = m.count > 1 ? String(m[1]) : ""
  if frac == "0" { frac = "" }
  // v = 0.digits * 10^n
  var n = whole.count + exp
  digits = whole + frac
  if whole == "0" {
    let lead = frac.prefix { $0 == "0" }.count
    digits = String(frac.dropFirst(lead)); n = exp - lead
  }
  while digits.hasSuffix("0") { digits.removeLast() }
  whole = ""
  let k = digits.count
  if k <= n, n <= 21 { return digits + String(repeating: "0", count: n - k) }
  if 0 < n, n <= 21 { return digits.prefix(n) + "." + digits.dropFirst(n) }
  if -6 < n, n <= 0 { return "0." + String(repeating: "0", count: -n) + digits }
  let e = n - 1, sign = e < 0 ? "-" : "+"
  return digits.prefix(1) + (k > 1 ? "." + digits.dropFirst(1) : "") + "e" + sign + String(abs(e))
}

/// Number.prototype.toFixed: of two as near, the one farther from zero.
func jsFixed(_ v: Double, _ f: Int) -> String {
  var out = [UInt8]()
  jsFixed(v, f, into: &out)
  return String(decoding: out, as: UTF8.self)
}

private let tens: [Double] = [1, 10, 100, 1000, 10000, 100000, 1000000]

/// The same, added to text that is being put together.
func jsFixed(_ v: Double, _ f: Int, into out: inout [UInt8]) {
  let a = abs(v)
  guard f < tens.count, a * 1e6 < 4e15 else {
    out.append(contentsOf: (v.isNaN ? "NaN" : jsFixedSlow(v, f)).utf8)
    return
  }
  // a * 10^f exactly, as two doubles (hi + lo), and the whole number nearest
  // to it: the part after the point is hi's own, a little more or less by lo.
  let hi = a * tens[f], lo = (-hi).addingProduct(a, tens[f])
  var n = hi.rounded(.down)
  let r = hi - n
  if r > 0.5 || (r == 0.5 && lo >= 0) { n += 1 }
  var digits = [UInt8](repeating: 48, count: 24)
  var i = 24, m = UInt64(n), k = 0
  repeat {
    if k == f, f > 0 { i -= 1; digits[i] = 46 }
    i -= 1; digits[i] = UInt8(48 + m % 10); m /= 10; k += 1
  } while m > 0 || k <= f
  if v < 0 { i -= 1; digits[i] = 45 }
  out.append(contentsOf: digits[i...])
}

private func jsFixedSlow(_ v: Double, _ f: Int) -> String {
  if abs(v) >= 1e21 { return jsString(v) }
  if v == 0 { return f > 0 ? "0." + String(repeating: "0", count: f) : "0" }
  // The C library rounds the exact value, as JavaScript does, but takes the
  // even one of two as near. Two are as near only when the number has no more
  // than f + 1 binary places; then f + 1 decimals print it exactly.
  let scaled = v * Double(1 << (f + 1))
  if scaled == scaled.rounded() {
    var s = String(format: "%.\(f + 1)f", v)
    if s.hasSuffix("5") {
      var digits = Array(s.utf8)
      digits.removeLast()
      var i = digits.count - 1
      while i >= 0 {
        if digits[i] == 57 { digits[i] = 48; i -= 1 } else if digits[i] >= 48, digits[i] < 57 { digits[i] += 1; break } else { i -= 1; continue }
      }
      s = String(decoding: digits, as: UTF8.self)
      if i < 0 { s = v < 0 ? "-1" + s.dropFirst() : "1" + s }
      return f == 0 ? String(s.dropLast()) : s
    }
  }
  return String(format: "%.\(f)f", v)
}

/// Math.min and Math.max: not a number when either is.
func jsMin(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : min(a, b) }
func jsMax(_ a: Double, _ b: Double) -> Double { a.isNaN || b.isNaN ? .nan : max(a, b) }
