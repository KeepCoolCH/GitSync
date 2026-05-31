import Foundation

struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        if stderr.isEmpty { return stdout }
        if stdout.isEmpty { return stderr }
        return stdout + "\n" + stderr
    }
}

struct ConflictSuggestion: Identifiable {
    let id: UUID = UUID()
    let file: String
    let statusCode: String
    let suggestion: String
}

enum ConflictStrategy {
    case ours
    case theirs
}

enum FolderPickerTarget {
    case repository
    case cloneDestination
    case projectParent
}

struct GitHubRepo: Decodable, Identifiable {
    let id: Int
    let name: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
    }
}

struct GitHubUser: Decodable {
    let login: String
}

struct CreateRepoPayload: Encodable {
    let name: String
    let auto_init: Bool
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case auto_init
        case isPrivate = "private"
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case repository
    case sync
    case tags
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .repository: return "Repository"
        case .sync: return "Synchronization"
        case .tags: return "Tags"
        case .logs: return "Status & Logs"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2.fill"
        case .repository: return "folder.fill"
        case .sync: return "arrow.triangle.2.circlepath"
        case .tags: return "tag.fill"
        case .logs: return "text.alignleft"
        }
    }
}

enum PullMode: String, CaseIterable, Identifiable {
    case merge
    case rebase
    case fastForwardOnly
    case rebaseAutostash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "Merge (git pull)"
        case .rebase: return "Rebase (--rebase)"
        case .fastForwardOnly: return "Fast-Forward only (--ff-only)"
        case .rebaseAutostash: return "Rebase + Autostash"
        }
    }

    var explanation: String {
        switch self {
        case .merge:
            return "Merge: Fetches remote changes and creates a merge commit when needed."
        case .rebase:
            return "Rebase: Fetches remote changes and reapplies your local commits on top."
        case .fastForwardOnly:
            return "Fast-Forward only: Updates only when no merge/rebase is required; otherwise it stops."
        case .rebaseAutostash:
            return "Rebase + Autostash: Like rebase, temporarily stashes uncommitted changes and restores them after."
        }
    }

    func pullArgs(branch: String) -> [String] {
        switch self {
        case .merge:
            return ["pull", "origin", branch]
        case .rebase:
            return ["pull", "--rebase", "origin", branch]
        case .fastForwardOnly:
            return ["pull", "--ff-only", "origin", branch]
        case .rebaseAutostash:
            return ["pull", "--rebase", "--autostash", "origin", branch]
        }
    }
}

