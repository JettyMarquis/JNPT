import Foundation

/// Represents a patch — a set of diffs anchored at a position in the source text.
public struct Patch: Equatable {
    public var diffs: [Diff] = []
    public var start1: Int = 0
    public var start2: Int = 0
    public var length1: Int = 0
    public var length2: Int = 0

    public init() {}
}

extension Patch: CustomStringConvertible {
    public var description: String {
        let coords1 = length1 == 0 ? "\(start1),0"
            : length1 == 1 ? "\(start1 + 1)"
            : "\(start1 + 1),\(length1)"
        let coords2 = length2 == 0 ? "\(start2),0"
            : length2 == 1 ? "\(start2 + 1)"
            : "\(start2 + 1),\(length2)"

        var text = "@@ -\(coords1) +\(coords2) @@\n"
        for diff in diffs {
            switch diff.operation {
            case .insert: text += "+"
            case .delete: text += "-"
            case .equal:  text += " "
            }
            text += diff.text.encodingForPatch() + "\n"
        }
        return text
    }
}

// MARK: - Percent encoding for patch text format

extension String {
    /// Encode for patch text format — percent-encode special chars.
    func encodingForPatch() -> String {
        var result = ""
        for char in self {
            switch char {
            case "%":  result += "%25"
            case "\n": result += "%0A"
            case "\r": result += "%0D"
            default:   result.append(char)
            }
        }
        return result
    }

    /// Decode from patch text format.
    func decodingFromPatch() -> String {
        var result = ""
        var i = startIndex
        while i < endIndex {
            if self[i] == "%" && distance(from: i, to: endIndex) >= 3 {
                let hexStart = index(after: i)
                let hexEnd = index(hexStart, offsetBy: 2)
                let hex = String(self[hexStart..<hexEnd])
                if let code = UInt8(hex, radix: 16) {
                    result.append(Character(UnicodeScalar(code)))
                    i = hexEnd
                    continue
                }
            }
            result.append(self[i])
            i = index(after: i)
        }
        return result
    }
}
