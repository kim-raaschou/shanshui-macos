import CryptoKit
import Foundation

// The landscapes, held fast: the generator must write exactly the drawings it
// wrote when it was checked, character for character, against the original
// JavaScript of {Shan, Shui}* and of omarchy-shanshui's gerar.js. Their
// fingerprints (SHA-256) are in fingerprints.txt, one view a line.
//
//   make landscapes     every view against its fingerprint
//
// A view is a seed, a place, a size and, for one of them, colours; its text is
// everything the app can ask of it: the whole picture and its delay, and the
// layers of three and of two.

struct View {
  let seed: String, cursor: Double, w: Int, h: Int
  var ink: String?, paper: String?
  var name: String { [seed, jsString(cursor), String(w), String(h), ink ?? "-", paper ?? "-"].joined(separator: " ") }

  var text: String {
    let d = Drawing(seed: seed, cursor: cursor, w: w, h: h, ink: ink, paper: paper)
    return [d.picture(nil, 3), d.delay(nil, 3), d.picture(0, 3), d.picture(1, 3), d.picture(2, 3), d.delay(0, 3), d.delay(1, 3), d.delay(2, 3),
            d.picture(0, 2), d.picture(1, 2), d.delay(0, 2), d.delay(1, 2)].joined(separator: "\n")
  }

  var fingerprint: String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

let views: [View] = {
  var v: [View] = []
  // The start of a landscape, a place far along, one left of 0, and strips as the app cuts them.
  for seed in ["1", "42", "1794744564642"] {
    v.append(View(seed: seed, cursor: 0, w: 1728, h: 1117))
    v.append(View(seed: seed, cursor: 260000, w: 2560, h: 1440))
    v.append(View(seed: seed, cursor: -900, w: 1000, h: 700))
    v.append(View(seed: seed, cursor: 57 * 700 * 3456 / 2234, w: 3456, h: 2234))
  }
  // Many seeds and places.
  for k in 0..<24 {
    let cursor = Double((k * 7919) % 300000 - 3000) + 0.5 * Double(k % 2)
    v.append(View(seed: String(1794000000000 + k * 104729), cursor: cursor, w: [1728, 2560, 3456, 1470][k % 4], h: [1117, 1440, 2234, 956][k % 4]))
  }
  v.append(View(seed: "7", cursor: 1200, w: 800, h: 600, ink: "#2b2b2b", paper: "f2e8d5"))
  return v
}()
