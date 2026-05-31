![Hero Screenshot](https://online.kevintobler.ch/projectimages/GitSync-Banner.jpg)

# GitSync for macOS

[![Download GitSync](https://img.shields.io/badge/Download-GitSync-blue)](https://github.com/KeepCoolCH/GitSync/releases/tag/V.1.1)

**GitSync** is a macOS app for visual Git/GitHub management directly from a graphical interface. You can sync local projects with GitHub, clone repositories, create new repositories, and run common Git workflows without using the terminal.
Version **1.0** – developed by **Kevin Tobler** 🌐 [www.kevintobler.ch](https://www.kevintobler.ch)

---

## 🔄 Changelog

### 🆕 Version 1.x
- **1.0**
  - First Release
  - Visual Git and GitHub management for macOS
  - GitHub repository dashboard with repository cards
  - Clone existing repositories from GitHub
  - Create new local projects and publish them directly to GitHub
  - Automatic SSH remote configuration
  - Secure GitHub token storage in macOS Keychain
  - SSH key generation with GitHub integration support
  - Repository-specific local folder assignments
  - Fetch, Pull, Push and Commit actions from the graphical interface
  - Multiple pull strategies with explanations: Merge, Rebase, Fast-forward only, Rebase with auto-stash
  - Built-in .gitignore editor with templates
  - Git status and commit log viewer
  - Conflict detection with resolution suggestions
  - Quick repository switching via active repository bar
  - Automatic loading of GitHub repositories through the GitHub API
  - Native macOS interface

---

## 🚀 Features

### Core
- Dashboard with your GitHub repositories (card layout)
- Active repository bar with quick switching
- Save and reuse a local repo folder per GitHub repository
- Clone repository (separate window)
- Create a new project and publish to GitHub (separate window)
- Automatic SSH remote URL setup
- `.gitignore` editor with a default template before applying
- Sync tools with `fetch`, `pull`, `push`, `force push`, and commit actions
- Pull modes with explanations (`merge`, `rebase`, `ff-only`, `rebase --autostash`)
- Conflict detection from `git status` with suggestions (`ours` / `theirs`)
- Create/Delete Tags
- Status and log views
- Secure GitHub token storage in macOS Keychain
- SSH key creation and GitHub handoff support

### Authentication
GitSync supports two methods:

1. SSH (recommended)
- Create an SSH key in the app
- Add the public key on GitHub under `Settings > SSH and GPG keys`
- Use SSH remotes (`git@github.com:owner/repo.git`)

2. GitHub Token (for API features)
- Add your token in GitSync (stored in macOS Keychain)
- Repositories load automatically when a token is available
- Used for GitHub API operations (for example repository creation)

---

## 📸 Screenshots

![Screenshot](https://online.kevintobler.ch/projectimages/GitSyncV1-dashboard.png)  
![Screenshot](https://online.kevintobler.ch/projectimages/GitSyncV1-newrepo.png)  
![Screenshot](https://online.kevintobler.ch/projectimages/GitSyncV1-repo.png)  
![Screenshot](https://online.kevintobler.ch/projectimages/GitSyncV1-sync.png)  
![Screenshot](https://online.kevintobler.ch/projectimages/GitSyncV1-tags.png)  
![Screenshot](https://online.kevintobler.ch/projectimages/GitSyncV1-statuslogs.png)  

---

## ⚙️ Requirements
- macOS 14.6 Sonoma or newer
- Git installed (for example via Homebrew or Command Line Tools)
- GitHub account

---

## 🔧 Installation

[![Download GitSync](https://img.shields.io/badge/Download-GitSync-blue)](https://github.com/KeepCoolCH/GitSync/releases/tag/V.1.1)

1. Download the latest GitSync release from GitHub.
2. Open the downloaded DMG file.
3. Drag GitSync.app into the Applications folder.
4. Launch GitSync.
5. If macOS displays a security warning:
6. Open System Settings → Privacy & Security
7. Click Open Anyway
8. Configure authentication: Create or import an SSH key (recommended), or Add a GitHub Personal Access Token for GitHub API features.
9. Select or clone your first repository and start syncing.

---

## 🔑 First-Time Setup
Option 1: SSH Authentication (Recommended)
1. Open Settings → SSH Keys
2. Create a new SSH key pair
3. Copy the generated public key
4. Add it to GitHub:
  - GitHub → Settings → SSH and GPG Keys
  - Click New SSH Key
  - Paste the public key and save
5. GitSync will use SSH URLs for repository operations

Option 2: GitHub Token
1. Create a Personal Access Token on GitHub
2. Open Settings → GitHub Token in GitSync
3. Paste the token
4. The token is securely stored in the macOS Keychain
5. Your repositories will automatically load from GitHub

---

## 🧩 Usage

### Typical Workflow
1. Add your GitHub token
2. Repositories load automatically
3. Select a repository
4. Assign the local folder
5. Sync with `Fetch`, `Pull`, `Push`
6. Commit changes and push

### Create a New Project
- Open `New Project`
- Enter project name and parent folder
- Optionally create an empty repo
- GitSync can automatically create the GitHub repository via API (private by default) and run the initial push

### Conflict Handling Note
The app detects conflicts from Git status codes (for example `UU`, `AA`) and provides quick actions. For complex conflicts, manual review is still required.

---

## 📝 Notes

### Known Limitations
- Some advanced Git edge cases still require manual handling
- Network/API propagation delays may cause newly created repositories to appear in the list after a short wait

---

## 🧑‍💻 Developer

**Kevin Tobler**  
🌐 [www.kevintobler.ch](https://www.kevintobler.ch)  

---

## 📜 License

This project is licensed under the **MIT License** – feel free to use, modify, and distribute.
