# RAM Disk Downloads Setup (`ram.sh`)

## Overview
The `ram.sh` script provides a way to temporarily use a high-speed RAM disk for the `~/Downloads` directory. This ensures that any data written into your downloads folder is incredibly fast and completely volatile, meaning it won't take up persistent storage and gets wiped out upon a system reboot.

## Features
- **Automatic Backups**: Safely backs up the existing `~/Downloads` folder before proceeding.
- **Cross-Platform Support**: Works on both macOS (using `hdiutil`) and Linux (using `tmpfs`).
- **Customizable Size**: The default RAM disk size is 10 GB, but you can specify custom sizes (e.g., `4g` or `512m`).
- **Safety Checks**: Includes a RAM headroom check that warns the user if the requested size exceeds 80% of available RAM to prevent system instability.
- **Volatile Storage**: Data stored in the `~/Downloads` folder while this is active is lost on reboot, enforcing a temporary lifecycle for downloaded files.

## Usage

### Default Size (10 GB)
```bash
./ram.sh
```

### Custom Sizes
```bash
./ram.sh 4    # 4 GB
./ram.sh 4g   # 4 GB
./ram.sh 512m # 512 MB
```

## Restoration
The script provides instructions upon completion on how to restore your original `~/Downloads` folder (which it automatically renames during backup). You simply need to remove the symlinked directory and rename your backup folder back to `~/Downloads`.
