import SwiftUI

extension ContentView {
    var activeContextBar: some View {
        Button {
            if gitHubRepos.isEmpty, !gitHubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runAsync {
                    await loadGitHubRepositories()
                    await MainActor.run { showQuickRepoPicker = true }
                }
            } else {
                showQuickRepoPicker = true
            }
        } label: {
            HStack(spacing: 10) {
                Label("Active repo", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedGitHubRepoFullName.isEmpty ? "No GitHub repository selected" : selectedGitHubRepoFullName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !repositoryPath.isEmpty {
                    Text(repositoryPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isWaitingForCreatedRepo {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showQuickRepoPicker) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select repository")
                    .font(.headline)

                if gitHubRepos.isEmpty {
                    Text("No repositories loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List(gitHubRepos) { repo in
                        Button {
                            selectedGitHubRepoFullName = repo.fullName
                            showQuickRepoPicker = false
                        } label: {
                            HStack {
                                Text(repo.fullName)
                                Spacer()
                                if repo.fullName == selectedGitHubRepoFullName {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minHeight: 260)
                }
            }
            .padding(12)
            .frame(width: 420)
        }
    }

    @ViewBuilder
    var sectionContent: some View {
        switch selectedSection {
        case .dashboard:
            VStack(alignment: .leading, spacing: 16) {
                quickActionsSection
                dashboardReposSection
            }
        case .repository:
            repositorySection
        case .sync:
            syncSection
        case .tags:
            tagsSection
        case .logs:
            outputSection
        }
    }

    var dashboardReposSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("GitHub Access")
                    Spacer()
                }

                if showTokenEditor {
                    SecureField("GitHub token for repository list", text: $gitHubToken)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button(showTokenEditor ? "Hide token" : "Add token") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showTokenEditor.toggle()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                    if !gitHubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("Token saved", systemImage: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if showSSHEmailEditor {
                    TextField("SSH-Key Email (optional)", text: $sshKeyEmail)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button(showSSHEmailEditor ? "Hide SSH email" : "Add SSH email") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSSHEmailEditor.toggle()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Create SSH key") {
                        runAsync {
                            await createSSHKey()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Add SSH key on GitHub") {
                        savePublicKeyToClipboard()
                        if let url = URL(string: "https://github.com/settings/keys") {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                if !sshPublicKey.isEmpty {
                    Text("Public key is ready to copy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionTitle("My Repositories")
                    Spacer()
                    Button {
                        runAsync {
                            await loadGitHubRepositories()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh repository list")
                }

                if isWaitingForCreatedRepo, !pendingCreatedRepoFullName.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for GitHub synchronization: \(pendingCreatedRepoFullName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if gitHubRepos.isEmpty {
                    Text("No repositories loaded. Enter your token to load repositories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(gitHubRepos) { repo in
                            let isSelected = repo.fullName == selectedGitHubRepoFullName
                            Button {
                                selectedGitHubRepoFullName = repo.fullName
                                selectedSection = .repository
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(repo.fullName)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected ? .green : .secondary)
                                    }
                                    if let localPath = localPathForRepo(repo.fullName), !localPath.isEmpty {
                                        Text(localPath)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    } else {
                                        Text("No local path assigned")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? Color.blue.opacity(0.18) : Color.white.opacity(0.55))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
        }
    }

    var quickActionsSection: some View {
        HStack(spacing: 12) {
            Button {
                showCloneWindow = true
            } label: {
                Label("Clone Repository", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Button {
                showNewProjectWindow = true
            } label: {
                Label("New Project", systemImage: "plus.app.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    var cloneSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Git URL to clone", text: $cloneURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Destination folder", text: $cloneDestinationPath)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Choose destination folder") {
                        openFolderPanel(for: .cloneDestination)
                    }
                    Button("Clone") {
                        runAsync {
                            guard !cloneURL.isEmpty, !cloneDestinationPath.isEmpty else {
                                appendLog("Clone URL and destination folder are required.")
                                return
                            }
                            _ = await runCommand(
                                executable: gitExecutablePath,
                                arguments: ["clone", cloneURL],
                                workingDirectory: sanitizePath(cloneDestinationPath)
                            )
                            showCloneWindow = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("Clone Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showCloneWindow = false }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 260)
    }

    var newProjectSheetContent: some View {
        NavigationStack {
            ZStack {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Projektname", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newProjectName) { _, _ in
                            updateAutoPublishRemoteURL()
                        }
                    TextField("Parent folder", text: $newProjectParentPath)
                        .textFieldStyle(.roundedBorder)
                    TextField("GitHub SSH Remote (optional)", text: $publishRemoteURL)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Create empty repo (without files)", isOn: $createEmptyRepository)

                    HStack {
                        Button("Choose parent folder") {
                            openFolderPanel(for: .projectParent)
                        }
                        Button("Create project") {
                            isCreatingProject = true
                            runAsync {
                                await createProjectAndOptionallyPublish()
                                await MainActor.run {
                                    isCreatingProject = false
                                    showNewProjectWindow = false
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .disabled(isCreatingProject)
                    }
                    Spacer()
                }
                .disabled(isCreatingProject)

                if isCreatingProject {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Projekt wird erstellt und synchronisiert …")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(16)
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showNewProjectWindow = false }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 300)
    }

    var repositorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Repository")

            TextField("Local repo path", text: $repositoryPath)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Choose repo folder") {
                    openFolderPanel(for: .repository)
                }

                Button("Repo initialisieren") {
                    runAsync {
                        guard !repositoryPath.isEmpty else {
                            appendLog("Please choose a repository path first.")
                            return
                        }
                        _ = await initRepository(at: repositoryPath)
                    }
                }
                .disabled(isRunningCommand)

                Button("Apply .gitignore") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showGitignoreEditor.toggle()
                    }
                }
                .disabled(isRunningCommand || repositoryPath.isEmpty)
            }

            if showGitignoreEditor {
                Text("Edit the default content and then apply it:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $gitignoreDraft)
                    .frame(minHeight: 160)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))

                HStack {
                    Button("Apply changes") {
                        runAsync {
                            let cleanedPath = sanitizePath(repositoryPath)
                            ensureGitignore(in: cleanedPath, template: gitignoreDraft)
                            await applyGitignoreToTrackedFiles()
                            await refreshStatusAndConflicts()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isRunningCommand || repositoryPath.isEmpty)

                    Button("Reset to default") {
                        gitignoreDraft = ContentView.defaultGitignoreTemplate
                    }
                    .disabled(isRunningCommand)
                }
            }

            TextField("SSH Remote (git@github.com:owner/repo.git)", text: $remoteURL)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Remote setzen") {
                    runAsync {
                        guard !repositoryPath.isEmpty, !remoteURL.isEmpty else {
                            appendLog("Repo path and remote URL are required.")
                            return
                        }
                        _ = await setRemoteOrigin(repoPath: repositoryPath, remote: remoteURL)
                    }
                }
                .disabled(isRunningCommand)

                Button("Refresh status") {
                    runAsync {
                        await refreshStatusAndConflicts()
                    }
                }
                .disabled(isRunningCommand)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Synchronization")
                Picker("Branch", selection: $branchName) {
                    ForEach(availableBranches, id: \.self) { branch in
                        Text(branch).tag(branch)
                    }
                }
                .onAppear {
                    if availableBranches.isEmpty { availableBranches = ["main"] }
                }

                Picker("Pull-Modus", selection: $pullMode) {
                    ForEach(PullMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(pullMode.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Commit Message", text: $commitMessage)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Fetch") {
                        runAsync {
                            await MainActor.run {
                                isRunningSyncAction = true
                                syncActionLabel = "Fetch running…"
                            }
                            _ = await runGit(repoPath: repositoryPath, args: ["fetch", "--all"])
                            await refreshStatusAndConflicts()
                            await MainActor.run {
                                isRunningSyncAction = false
                                syncActionLabel = ""
                            }
                        }
                    }
                    .disabled(isRunningCommand || repositoryPath.isEmpty)

                    Button("Pull") {
                        runAsync {
                            await MainActor.run {
                                isRunningSyncAction = true
                                syncActionLabel = "Pull running…"
                            }
                            _ = await runGit(repoPath: repositoryPath, args: pullMode.pullArgs(branch: branchName))
                            await refreshStatusAndConflicts()
                            await MainActor.run {
                                isRunningSyncAction = false
                                syncActionLabel = ""
                            }
                        }
                    }
                    .disabled(isRunningCommand || repositoryPath.isEmpty)

                    Button("Push") {
                        runAsync {
                            await MainActor.run {
                                isRunningSyncAction = true
                                syncActionLabel = "Push running…"
                            }
                            _ = await runGit(repoPath: repositoryPath, args: ["push", "origin", branchName])
                            await refreshStatusAndConflicts()
                            await MainActor.run {
                                isRunningSyncAction = false
                                syncActionLabel = ""
                            }
                        }
                    }
                    .disabled(isRunningCommand || repositoryPath.isEmpty)

                    Button("Force Push (with lease)") {
                        runAsync {
                            await MainActor.run {
                                isRunningSyncAction = true
                                syncActionLabel = "Force push (with lease) running…"
                            }
                            _ = await runGit(repoPath: repositoryPath, args: ["push", "--force-with-lease", "origin", branchName])
                            await refreshStatusAndConflicts()
                            await MainActor.run {
                                isRunningSyncAction = false
                                syncActionLabel = ""
                            }
                        }
                    }
                    .disabled(isRunningCommand || repositoryPath.isEmpty)

                    Button("Force Push (no lease)") {
                        runAsync {
                            await MainActor.run {
                                isRunningSyncAction = true
                                syncActionLabel = "Force push (no lease) running…"
                            }
                            _ = await runGit(repoPath: repositoryPath, args: ["push", "--force", "origin", branchName])
                            await refreshStatusAndConflicts()
                            await MainActor.run {
                                isRunningSyncAction = false
                                syncActionLabel = ""
                            }
                        }
                    }
                    .disabled(isRunningCommand || repositoryPath.isEmpty)

                    Button("Load branches") {
                        runAsync {
                            await refreshBranches()
                        }
                    }
                    .disabled(isRunningCommand || repositoryPath.isEmpty)
                }

                if isRunningSyncAction {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(syncActionLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("`Fetch`: Downloads new commits from the remote without changing local files.")
                    Text("`Pull`: Fetches changes and integrates them using the selected pull mode.")
                    Text("`Push`: Uploads your local commits to the remote branch.")
                    Text("`Force Push (with lease)`: Uses `--force-with-lease` (safer; prevents overwriting unknown remote updates).")
                    Text("`Force Push (no lease)`: Uses `--force` (overwrites remote history unconditionally).")
                    Text("`Load branches`: Refreshes the available branch list from local and origin.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Commit All (add + commit)") {
                    runAsync {
                        guard !commitMessage.isEmpty else {
                            appendLog("Commit message must not be empty.")
                            return
                        }
                        _ = await runGit(repoPath: repositoryPath, args: ["add", "-A"])
                        _ = await runGit(repoPath: repositoryPath, args: ["commit", "-m", commitMessage])
                        await refreshStatusAndConflicts()
                    }
                }
                .disabled(isRunningCommand || repositoryPath.isEmpty)

                Text("`Commit All`: Runs `git add -A` followed by `git commit -m ...`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )

            conflictSectionContent
        }
    }

    var conflictSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Conflicts & Suggestions")

            if conflictSuggestions.isEmpty {
                Text("No conflicts detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(conflictSuggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.file)
                            .font(.headline)
                        Text("Status: \(suggestion.statusCode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(suggestion.suggestion)
                            .font(.subheadline)

                        HStack {
                            Button("Apply suggestion") {
                                runAsync {
                                    await applySuggestion(suggestion)
                                    await refreshStatusAndConflicts()
                                }
                            }
                            .disabled(isRunningCommand)

                            Button("Our version") {
                                runAsync {
                                    await resolveConflictUsing(repoPath: repositoryPath, file: suggestion.file, strategy: .ours)
                                    await refreshStatusAndConflicts()
                                }
                            }
                            .disabled(isRunningCommand)

                            Button("Their version") {
                                runAsync {
                                    await resolveConflictUsing(repoPath: repositoryPath, file: suggestion.file, strategy: .theirs)
                                    await refreshStatusAndConflicts()
                                }
                            }
                            .disabled(isRunningCommand)
                        }
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }

    var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Tags")

            HStack {
                Button("Load Tags") {
                    runAsync {
                        await refreshTags()
                    }
                }
                .disabled(isRunningCommand || repositoryPath.isEmpty)

                Button("Create Tag") {
                    runAsync {
                        guard !tagNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            appendLog("Tag name is required.")
                            return
                        }
                        _ = await createTag(name: tagNameInput, message: tagMessageInput)
                        await refreshTags()
                    }
                }
                .disabled(isRunningCommand || repositoryPath.isEmpty)

                Button("Rename Tag") {
                    runAsync {
                        guard !selectedTagName.isEmpty else {
                            appendLog("Select a tag first.")
                            return
                        }
                        guard !tagNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            appendLog("New tag name is required.")
                            return
                        }
                        _ = await renameTag(oldName: selectedTagName, newName: tagNameInput, message: tagMessageInput)
                        await refreshTags()
                    }
                }
                .disabled(isRunningCommand || repositoryPath.isEmpty)

                Button("Delete Tag") {
                    runAsync {
                        guard !selectedTagName.isEmpty else {
                            appendLog("Select a tag first.")
                            return
                        }
                        _ = await deleteTag(name: selectedTagName)
                        await refreshTags()
                    }
                }
                .disabled(isRunningCommand || repositoryPath.isEmpty)

                Button("Push Tag") {
                    runAsync {
                        let tagToPush = selectedTagName.isEmpty ? tagNameInput : selectedTagName
                        guard !tagToPush.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            appendLog("Select or enter a tag first.")
                            return
                        }
                        _ = await pushTag(name: tagToPush)
                    }
                }
                .disabled(isRunningCommand || repositoryPath.isEmpty)

                Button("Delete Remote Tag") {
                    runAsync {
                        let tagToDelete = selectedTagName.isEmpty ? tagNameInput : selectedTagName
                        guard !tagToDelete.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            appendLog("Select or enter a tag first.")
                            return
                        }
                        _ = await deleteRemoteTag(name: tagToDelete)
                    }
                }
                .disabled(isRunningCommand || repositoryPath.isEmpty)
            }

            TextField("Tag name (e.g. v1.2.0)", text: $tagNameInput)
                .textFieldStyle(.roundedBorder)

            TextField("Tag message (optional, creates annotated tag)", text: $tagMessageInput)
                .textFieldStyle(.roundedBorder)

            if availableTags.isEmpty {
                Text("No tags found in this repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(availableTags, id: \.self) { tag in
                    Button {
                        selectedTagName = tag
                        tagNameInput = tag
                    } label: {
                        HStack {
                            Text(tag)
                            Spacer()
                            if tag == selectedTagName {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 220)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("`Rename Tag` recreates the tag on the same commit and removes the old name locally.")
                Text("`Push Tag` pushes the selected/local tag to `origin`.")
                Text("`Delete Remote Tag` removes the selected tag from `origin`.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .onAppear {
            if availableTags.isEmpty && !repositoryPath.isEmpty {
                runAsync {
                    await refreshTags()
                }
            }
        }
    }

    var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Status")

                TextEditor(text: $gitStatusOutput)
                    .frame(minHeight: 120)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
            }
            .padding(12)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Log")

                TextEditor(text: $logOutput)
                    .frame(minHeight: 220)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
            }
            .padding(12)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
        }
    }
}
