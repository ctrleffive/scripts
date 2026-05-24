# Mac Cleaner (`mc.sh`)

## Overview
`mc.sh` is a unified, interactive utility script designed to scan and safely clean up disk space on macOS. It replaces the previous separate scanner (`mss.sh`) and cleanup (`msc.sh`) scripts by merging their functionalities into one cohesive experience.

## Capabilities
- **Intelligent Sorting:** All scanned items within a section (as well as custom large files and `node_modules`) are strictly ordered by size descending, surfacing the largest junk first.
- **Comprehensive Scanning:** Identifies caches for package managers (Homebrew, npm, pnpm, Bun, pip, Gradle, Go, CocoaPods), IDEs (JetBrains, VS Code), Docker data, Time Machine snapshots, system/user caches, temporary files, and application logs.
- **Dry-Run by Default:** Running the script directly `sudo ./mc.sh` simply scans and lists the sizes of the components without modifying or deleting any files.
- **Interactive Deletion:** Running the script with `sudo ./mc.sh --clean` triggers live mode. It individually prompts the user for confirmation (`[y/N]`) before proceeding with the deletion of each categorized area.
- **Native Command Visibility:** When dealing with environments like Docker or Package Managers, the script prints the exact native command it intends to run (e.g., `docker system prune -f`) inside the confirmation prompt so the user has full transparency.
- **Custom Deep Scanning:** The script interactively asks if the user wants to scan a custom target directory (like `~/Projects`) for excessively heavy `node_modules` folders or individual files larger than `200MB`. Leaving the prompt blank safely skips the action.

## UI / Aesthetics
The script uses a minimal, color-coded terminal interface with the following elements:
- A stylish block ASCII "Mac Cleaner" branding header at the start.
- `[?]` (Yellow Question Mark) for user prompts.
- `[✓]` (Green Checkbox) for successfully executed actions.
- `[-]` (Dim Minus) for skipped actions.
- `[!]` (Red Exclamation) for highly destructive warnings (like iOS device backups).
- Animated cyan spinners (`⠋⠙⠹...`) for visually pleasing progress tracking.
