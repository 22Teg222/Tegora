# Tegora

A native macOS cleaning and maintenance app, written in Swift and SwiftUI. It takes its cue from CleanMyMac, but with its own look and code, built around Apple's Liquid Glass design.

> **A personal project.** I built Tegora independently, only for myself, as an app I wanted on my own Mac. I've now put it on GitHub in case it's useful or interesting to someone else. It is provided as-is, with no warranty and no support promised. Use it at your own risk, and read the Safety section before you delete anything.

## Features

### Smart Care
One scan that checks the whole Mac and gives it a health score.
- Real storage and memory numbers
- Junk detection across every Cleanup category
- A quick malware scan (once ClamAV is set up)
- App signature and notarization checks, startup items, and the state of Gatekeeper, System Integrity Protection and the firewall
- Recommendations, and a review step before anything is cleaned

### Cleanup
Find and remove files you don't need, after inspecting them first.
- System caches, logs and old temporary files
- Xcode junk (derived data, device support files)
- Mail downloads and iOS backups
- Trash
- Broken preference files
- Unused language files (carries a warning, because it changes other apps' files)

### Protection
- **Malware:** scans with ClamAV, a real open-source engine and signature database. Quick Scan, Applications, Home Folder, or any folder you choose.
- **Security Check:** verifies app code signatures and notarization, and reviews launch agents and daemons.
- **Privacy:** clears browser history, cookies and recent-item lists.

### Applications
- Uninstall apps together with their leftover files, one at a time or in bulk
- Check for updates for App Store apps and apps that use Sparkle

### My Clutter
- Large files and old files
- Downloads cleanup
- Duplicate finder (identical files, compared by SHA-256)
- Similar image finder (uses Apple's Vision framework)
- File size breakdown by type, with previews

### Space Lens
- An interactive treemap of what is using your storage
- Click to select, double-click to open a folder
- Largest files list

### Design
- Liquid Glass on macOS 26, with a native material fallback on earlier versions
- A colour theme and animated backdrop for each section
- Light and dark mode, and SF Symbols throughout

## Requirements
- macOS 14 or later (Liquid Glass needs macOS 26)
- Xcode 16 or later to build it (Xcode 26 for the full Liquid Glass look)

## Build and run
1. Clone or download this repository.
2. Open `Tegora.xcodeproj` in Xcode.
3. Select the **Tegora** scheme and your Mac as the destination.
4. Under **Signing & Capabilities**, choose your own Team.
5. Press **Cmd-R**.

For the best results, give Tegora **Full Disk Access** in System Settings > Privacy & Security, then relaunch. Without it, Tegora can't see Mail, iOS backups, the Trash or Safari data.

## Turning on malware scanning
The malware scan uses [ClamAV](https://www.clamav.net), which Tegora doesn't include.

1. Install it once with Homebrew: `brew install clamav`
2. In Tegora, open **Protection > Malware** and press **Check Again**, then **Download Signatures**. The download is about 300 MB and is stored in `~/Library/Application Support/Tegora/ClamAV`.
3. Choose a scan.

Tegora only reports what ClamAV identifies. ClamAV finds known malware, so it won't catch everything, and it can occasionally flag a harmless file. Look at each detection before you remove it.

## Safety
- Nothing is removed until you review the list and confirm.
- Almost everything is moved to the Trash, so you can restore it. Only items already in the Trash and browser history and cookie files are deleted permanently, and the confirmation screen says so.
- System folders, your home folders themselves and Apple's own apps are blocked in code.
- Cleanup only touches files inside your home folder, `/Applications` and the temporary folder.
- Tegora is **not sandboxed**, because a cleaner has to read and remove files in `~/Library` and in other apps. It uses the Hardened Runtime.
- Your files are never uploaded anywhere. The only network use is the ClamAV signature download and the update checks for apps.

## Limitations
- Tegora can't read or change macOS app permissions, or other apps' login items. macOS protects them.
- Smart Care's malware step scans only Downloads, Desktop and startup folders. Use Protection for a wider scan.
- Update checks only work for App Store apps and Sparkle apps.
- It is a personal project and has mainly been tested on my own Mac. Try a small category first, such as Logs, and check the Trash afterwards.

## Project layout
```
Tegora/
├── App/          App entry point and navigation
├── Views/        One view per section, plus the sidebar
├── Components/   Glass styles, themes and shared review screens
├── Models/       Data types
├── Services/     Scanning, cleanup, malware, applications and storage logic
├── Utilities/    File helpers and formatting
└── Resources/    Asset catalog and app icon
```
`IconLayers/` holds the leaf icon artwork for use in Icon Composer.
