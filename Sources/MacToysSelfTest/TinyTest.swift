import Foundation

/// Minimal test harness. XCTest ships with Xcode, not with the Command Line
/// Tools, so the suite is a plain executable: it runs every registered case,
/// prints a report and exits non-zero if anything failed.
final class TinyTest {
    struct Failure {
        let test: String
        let message: String
        let file: String
        let line: Int
    }

    private(set) var failures: [Failure] = []
    private(set) var assertions = 0
    private(set) var passedTests = 0
    private(set) var totalTests = 0
    private var currentTest = "<none>"
    private var currentFailed = false

    private var suite = ""

    func group(_ name: String) {
        suite = name
        print("\n\u{001B}[1m\(name)\u{001B}[0m")
    }

    func test(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        currentFailed = false
        totalTests += 1
        do {
            try body()
        } catch {
            currentFailed = true
            failures.append(Failure(test: name, message: "threw: \(error)", file: #file, line: #line))
        }
        if currentFailed {
            print("  \u{001B}[31m✗\u{001B}[0m \(name)")
        } else {
            passedTests += 1
            print("  \u{001B}[32m✓\u{001B}[0m \(name)")
        }
    }

    func expect(_ condition: Bool, _ message: @autoclosure () -> String = "expectation failed",
                file: String = #file, line: Int = #line) {
        assertions += 1
        if !condition {
            currentFailed = true
            failures.append(Failure(test: currentTest, message: message(), file: file, line: line))
        }
    }

    func equal<T: Equatable>(_ a: T, _ b: T, _ label: String = "",
                             file: String = #file, line: Int = #line) {
        assertions += 1
        if a != b {
            currentFailed = true
            let prefix = label.isEmpty ? "" : "\(label): "
            failures.append(Failure(test: currentTest,
                                    message: "\(prefix)expected \(b), got \(a)",
                                    file: file, line: line))
        }
    }

    func nearlyEqual(_ a: Double, _ b: Double, tolerance: Double = 0.5, _ label: String = "",
                     file: String = #file, line: Int = #line) {
        assertions += 1
        if abs(a - b) > tolerance {
            currentFailed = true
            let prefix = label.isEmpty ? "" : "\(label): "
            failures.append(Failure(test: currentTest,
                                    message: "\(prefix)expected \(b) ± \(tolerance), got \(a)",
                                    file: file, line: line))
        }
    }

    func report() -> Int32 {
        print("\n" + String(repeating: "─", count: 62))
        if failures.isEmpty {
            print("\u{001B}[32m\u{001B}[1mPASSED\u{001B}[0m  \(passedTests)/\(totalTests) tests, \(assertions) assertions")
            return 0
        }
        print("\u{001B}[31m\u{001B}[1mFAILED\u{001B}[0m  \(passedTests)/\(totalTests) tests passed, \(failures.count) failure(s), \(assertions) assertions\n")
        for f in failures {
            let file = (f.file as NSString).lastPathComponent
            print("  \u{001B}[31m•\u{001B}[0m [\(f.test)] \(f.message)")
            print("    at \(file):\(f.line)")
        }
        return 1
    }
}
