import Foundation

// Minimal test harness — no XCTest needed
var totalTests = 0
var passedTests = 0
var failedTests: [(String, String)] = []

func test(_ name: String, _ body: () throws -> Void) {
    totalTests += 1
    do {
        try body()
        passedTests += 1
        print("  \u{2713} \(name)")
    } catch {
        failedTests.append((name, "\(error)"))
        print("  \u{2717} \(name): \(error)")
    }
}

struct AssertionError: Error, CustomStringConvertible {
    let description: String
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw AssertionError(description: "assertEqual failed: \(a) != \(b) at \(file):\(line)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard condition else {
        throw AssertionError(description: "assertTrue failed\(message.isEmpty ? "" : ": \(message)") at \(file):\(line)")
    }
}

func assertNotNil<T>(_ value: T?, file: String = #file, line: Int = #line) throws {
    guard value != nil else {
        throw AssertionError(description: "assertNotNil failed at \(file):\(line)")
    }
}

func assertThrows<T>(_ body: () throws -> T, file: String = #file, line: Int = #line) throws {
    do {
        _ = try body()
        throw AssertionError(description: "Expected error but none thrown at \(file):\(line)")
    } catch is AssertionError {
        throw AssertionError(description: "Expected error but none thrown at \(file):\(line)")
    } catch {
        // Expected
    }
}

func assertGreaterThan<T: Comparable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    guard a > b else {
        throw AssertionError(description: "assertGreaterThan failed: \(a) <= \(b) at \(file):\(line)")
    }
}

func printSummary() {
    print("\n\(passedTests)/\(totalTests) passed, \(failedTests.count) failed")
    if !failedTests.isEmpty {
        print("\nFailed tests:")
        for (name, error) in failedTests {
            print("  - \(name): \(error)")
        }
        exit(1)
    }
}
