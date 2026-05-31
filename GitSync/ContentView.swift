import SwiftUI
import Foundation

struct ContentView: View {
    static let defaultGitignoreTemplate = """
# Xcode User Data
xcuserdata/
**/xcuserdata/
*.xcuserdatad
*.xcuserstate

# Build Folders
DerivedData/
build/

# macOS
.DS_Store

# Swift Package Manager
.build/
"""

    @Environment(\.openURL) var openURL
    @State var repositoryPath: String = ""
    @State var remoteURL: String = ""
    @State var cloneURL: String = ""
    @State var cloneDestinationPath: String = ""
    @State var commitMessage: String = "Update from GitSync"
    @State var branchName: String = "main"
    @State var pullMode: PullMode = .rebase
    @State var availableBranches: [String] = []
    @State var availableTags: [String] = []
    @State var selectedTagName: String = ""
    @State var tagNameInput: String = ""
    @State var tagMessageInput: String = ""
    @State var gitHubToken: String = ""
    @State var gitHubRepos: [GitHubRepo] = []
    @State var selectedGitHubRepoFullName: String = ""

    @State var newProjectName: String = "MyNewRepo"
    @State var newProjectParentPath: String = ""
    @State var publishRemoteURL: String = ""
    @State var createEmptyRepository: Bool = true

    @State var gitStatusOutput: String = ""
    @State var logOutput: String = ""
    @State var isRunningCommand: Bool = false
    @State var conflictSuggestions: [ConflictSuggestion] = []

    @State var showFolderPicker: Bool = false
    @State var folderPickerTarget: FolderPickerTarget = .repository
    @State var gitExecutablePath: String = ""
    @State var showCloneWindow: Bool = false
    @State var showNewProjectWindow: Bool = false
    @State var repoFolderAccessURL: URL?
    @State var cloneFolderAccessURL: URL?
    @State var projectParentAccessURL: URL?
    @State var selectedSection: AppSection = .dashboard
    @AppStorage("repoPathMappings") var repoPathMappingsStore: String = "{}"
    @AppStorage("lastSelectedGitHubRepo") var lastSelectedGitHubRepo: String = ""
    @State var showTokenEditor: Bool = false
    @State var showSSHEmailEditor: Bool = false
    @State var showGitignoreEditor: Bool = false
    @State var showQuickRepoPicker: Bool = false
    @State var isWaitingForCreatedRepo: Bool = false
    @State var pendingCreatedRepoFullName: String = ""
    @State var createdRepoWaitTask: Task<Void, Never>?
    @State var isCreatingProject: Bool = false
    @State var isRunningSyncAction: Bool = false
    @State var syncActionLabel: String = ""
    @State var gitignoreDraft: String = ContentView.defaultGitignoreTemplate
    @State var sshKeyEmail: String = ""
    @State var sshPublicKey: String = ""

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("GitSync")
        } detail: {
            NavigationStack {
                ZStack {
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.18), Color.blue.opacity(0.14), Color.mint.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            activeContextBar
                            sectionContent
                        }
                        .padding(16)
                    }
                }
                .navigationTitle(selectedSection.title)
            }
        }
        .onAppear {
            gitExecutablePath = resolveGitExecutablePath()
            if gitExecutablePath.isEmpty {
                appendLog("No direct git binary found. Install Git via Homebrew or Command Line Tools.")
            } else {
                appendLog("Git binary: \(gitExecutablePath)")
            }
            gitHubToken = loadGitHubTokenFromKeychain() ?? ""
            if !lastSelectedGitHubRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedGitHubRepoFullName = lastSelectedGitHubRepo
            }
            if !gitHubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runAsync {
                    await loadGitHubRepositories()
                }
            }
        }
        .onDisappear {
            releaseSecurityScope(for: &repoFolderAccessURL)
            releaseSecurityScope(for: &cloneFolderAccessURL)
            releaseSecurityScope(for: &projectParentAccessURL)
            createdRepoWaitTask?.cancel()
        }
        .onChange(of: selectedGitHubRepoFullName) { _, newValue in
            guard !newValue.isEmpty else { return }
            lastSelectedGitHubRepo = newValue
            remoteURL = "git@github.com:\(newValue).git"
            if let savedPath = repoPathMappings()[newValue], !savedPath.isEmpty {
                repositoryPath = savedPath
                runAsync {
                    _ = await setRemoteOrigin(repoPath: repositoryPath, remote: remoteURL)
                    await refreshBranches()
                    await refreshTags()
                }
            } else {
                repositoryPath = ""
                availableBranches = []
                availableTags = []
                selectedTagName = ""
                tagNameInput = ""
                tagMessageInput = ""
                branchName = "main"
            }
        }
        .onChange(of: gitHubToken) { _, newValue in
            saveGitHubTokenToKeychain(newValue)
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runAsync {
                    await loadGitHubRepositories()
                }
            } else {
                gitHubRepos = []
                selectedGitHubRepoFullName = ""
                lastSelectedGitHubRepo = ""
            }
        }
        .sheet(isPresented: $showCloneWindow) {
            cloneSheetContent
        }
        .sheet(isPresented: $showNewProjectWindow) {
            newProjectSheetContent
        }
    }
}

#Preview {
    ContentView()
}
