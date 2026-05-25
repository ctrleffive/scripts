# Ctrl F5 Scripts

Various scripts for personal automations.

## 1. Mac Cleaner (`mc.sh`)
A unified storage scanning and cleanup utility for macOS.

**Features:**
- Cleans caches, temporary files, package managers, and Docker artifacts.
- Identifies heavy and large files (>200MB).
- Safe default scanner (dry-run mode).
- Interactive cleanup mode for selective removal.

**Usage:**
```bash
# Dry Run
curl -sL https://scripts.chandujs.com/mc.sh | sudo bash

# Live Mode
curl -sL https://scripts.chandujs.com/mc.sh | sudo bash -s -- --clean
```

## 2. RAM Disk Downloads (`ram.sh`)
Backs up `~/Downloads`, mounts a RAM disk, and symlinks it for volatile, high-speed storage.

**Features:**
- Safely backs up existing `~/Downloads` folder.
- Mounts a customizable RAM disk (default: 10GB).
- Supports macOS (`hdiutil`) and Linux (`tmpfs`).
- Protects against filling up RAM (>80% warning).

**Usage:**
```bash
# Default 10GB
curl -sL https://scripts.chandujs.com/ram.sh | bash

# Custom Size (e.g., 4GB)
curl -sL https://scripts.chandujs.com/ram.sh | bash -s -- 4g
```