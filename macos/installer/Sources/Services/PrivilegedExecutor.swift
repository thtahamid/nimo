import Foundation

protocol PrivilegedExecuting {
    func run(_ script: String) throws
}

struct PrivilegedCancelled: LocalizedError {
    var errorDescription: String? { "Administrator authorization was cancelled." }
}

struct PrivilegedFailure: LocalizedError {
    let exitCode: Int
    let message: String
    var errorDescription: String? {
        message.isEmpty
            ? "Privileged command failed (exit \(exitCode))."
            : message
    }
}

/// Runs shell scripts via `osascript`'s `do shell script ... with administrator privileges`.
/// This triggers the standard macOS admin-password prompt and executes the script as root,
/// which bypasses the App Management protection on /Applications.
final class AppleScriptPrivilegedExecutor: PrivilegedExecuting {
    private let prompt: String

    init(prompt: String = "Nimo needs administrator access to modify Discord in /Applications.") {
        self.prompt = prompt
    }

    func run(_ script: String) throws {
        let source = """
        do shell script \(Self.applescriptString(script)) \
        with administrator privileges \
        with prompt \(Self.applescriptString(prompt))
        """

        guard let apple = NSAppleScript(source: source) else {
            throw PrivilegedFailure(exitCode: -1, message: "Failed to compile AppleScript.")
        }

        var errorInfo: NSDictionary?
        apple.executeAndReturnError(&errorInfo)

        if let errorInfo = errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
            let msg = (errorInfo[NSAppleScript.errorMessage] as? String) ?? ""
            if code == -128 { throw PrivilegedCancelled() }
            throw PrivilegedFailure(exitCode: code, message: msg)
        }
    }

    private static func applescriptString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}

/// Non-privileged executor used by unit tests — runs the script locally via /bin/bash.
final class LocalShellExecutor: PrivilegedExecuting {
    func run(_ script: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", script]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw PrivilegedFailure(exitCode: Int(proc.terminationStatus), message: msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
