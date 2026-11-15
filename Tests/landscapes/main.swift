import Foundation

let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fingerprints.txt")
var known: [String: String] = [:]
for line in ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n") {
  let p = line.split(separator: " ", maxSplits: 1)
  if p.count == 2 { known[String(p[1])] = String(p[0]) }
}
var failed = 0
for v in views {
  guard let k = known[v.name] else { print("FAILED: no fingerprint for \(v.name)"); failed += 1; continue }
  if v.fingerprint != k { print("FAILED: the landscape of \(v.name) has changed"); failed += 1 }
}
print(failed == 0 ? "ok: \(views.count) landscapes as they were" : "\(failed) of \(views.count) landscapes differ")
exit(failed == 0 ? 0 : 1)
