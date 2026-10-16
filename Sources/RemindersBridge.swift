import Foundation

enum BridgeError: Error {
    case launchFailed(String)
    case osascript(String, Int32)
    case emptyOutput

    var message: String {
        switch self {
        case .launchFailed(let detail):
            return "无法启动 osascript：\(detail)"
        case .osascript(let text, let code):
            let lowered = text.lowercased()
            if text.contains("-1743") || lowered.contains("not allowed") || lowered.contains("not authorized") {
                return "未授权自动化：请在 系统设置 → 隐私与安全性 → 自动化 里允许 DeskMinder 控制「提醒事项」"
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "osascript 退出码 \(code)：\(trimmed.isEmpty ? "无错误输出" : trimmed)"
        case .emptyOutput:
            return "「提醒事项」没有返回 id"
        }
    }
}

/// 通过 osascript 读写 Apple「提醒事项」。
/// 脚本与之前在 DSH 插件里验证过的一致：日期逐段赋值，不依赖系统 locale 的日期格式。
enum RemindersBridge {
    private static let queue = DispatchQueue(label: "deskminder.reminders")

    static func escape(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    /// 建一条带到期日的提醒，回调返回它的 id。
    static func create(title: String, dueDate: Date, completion: @escaping (Result<String, BridgeError>) -> Void) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        let script = [
            "set theTitle to \"\(escape(title))\"",
            "set theDate to (current date)",
            "set day of theDate to 1",
            "set year of theDate to \(parts.year ?? 2026)",
            "set month of theDate to \(parts.month ?? 1)",
            "set day of theDate to \(parts.day ?? 1)",
            "set time of theDate to 0",
            "tell application \"Reminders\"",
            "  set theList to default list",
            "  set r to make new reminder at end of theList with properties {name:theTitle, due date:theDate}",
            "  return id of r",
            "end tell",
        ].joined(separator: "\n")

        run(script) { result in
            switch result {
            case .success(let output):
                let id = output.trimmingCharacters(in: .whitespacesAndNewlines)
                completion(id.isEmpty ? .failure(.emptyOutput) : .success(id))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// 按 id 把提醒标记为已完成。
    static func complete(reminderID: String, completion: @escaping (Bool) -> Void) {
        let script = [
            "tell application \"Reminders\"",
            "  set r to (first reminder whose id is \"\(escape(reminderID))\")",
            "  set completed of r to true",
            "end tell",
        ].joined(separator: "\n")

        run(script) { result in
            switch result {
            case .success:
                completion(true)
            case .failure:
                completion(false)
            }
        }
    }

    private static func run(_ script: String, completion: @escaping (Result<String, BridgeError>) -> Void) {
        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.launchFailed(error.localizedDescription)))
                }
                return
            }

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let stdout = String(data: outData, encoding: .utf8) ?? ""
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            let status = process.terminationStatus

            DispatchQueue.main.async {
                if status == 0 {
                    completion(.success(stdout))
                } else {
                    completion(.failure(.osascript(stderr.isEmpty ? stdout : stderr, status)))
                }
            }
        }
    }
}
