import SwiftUI
import Foundation
import Security
import AppKit

extension ContentView {
    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
    }

    func runAsync(_ operation: @escaping () async -> Void) {
        Task {
            await MainActor.run { isRunningCommand = true }
            await operation()
            await MainActor.run { isRunningCommand = false }
        }
    }

    func openFolderPanel(for target: FolderPickerTarget) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            let path = sanitizePath(url.path)
            switch target {
            case .repository:
                releaseSecurityScope(for: &repoFolderAccessURL)
                if url.startAccessingSecurityScopedResource() { repoFolderAccessURL = url }
                repositoryPath = path
                savePathMappingIfPossible(path: path)
            case .cloneDestination:
                releaseSecurityScope(for: &cloneFolderAccessURL)
                if url.startAccessingSecurityScopedResource() { cloneFolderAccessURL = url }
                cloneDestinationPath = path
            case .projectParent:
                releaseSecurityScope(for: &projectParentAccessURL)
                if url.startAccessingSecurityScopedResource() { projectParentAccessURL = url }
                newProjectParentPath = path
            }
        }
    }

    func handleFolderSelection(result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            let path = sanitizePath(url.path)
            switch folderPickerTarget {
            case .repository:
                releaseSecurityScope(for: &repoFolderAccessURL)
                if url.startAccessingSecurityScopedResource() { repoFolderAccessURL = url }
                repositoryPath = path
                savePathMappingIfPossible(path: path)
            case .cloneDestination:
                releaseSecurityScope(for: &cloneFolderAccessURL)
                if url.startAccessingSecurityScopedResource() { cloneFolderAccessURL = url }
                cloneDestinationPath = path
            case .projectParent:
                releaseSecurityScope(for: &projectParentAccessURL)
                if url.startAccessingSecurityScopedResource() { projectParentAccessURL = url }
                newProjectParentPath = path
            }
        case let .failure(error):
            appendLog("Folder selection failed: \(error.localizedDescription)")
        }
    }

    func refreshStatusAndConflicts() async {
        guard !repositoryPath.isEmpty else {
            appendLog("No repository selected.")
            return
        }

        let status = await runGit(repoPath: repositoryPath, args: ["status", "--short", "--branch"])
        await MainActor.run {
            gitStatusOutput = status.combinedOutput
            conflictSuggestions = parseConflictSuggestions(fromPorcelainStatus: status.combinedOutput)
        }
        await refreshBranches()
    }

    func refreshBranches() async {
        guard !repositoryPath.isEmpty else { return }
        let localResult = await runGit(
            repoPath: repositoryPath,
            args: ["for-each-ref", "--format=%(refname:short)", "refs/heads"]
        )
        let remoteResult = await runGit(
            repoPath: repositoryPath,
            args: ["for-each-ref", "--format=%(refname:short)", "refs/remotes/origin"]
        )

        guard localResult.exitCode == 0 || remoteResult.exitCode == 0 else { return }

        let raw = (localResult.stdout + "\n" + remoteResult.stdout)
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        let normalized = raw.compactMap { ref -> String? in
            guard !ref.isEmpty else { return nil }
            if ref == "origin" || ref == "HEAD" || ref == "origin/HEAD" { return nil }
            if ref.hasPrefix("origin/") {
                let cleaned = String(ref.dropFirst("origin/".count))
                guard !cleaned.isEmpty, cleaned != "HEAD" else { return nil }
                return cleaned
            }
            return ref
        }

        let unique = Array(Set(normalized)).sorted()
        await MainActor.run {
            availableBranches = unique.isEmpty ? ["main"] : unique
            if !availableBranches.contains(branchName) {
                branchName = availableBranches.first ?? "main"
            }
        }
    }

    func refreshTags() async {
        guard !repositoryPath.isEmpty else { return }
        let result = await runGit(repoPath: repositoryPath, args: ["tag", "--list"])
        guard result.exitCode == 0 else { return }

        let tags = result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        await MainActor.run {
            availableTags = tags
            if !selectedTagName.isEmpty, !tags.contains(selectedTagName) {
                selectedTagName = ""
            }
        }
    }

    func createTag(name: String, message: String) async -> CommandResult {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanMessage.isEmpty {
            return await runGit(repoPath: repositoryPath, args: ["tag", cleanName])
        }
        return await runGit(repoPath: repositoryPath, args: ["tag", "-a", cleanName, "-m", cleanMessage])
    }

    func deleteTag(name: String) async -> CommandResult {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return await runGit(repoPath: repositoryPath, args: ["tag", "-d", cleanName])
    }

    func pushTag(name: String) async -> CommandResult {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return await runGit(repoPath: repositoryPath, args: ["push", "origin", cleanName])
    }

    func deleteRemoteTag(name: String) async -> CommandResult {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return await runGit(repoPath: repositoryPath, args: ["push", "origin", "--delete", cleanName])
    }

    func renameTag(oldName: String, newName: String, message: String) async -> CommandResult {
        let source = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty, !target.isEmpty else {
            return CommandResult(exitCode: 1, stdout: "", stderr: "Source and target tag name are required.")
        }

        let rev = await runGit(repoPath: repositoryPath, args: ["rev-list", "-n", "1", source])
        guard rev.exitCode == 0 else { return rev }

        let commit = rev.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commit.isEmpty else {
            return CommandResult(exitCode: 1, stdout: "", stderr: "Could not resolve tag commit.")
        }

        let createResult: CommandResult
        if cleanMessage.isEmpty {
            createResult = await runGit(repoPath: repositoryPath, args: ["tag", target, commit])
        } else {
            createResult = await runGit(repoPath: repositoryPath, args: ["tag", "-a", target, commit, "-m", cleanMessage])
        }
        guard createResult.exitCode == 0 else { return createResult }

        _ = await runGit(repoPath: repositoryPath, args: ["tag", "-d", source])
        await MainActor.run {
            selectedTagName = target
            tagNameInput = target
        }
        return createResult
    }

    func createProjectAndOptionallyPublish() async {
        guard !newProjectName.isEmpty, !newProjectParentPath.isEmpty else {
            appendLog("Project name and parent folder are required.")
            return
        }

        let projectPath = sanitizePath(newProjectParentPath) + "/" + newProjectName

        _ = await runCommand(executable: "/bin/mkdir", arguments: ["-p", projectPath], workingDirectory: nil)
        _ = await initRepository(at: projectPath)

        if !createEmptyRepository {
            ensureGitignore(in: projectPath, template: ContentView.defaultGitignoreTemplate)
            _ = await runCommand(
                executable: "/usr/bin/env",
                arguments: ["swift", "package", "init", "--type", "executable"],
                workingDirectory: projectPath
            )
            _ = await runGit(repoPath: projectPath, args: ["add", "-A"])
            _ = await runGit(repoPath: projectPath, args: ["commit", "-m", "Initial commit"])
        } else {
            _ = await runGit(repoPath: projectPath, args: ["add", ".gitignore"])
            _ = await runGit(repoPath: projectPath, args: ["commit", "-m", "Initial commit with .gitignore"])
            appendLog("Empty repository created and .gitignore prepared as first commit.")
        }

        let autoRemote: String? = {
            if !publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return publishRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let owner = inferredGitHubOwner() else { return nil }
            return "git@github.com:\(owner)/\(newProjectName).git"
        }()

        if let autoRemote {
            _ = await ensureGitHubRepositoryExists(forRemote: autoRemote)
            await MainActor.run {
                publishRemoteURL = autoRemote
            }
            _ = await setRemoteOrigin(repoPath: projectPath, remote: autoRemote)
            _ = await runGit(repoPath: projectPath, args: ["push", "-u", "origin", "main"])

            if let createdFullName = githubFullNameFromRemote(autoRemote) {
                await MainActor.run {
                    isWaitingForCreatedRepo = true
                    pendingCreatedRepoFullName = createdFullName
                    var mappings = repoPathMappings()
                    mappings[createdFullName] = projectPath
                    writeRepoPathMappings(mappings)
                }
                let repoVisible = await waitForRepositoryToAppearOnGitHub(fullName: createdFullName)
                await MainActor.run {
                    if repoVisible {
                        selectedGitHubRepoFullName = createdFullName
                        lastSelectedGitHubRepo = createdFullName
                        pendingCreatedRepoFullName = ""
                        isWaitingForCreatedRepo = false
                    } else {
                        selectedGitHubRepoFullName = createdFullName
                        lastSelectedGitHubRepo = createdFullName
                        isWaitingForCreatedRepo = false
                    }
                }
                startBackgroundRepoRefreshIfNeeded(for: createdFullName)
            } else {
                await MainActor.run {
                    isWaitingForCreatedRepo = false
                    pendingCreatedRepoFullName = ""
                }
            }
            await loadGitHubRepositories()
        }

        await MainActor.run {
            repositoryPath = projectPath
            selectedSection = .dashboard
        }
        await refreshStatusAndConflicts()
    }

    func loadGitHubRepositories() async {
        let token = gitHubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            appendLog("Please enter a GitHub token.")
            return
        }

        guard let url = URL(string: "https://api.github.com/user/repos?per_page=100&sort=updated") else {
            appendLog("Invalid GitHub API URL.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                appendLog("Invalid API response.")
                return
            }

            guard httpResponse.statusCode == 200 else {
                appendLog("GitHub API error: HTTP \(httpResponse.statusCode). Check token permissions.")
                return
            }

            let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
            await MainActor.run {
                gitHubRepos = repos.sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
                let availableNames = Set(gitHubRepos.map(\.fullName))
                if !pendingCreatedRepoFullName.isEmpty, availableNames.contains(pendingCreatedRepoFullName) {
                    selectedGitHubRepoFullName = pendingCreatedRepoFullName
                    lastSelectedGitHubRepo = pendingCreatedRepoFullName
                    pendingCreatedRepoFullName = ""
                    isWaitingForCreatedRepo = false
                } else if availableNames.contains(lastSelectedGitHubRepo) {
                    selectedGitHubRepoFullName = lastSelectedGitHubRepo
                } else if !pendingCreatedRepoFullName.isEmpty {
                } else if (!isWaitingForCreatedRepo && pendingCreatedRepoFullName.isEmpty) &&
                            (selectedGitHubRepoFullName.isEmpty || !availableNames.contains(selectedGitHubRepoFullName)) {
                    selectedGitHubRepoFullName = gitHubRepos.first?.fullName ?? ""
                }
            }
            appendLog("GitHub repositories loaded: \(repos.count)")
        } catch {
            appendLog("Could not load GitHub repositories: \(error.localizedDescription)")
        }
    }

    func initRepository(at path: String) async -> CommandResult {
        ensureGitignore(in: sanitizePath(path), template: ContentView.defaultGitignoreTemplate)
        _ = await runGit(repoPath: path, args: ["init", "-b", "main"])
        return await runGit(repoPath: path, args: ["status"])
    }

    func applyGitignoreToTrackedFiles() async {
        guard !repositoryPath.isEmpty else {
            appendLog("Please select a repository first.")
            return
        }

        let listResult = await runGit(
            repoPath: repositoryPath,
            args: ["ls-files", "-ci", "--exclude-standard"]
        )

        guard listResult.exitCode == 0 else {
            appendLog("Could not determine ignored tracked files.")
            return
        }

        let files = listResult.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if files.isEmpty {
            appendLog("No tracked files found that are now ignored.")
            return
        }

        for file in files {
            _ = await runGit(repoPath: repositoryPath, args: ["rm", "--cached", "--", file])
        }

        appendLog("Ignored files removed from index. Next step: commit + push.")
    }

    func setRemoteOrigin(repoPath: String, remote: String) async -> CommandResult {
        let cleanedRemote = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRemote = normalizedRemoteURL(cleanedRemote) ?? cleanedRemote
        let existingOrigin = await runGit(repoPath: repoPath, args: ["remote", "get-url", "origin"])
        if existingOrigin.exitCode == 0 {
            _ = await runGit(repoPath: repoPath, args: ["remote", "remove", "origin"])
        }
        return await runGit(repoPath: repoPath, args: ["remote", "add", "origin", normalizedRemote])
    }

    func runGit(repoPath: String, args: [String], standardInput: String? = nil) async -> CommandResult {
        let cleanedPath = sanitizePath(repoPath)
        guard !cleanedPath.isEmpty else {
            let result = CommandResult(exitCode: 1, stdout: "", stderr: "No repository selected")
            await MainActor.run {
                appendLog("[git] Error: \(result.stderr)")
            }
            return result
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cleanedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            let result = CommandResult(exitCode: 1, stdout: "", stderr: "Repository folder does not exist: \(cleanedPath)")
            await MainActor.run {
                appendLog("[git] Error: \(result.stderr)")
            }
            return result
        }

        if gitExecutablePath.isEmpty {
            await MainActor.run {
                gitExecutablePath = resolveGitExecutablePath()
            }
        }

        guard !gitExecutablePath.isEmpty else {
            let result = CommandResult(
                exitCode: 1,
                stdout: "",
                stderr: "No executable git found. Install Git (e.g. Homebrew) and restart the app."
            )
            await MainActor.run {
                appendLog("[git] Error: \(result.stderr)")
            }
            return result
        }

        return await runCommand(
            executable: gitExecutablePath,
            arguments: args,
            workingDirectory: cleanedPath,
            standardInput: standardInput
        )
    }

    func runCommand(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        standardInput: String? = nil
    ) async -> CommandResult {
        await MainActor.run {
            appendLog("$ \(arguments.joined(separator: " "))")
        }

        let result = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            do {
                try process.run()
                if let standardInput {
                    if let data = standardInput.data(using: .utf8) {
                        stdinPipe.fileHandleForWriting.write(data)
                    }
                }
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(returning: CommandResult(exitCode: 1, stdout: "", stderr: error.localizedDescription))
                return
            }

            process.terminationHandler = { finishedProcess in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                continuation.resume(returning: CommandResult(exitCode: finishedProcess.terminationStatus, stdout: stdout, stderr: stderr))
            }
        }

        await MainActor.run {
            if !result.stdout.isEmpty {
                appendLog(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if !result.stderr.isEmpty {
                let trimmedError = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                appendLog("stderr: \(trimmedError)")
                if trimmedError.contains("xcrun: error: cannot be used within an App Sandbox") {
                    appendLog("Note: /usr/bin/git is often blocked in sandboxed apps. Use a direct git binary (e.g. /opt/homebrew/bin/git).")
                }
                if trimmedError.contains("could not read Username for 'https://github.com'") {
                    appendLog("Note: Use an SSH remote like git@github.com:owner/repo.git.")
                }
            }
            if result.exitCode != 0 {
                if result.stderr.contains("nothing to commit, working tree clean") {
                    appendLog("Info: No commit needed, working tree is clean.")
                } else {
                    appendLog("Command failed with exit code \(result.exitCode)")
                }
            }
        }

        return result
    }

    func parseConflictSuggestions(fromPorcelainStatus status: String) -> [ConflictSuggestion] {
        var suggestions: [ConflictSuggestion] = []
        let lines = status.split(separator: "\n")

        for line in lines {
            guard line.count >= 3 else { continue }
            let code = String(line.prefix(2))
            let file = String(line.dropFirst(3))

            if let suggestion = suggestionForConflict(statusCode: code, file: file) {
                suggestions.append(suggestion)
            }
        }

        return suggestions
    }

    func suggestionForConflict(statusCode: String, file: String) -> ConflictSuggestion? {
        switch statusCode {
        case "UU":
            return ConflictSuggestion(
                file: file,
                statusCode: statusCode,
                suggestion: "Both sides changed this file. Suggestion: try \"Our version\" or \"Their version\" first, then review manually."
            )
        case "AA":
            return ConflictSuggestion(
                file: file,
                statusCode: statusCode,
                suggestion: "File was added on both sides. Suggestion: merge contents, then add/commit."
            )
        case "DU", "UD", "UA", "AU", "DD":
            return ConflictSuggestion(
                file: file,
                statusCode: statusCode,
                suggestion: "Delete/modify conflict. Suggestion: choose \"Our version\" or \"Their version\"."
            )
        default:
            return nil
        }
    }

    func applySuggestion(_ suggestion: ConflictSuggestion) async {
        if suggestion.statusCode == "UU" || suggestion.statusCode == "AA" {
            appendLog("Automatic choice: selecting OURS first for \(suggestion.file). You can switch to THEIRS afterward.")
            await resolveConflictUsing(repoPath: repositoryPath, file: suggestion.file, strategy: .ours)
        } else {
            await resolveConflictUsing(repoPath: repositoryPath, file: suggestion.file, strategy: .ours)
        }
    }

    func resolveConflictUsing(repoPath: String, file: String, strategy: ConflictStrategy) async {
        switch strategy {
        case .ours:
            _ = await runGit(repoPath: repoPath, args: ["checkout", "--ours", "--", file])
        case .theirs:
            _ = await runGit(repoPath: repoPath, args: ["checkout", "--theirs", "--", file])
        }
        _ = await runGit(repoPath: repoPath, args: ["add", "--", file])
    }

    func sanitizePath(_ rawPath: String) -> String {
        rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    func resolveGitExecutablePath() -> String {
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/usr/bin/git"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return ""
    }

    func parseRemoteParts(_ remote: String) -> (host: String, path: String)? {
        if let url = URL(string: remote), let host = url.host {
            let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let cleanedPath = rawPath.hasSuffix(".git") ? rawPath : "\(rawPath).git"
            guard !cleanedPath.isEmpty else { return nil }
            return (host, cleanedPath)
        }

        if remote.contains("@"), remote.contains(":") {
            let parts = remote.split(separator: "@", maxSplits: 1)
            if parts.count == 2 {
                let hostAndPath = parts[1].split(separator: ":", maxSplits: 1)
                if hostAndPath.count == 2 {
                    let host = String(hostAndPath[0])
                    let rawPath = String(hostAndPath[1])
                    let cleanedPath = rawPath.hasSuffix(".git") ? rawPath : "\(rawPath).git"
                    return (host, cleanedPath)
                }
            }
        }

        return nil
    }

    func githubFullNameFromRemote(_ remote: String) -> String? {
        guard let parts = parseRemoteParts(remote) else { return nil }
        var path = parts.path
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        return path.isEmpty ? nil : path
    }

    func inferredGitHubOwner() -> String? {
        if !selectedGitHubRepoFullName.isEmpty {
            let parts = selectedGitHubRepoFullName.split(separator: "/", maxSplits: 1)
            if let owner = parts.first, !owner.isEmpty {
                return String(owner)
            }
        }

        if let first = gitHubRepos.first?.fullName {
            let parts = first.split(separator: "/", maxSplits: 1)
            if let owner = parts.first, !owner.isEmpty {
                return String(owner)
            }
        }

        return nil
    }

    func ensureGitHubRepositoryExists(forRemote remote: String) async -> Bool {
        guard let parts = parseRemoteParts(remote) else {
            appendLog("Could not parse remote: \(remote)")
            return false
        }

        guard parts.host.lowercased() == "github.com" else {
            appendLog("Automatic repository creation is currently supported only for github.com.")
            return false
        }

        let token = gitHubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            appendLog("No GitHub token available: repository cannot be created automatically.")
            return false
        }

        let path = parts.path.hasSuffix(".git") ? String(parts.path.dropLast(4)) : parts.path
        let pathParts = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard pathParts.count == 2 else {
            appendLog("Invalid repository path for automatic creation: \(parts.path)")
            return false
        }

        let owner = pathParts[0]
        let repoName = pathParts[1]

        do {
            if try await githubRepositoryExists(owner: owner, repo: repoName, token: token) {
                return true
            }
            return try await createGitHubRepository(name: repoName, owner: owner, token: token)
        } catch {
            appendLog("GitHub API error during repository creation: \(error.localizedDescription)")
            return false
        }
    }

    func githubRepositoryExists(owner: String, repo: String, token: String) async throws -> Bool {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 200 { return true }
        if http.statusCode == 404 { return false }
        appendLog("Repository existence check returned HTTP \(http.statusCode).")
        return false
    }

    func waitForRepositoryToAppearOnGitHub(fullName: String) async -> Bool {
        let token = gitHubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }

        let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let owner = parts[0]
        let repo = parts[1]

        for _ in 0..<60 {
            await loadGitHubRepositories()
            if gitHubRepos.contains(where: { $0.fullName == fullName }) {
                appendLog("GitHub-Repo ist in der Liste sichtbar: \(fullName)")
                return true
            }
            if (try? await githubRepositoryExists(owner: owner, repo: repo, token: token)) == true {
                appendLog("GitHub repository is available online: \(fullName)")
                return false
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        appendLog("Note: Repository \(fullName) is not visible in the API list yet. Refresh continues.")
        return false
    }

    func startBackgroundRepoRefreshIfNeeded(for fullName: String) {
        createdRepoWaitTask?.cancel()
        createdRepoWaitTask = Task {
            for _ in 0..<24 { // up to ~120s
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await loadGitHubRepositories()
                if gitHubRepos.contains(where: { $0.fullName == fullName }) {
                    await MainActor.run {
                        selectedGitHubRepoFullName = fullName
                        lastSelectedGitHubRepo = fullName
                        pendingCreatedRepoFullName = ""
                        isWaitingForCreatedRepo = false
                    }
                    return
                } else {
                    await MainActor.run {
                        isWaitingForCreatedRepo = true
                    }
                }
            }
            await MainActor.run {
                isWaitingForCreatedRepo = false
            }
        }
    }

    func createGitHubRepository(name: String, owner: String, token: String) async throws -> Bool {
        guard let userURL = URL(string: "https://api.github.com/user") else { return false }
        var userRequest = URLRequest(url: userURL)
        userRequest.httpMethod = "GET"
        userRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        userRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (userData, userResponse) = try await URLSession.shared.data(for: userRequest)
        guard let userHTTP = userResponse as? HTTPURLResponse, userHTTP.statusCode == 200 else {
            appendLog("Could not determine GitHub user.")
            return false
        }

        let user = try JSONDecoder().decode(GitHubUser.self, from: userData)
        let isOwnAccount = user.login.caseInsensitiveCompare(owner) == .orderedSame

        let targetURLString = isOwnAccount
            ? "https://api.github.com/user/repos"
            : "https://api.github.com/orgs/\(owner)/repos"
        guard let targetURL = URL(string: targetURLString) else { return false }

        var createRequest = URLRequest(url: targetURL)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CreateRepoPayload(name: name, auto_init: false, isPrivate: true)
        createRequest.httpBody = try JSONEncoder().encode(payload)

        let (_, createResponse) = try await URLSession.shared.data(for: createRequest)
        guard let createHTTP = createResponse as? HTTPURLResponse else { return false }

        if createHTTP.statusCode == 201 {
            appendLog("GitHub-Repo automatisch erstellt: \(owner)/\(name)")
            return true
        }
        if createHTTP.statusCode == 422 {
            appendLog("GitHub reports: repository already exists or name is invalid.")
            return true
        }

        appendLog("Repo-Erstellung fehlgeschlagen mit HTTP \(createHTTP.statusCode).")
        return false
    }

    func updateAutoPublishRemoteURL() {
        let trimmedName = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let owner = inferredGitHubOwner(), !trimmedName.isEmpty else {
            publishRemoteURL = ""
            return
        }
        publishRemoteURL = "git@github.com:\(owner)/\(trimmedName).git"
    }

    func normalizedRemoteURL(_ remote: String) -> String? {
        guard let parts = parseRemoteParts(remote) else { return nil }
        return "git@\(parts.host):\(parts.path)"
    }

    func appendLog(_ line: String) {
        if logOutput.isEmpty {
            logOutput = line
        } else {
            logOutput += "\n\(line)"
        }
    }

    func repoPathMappings() -> [String: String] {
        guard let data = repoPathMappingsStore.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    func writeRepoPathMappings(_ mappings: [String: String]) {
        guard let data = try? JSONEncoder().encode(mappings),
              let string = String(data: data, encoding: .utf8)
        else {
            return
        }
        repoPathMappingsStore = string
    }

    func savePathMappingIfPossible(path: String) {
        let repo = selectedGitHubRepoFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else { return }
        var mappings = repoPathMappings()
        mappings[repo] = path
        writeRepoPathMappings(mappings)
    }

    func createSSHKey() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sshDir = home + "/.ssh"
        let privateKeyPath = sshDir + "/gitsync_ed25519"
        let publicKeyPath = privateKeyPath + ".pub"

        _ = await runCommand(executable: "/bin/mkdir", arguments: ["-p", sshDir], workingDirectory: nil)

        let hasExistingKey = FileManager.default.fileExists(atPath: privateKeyPath)
        if !hasExistingKey {
            let email = sshKeyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            var args = ["ssh-keygen", "-t", "ed25519", "-f", privateKeyPath, "-N", ""]
            if !email.isEmpty {
                args += ["-C", email]
            }
            _ = await runCommand(executable: "/usr/bin/env", arguments: args, workingDirectory: nil)
        } else {
            appendLog("SSH-Key existiert bereits: \(privateKeyPath)")
        }

        _ = await runCommand(executable: "/usr/bin/env", arguments: ["ssh-add", "--apple-use-keychain", privateKeyPath], workingDirectory: nil)

        do {
            sshPublicKey = try String(contentsOfFile: publicKeyPath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            appendLog("SSH public key loaded. Next step: 'Add SSH key on GitHub'.")
        } catch {
            appendLog("Could not read public key: \(error.localizedDescription)")
        }
    }

    func savePublicKeyToClipboard() {
        if sshPublicKey.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let publicKeyPath = home + "/.ssh/gitsync_ed25519.pub"
            if let value = try? String(contentsOfFile: publicKeyPath, encoding: .utf8) {
                sshPublicKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !sshPublicKey.isEmpty else {
            appendLog("No public key found. Please create an SSH key first.")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sshPublicKey, forType: .string)
        appendLog("SSH Public Key wurde in die Zwischenablage kopiert.")
    }

    func localPathForRepo(_ repoFullName: String) -> String? {
        let value = repoPathMappings()[repoFullName]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    func saveGitHubTokenToKeychain(_ token: String) {
        let service = "GitSync.GitHubToken"
        let account = "default"
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if trimmedToken.isEmpty {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }

        let tokenData = Data(trimmedToken.utf8)
        let updateAttributes: [String: Any] = [kSecValueData as String: tokenData]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = tokenData
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            appendLog("Could not save GitHub token in Keychain.")
        }
    }

    func loadGitHubTokenFromKeychain() -> String? {
        let service = "GitSync.GitHubToken"
        let account = "default"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    func releaseSecurityScope(for url: inout URL?) {
        guard let existing = url else { return }
        existing.stopAccessingSecurityScopedResource()
        url = nil
    }

    func ensureGitignore(in directory: String, template: String) {
        let filePath = directory + "/.gitignore"
        let fileURL = URL(fileURLWithPath: filePath)

        if let existing = try? String(contentsOf: fileURL, encoding: .utf8) {
            var updated = existing
            for entry in template.split(separator: "\n").map(String.init) where !existing.contains(entry) {
                if !updated.hasSuffix("\n") {
                    updated += "\n"
                }
                updated += entry + "\n"
            }
            try? updated.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            try? template.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
