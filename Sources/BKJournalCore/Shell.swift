import Foundation

public struct ShellOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    /// Süre dolduğu için süreç sonlandırıldıysa true.
    public let timedOut: Bool

    public var succeeded: Bool { status == 0 && !timedOut }
}

public enum Shell {
    /// Bir süreci çalıştırır, çıktısını toplar. Süre dolarsa süreci sonlandırır.
    @discardableResult
    public static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: URL? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval = 30
    ) -> ShellOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ShellOutput(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        let timedOut = Flag()
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning {
                timedOut.set()
                process.terminate()
            }
        }
        timer.resume()

        // stderr ayrı iş parçacığında okunur; aksi halde dolan bir boru süreci kilitleyebilir.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        timer.cancel()

        return ShellOutput(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errBox.get(), as: UTF8.self),
            timedOut: timedOut.isSet
        )
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ new: Data) { lock.lock(); data = new; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}
