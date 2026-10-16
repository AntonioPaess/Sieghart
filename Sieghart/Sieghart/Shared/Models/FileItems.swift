import Foundation

struct FileReference: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var bookmark: Data
    var name: String
    var pathHint: String
    var resourceID: String
    var isDirectory: Bool
    var addedAt = Date()
}

struct WatchedFolder: Identifiable, Codable, Equatable, Sendable {
    var reference: FileReference
    var id: UUID { reference.id }
}

struct DownloadFile: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(folderID.uuidString)/\(name)" }
    var folderID: UUID
    var name: String
    var bytes: Int64
    var modifiedAt: Date
    var partial: Bool
    var readyAfterPartial = false
    var available: Bool
    var resourceID = ""
    var signature: String { "\(resourceID):\(bytes):\(modifiedAt.timeIntervalSince1970)" }
    var stateTitle: String { !available ? "Unavailable" : partial ? "Partial file · size only" : readyAfterPartial ? "Download ready" : "Available file" }
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp"]
    var finalName: String { partial ? (name as NSString).deletingPathExtension : name }
}

struct FilesSnapshot: Codable, Sendable {
    var shelf: [FileReference] = []
    var folders: [WatchedFolder] = []
    var recent: [DownloadFile] = []
}

struct FileDetails: Equatable, Sendable {
    var name: String
    var bytes: Int64
    var modifiedAt: Date
    var resourceID: String
    var isDirectory: Bool
}

enum FileConflictPolicy: String, CaseIterable, Sendable { case cancel = "Stop on conflict", keepBoth = "Keep both" }
enum FileOperationKind: String, Sendable { case move = "Move", rename = "Rename", install = "Install" }
struct ReviewedFileOperation: Identifiable, Sendable {
    var id = UUID()
    var kind: FileOperationKind
    var sources: [FileReference]
    var details: [FileDetails]
    var destination: FileReference
    var targetNames: [String]
}

enum FileToolError: Error, LocalizedError, Equatable {
    case missing, access, invalidName, conflict(String), changed, invalidDestination, cancelled, unsupported, message(String)
    var errorDescription: String? {
        switch self {
        case .missing: "This file moved or is missing. Choose it again to reconnect."
        case .access: "Access is unavailable. Choose this file or folder again."
        case .invalidName: "Enter a file name without a path or control characters."
        case .conflict(let name): "\(name) already exists. Choose Keep both or another destination."
        case .changed: "The files changed after this review. Prepare the action again."
        case .invalidDestination: "Choose a writable destination outside the source folder."
        case .cancelled: "Cancelled."
        case .unsupported: "This file type is not supported here."
        case .message(let text): text
        }
    }
}
