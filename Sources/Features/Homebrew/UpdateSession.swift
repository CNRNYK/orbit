import Foundation

/// A single broker and controlling terminal for one reviewed update queue.
final class UpdateAuthorizationSession: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let worker = DispatchQueue(label:"orbit.update-session")
    private let brew: String
    private let helper: URL
    private var started = false
    private var closed = false

    init?(brew: String) {
        guard ["/opt/homebrew/bin/brew","/usr/local/bin/brew"].contains(brew),
              let helper = Bundle.main.url(forResource:"OrbitUpdateSession",withExtension:nil),
              Bundle.main.url(forResource:"askpass",withExtension:"sh") != nil else { return nil }
        self.brew = brew; self.helper = helper
    }

    private func read(_ count: Int) throws -> Data {
        var bytes = Data()
        while bytes.count < count {
            guard let chunk = try output.fileHandleForReading.read(upToCount:count-bytes.count), !chunk.isEmpty else {
                throw CocoaError(.fileReadUnknown)
            }
            bytes.append(chunk)
        }
        return bytes
    }

    private func header() throws -> (UInt32,Int32) {
        let data = try read(8)
        return data.withUnsafeBytes { ($0.loadUnaligned(as:UInt32.self),$0.loadUnaligned(fromByteOffset:4,as:Int32.self)) }
    }

    func run(_ item: UpdateItem, log: @escaping @Sendable (String) -> Void) async -> (Int32,String) {
        await withCheckedContinuation { continuation in
            worker.async {
                do {
                    guard !self.closed else { throw CocoaError(.fileReadUnknown) }
                    if !self.started {
                        self.process.executableURL = self.helper
                        self.process.arguments = [self.brew]
                        self.process.environment = BrewRunner.environment()
                        self.process.standardInput = self.input
                        self.process.standardOutput = self.output
                        self.process.standardError = FileHandle.nullDevice
                        try self.process.run()
                        self.started = true
                        let ready = try self.header()
                        guard ready.0 == 0, ready.1 == 0 else { throw CocoaError(.fileReadCorruptFile) }
                    }
                    let token = item.package.operationToken
                    guard token.range(of:#"^[A-Za-z0-9@+._][A-Za-z0-9@+._/-]{0,480}$"#,options:.regularExpression) != nil else {
                        continuation.resume(returning:(125,"Invalid Homebrew update token.")); return
                    }
                    let request = "\(item.package.cask ? "c" : "f")\t\(token)\n"
                    try self.input.fileHandleForWriting.write(contentsOf:Data(request.utf8))
                    var result = Data()
                    while true {
                        let (type,value) = try self.header()
                        if type == 2 { continuation.resume(returning:(value,String(decoding:result,as:UTF8.self))); return }
                        guard type == 1, value > 0, value <= 4096 else { throw CocoaError(.fileReadCorruptFile) }
                        let chunk = try self.read(Int(value))
                        result.append(chunk); log(String(decoding:chunk,as:UTF8.self))
                    }
                } catch {
                    self.finish()
                    continuation.resume(returning:(125,"The shared Homebrew update session could not continue."))
                }
            }
        }
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
        if started { process.waitUntilExit() }
    }

    func close() { worker.async { self.finish() } }
}
