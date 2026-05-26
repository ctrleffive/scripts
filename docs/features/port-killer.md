# Port Killer (`pk.sh`)

Find and kill processes listening on TCP ports.

## Metadata
- **OS**: macOS, Linux
- **Sudo**: No (escalates dynamically if needed)

## Usage

### Interactive Mode
```bash
./pk.sh
```
Scans all listening TCP ports, displays a numbered table, and prompts to pick a process to kill by number, port, or `all`.

### Direct Mode
```bash
./pk.sh 3000
```
Kills whatever is listening on port 3000 immediately.

## Features
- Cross-platform port scanning (`lsof` on macOS, `ss` on Linux)
- Deduplicates entries by port + PID
- Sorted by port number
- Graceful kill (SIGTERM) with SIGKILL fallback
- Accepts menu number, raw port number, or `all`
- Invalid input re-prompts without repeating the table
