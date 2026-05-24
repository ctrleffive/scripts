# Ctrl F5 Scripts

Various scripts for personal automations.

## 1. Mac Cleaner (`mc.sh`)
A unified, interactive storage scanning and cleanup utility for macOS. It safely reclaims storage space by removing unneeded caches, temporary files, old package manager data, Docker artifacts, and large files. The output is elegantly formatted with ASCII branding and automatically sorted by size descending.

**Default (Dry-Run / Scanner):**
Running the script directly acts as a scanner. It will calculate the sizes of various caches and prompt you for custom directories to find heavy `node_modules` or large files (>200MB), without deleting anything.
```bash
curl -sL https://scripts.chandujs.com/mc.sh | sudo bash
```

**Interactive Cleanup (`--clean`):**
Running with the `--clean` flag triggers interactive mode. For every scannable area that contains data, it will display the exact command or paths to be removed and prompt for your confirmation before proceeding.
```bash
curl -sL https://scripts.chandujs.com/mc.sh | sudo bash -s -- --clean
```