import Foundation

protocol LocalChatStoring: Sendable {
    func load() async throws -> [LocalChatConversation]
    func save(_ conversations: [LocalChatConversation]) async throws
}

actor MemoryLocalChatStore: LocalChatStoring {
    private var conversations: [LocalChatConversation]
    init(_ conversations: [LocalChatConversation] = []) { self.conversations = conversations }
    func load() -> [LocalChatConversation] { conversations }
    func save(_ conversations: [LocalChatConversation]) { self.conversations = conversations }
}

actor JSONLocalChatStore: LocalChatStoring {
    static let maximumBytes = 1_048_576
    private struct File: Codable { var version: Int; var conversations: [LocalChatConversation] }
    let url: URL
    private var validated = false
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sieghart/Chat/history.json")) { self.url = url }
    func load() throws -> [LocalChatConversation] {
        guard FileManager.default.fileExists(atPath: url.path) else { validated = true; return [] }
        let reader = try FileHandle(forReadingFrom: url); defer { try? reader.close() }
        let data = try reader.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.version == 1, Self.valid(file.conversations) else { throw CocoaError(.fileReadCorruptFile) }
        validated = true
        return file.conversations
    }
    func save(_ conversations: [LocalChatConversation]) throws {
        if !validated { _ = try load() }
        guard Self.valid(conversations) else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = try JSONEncoder().encode(File(version: 1, conversations: conversations))
        guard data.count <= Self.maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func valid(_ values: [LocalChatConversation]) -> Bool {
        values.count <= 20 && Set(values.map(\.id)).count == values.count && values.allSatisfy {
            !$0.id.isEmpty && $0.title.utf8.count <= 512 && $0.messages.count <= 60 &&
            Set($0.messages.map(\.id)).count == $0.messages.count && $0.messages.allSatisfy { !$0.id.isEmpty && $0.text.utf8.count <= 16_384 }
        }
    }
}
