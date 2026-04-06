import Foundation

/// Represents a single diff operation.
public struct Diff: Equatable {
    public enum Operation: Int, Equatable {
        case delete = -1
        case equal = 0
        case insert = 1
    }

    public var operation: Operation
    public var text: String

    public init(_ operation: Operation, _ text: String) {
        self.operation = operation
        self.text = text
    }
}

extension Diff: CustomStringConvertible {
    public var description: String {
        let prefix: String
        switch operation {
        case .delete: prefix = "-"
        case .equal:  prefix = "="
        case .insert: prefix = "+"
        }
        return "\(prefix)[\(text)]"
    }
}
