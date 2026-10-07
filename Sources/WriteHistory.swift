import Foundation
import Darwin

/// The last completed write attempt, shared by the app's diagnostics and its local CLI.
/// This is operational history, not a preference: never export or sync this file.
struct WriteHistoryRecord: Codable, Equatable {
    let schemaVersion: Int
    let completedAt: String
    let action: String
    let succeeded: Bool
    let lastEngineLog: String
    let lastWriteError: String?
    let overall: String?

    init(action: String, succeeded: Bool, lastEngineLog: String, lastWriteError: String?,
         overall: String? = nil, completedAt: Date = Date()) {
        schemaVersion = 1
        self.completedAt = ISO8601DateFormatter().string(from: completedAt)
        self.action = action
        self.succeeded = succeeded
        self.lastEngineLog = lastEngineLog
        self.lastWriteError = lastWriteError
        self.overall = overall
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, completedAt, action, succeeded, lastEngineLog, lastWriteError, overall
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(action, forKey: .action)
        try container.encode(succeeded, forKey: .succeeded)
        try container.encode(lastEngineLog, forKey: .lastEngineLog)
        // Explicit nulls let CLI consumers distinguish a successful write from a missing field.
        try container.encode(lastWriteError, forKey: .lastWriteError)
        try container.encode(overall, forKey: .overall)
    }
}

/// A read never creates directories or changes permissions. A write replaces one private file
/// atomically; an existing open reader keeps the complete previous record until it closes.
struct WriteHistoryStore {
    let recordURL: URL

    static var defaultRecordURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unrevoke/Logs/last-write.json")
    }

    /// Fixture apps and helper executables must opt in with their own disposable URL.
    static func forProductBundle(_ bundle: Bundle = .main) -> WriteHistoryStore? {
        bundle.bundleIdentifier == "io.github.zengtianli.unrevoke" ? WriteHistoryStore() : nil
    }

    init(recordURL: URL = WriteHistoryStore.defaultRecordURL) {
        self.recordURL = recordURL
    }

    func load() throws -> WriteHistoryRecord? {
        let directory = open(recordURL.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        defer { close(directory) }
        let file = openat(directory, recordURL.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        defer { close(file) }
        var attributes = stat()
        guard fstat(file, &attributes) == 0 else { throw posixError() }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        let record = try JSONDecoder().decode(WriteHistoryRecord.self, from: data)
        guard record.schemaVersion == 1 else {
            throw CocoaError(.coderReadCorrupt)
        }
        return record
    }

    func save(_ record: WriteHistoryRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        let parent = recordURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let directory = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw posixError() }
        defer { close(directory) }
        guard fchmod(directory, 0o700) == 0 else { throw posixError() }

        let temporary = ".last-write-\(UUID().uuidString).tmp"
        let file = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard file >= 0 else { throw posixError() }
        defer {
            close(file)
            unlinkat(directory, temporary, 0)
        }
        guard fchmod(file, 0o600) == 0 else { throw posixError() }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fsync(file) == 0 else { throw posixError() }
        guard renameat(directory, temporary, directory, recordURL.lastPathComponent) == 0 else {
            throw posixError()
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
