# Ctrl F5 Scripts

Various scripts for personal automations.

## Available Scripts

### 1. Mac Storage Scanner (`mss.sh`)
A storage scanning utility that provides a detailed breakdown of disk usage across your system.

**Usage:**
```bash
curl -sL https://scripts.chandujs.com/mss.sh | sudo bash
```

### 2. Mac Secure Cleanup (`msc.sh`)
A cleanup script designed to safely reclaim storage space by removing unneeded caches, temporary files, and logs.

**Live run:**
```bash
curl -sL https://scripts.chandujs.com/msc.sh | sudo bash
```

**Preview only (dry run):**
```bash
curl -sL https://scripts.chandujs.com/msc.sh | sudo bash -s -- --dry-run
```

**Show details (verbose):**
```bash
curl -sL https://scripts.chandujs.com/msc.sh | sudo bash -s -- --verbose
```