---
trigger: always_on
---

# Project Architecture

## Structure
```
.
├── run.sh              # Universal launcher (entry point via curl)
├── index.html          # Static landing page (GitHub Pages)
├── serve.sh            # Local dev server
├── scripts/            # All user-facing scripts
│   ├── mc.sh
│   └── ram.sh
└── docs/features/      # Feature documentation
```

## Script Metadata Convention
Every script in `scripts/` MUST have these metadata comments right after the shebang:
```bash
#!/usr/bin/env bash
# @name Script Name
# @desc One-line description
# @sudo true|false
```
- `@name` — Display name shown in the launcher and landing page
- `@desc` — One-line description
- `@sudo` — Whether root privileges are needed

## Adding a New Script
1. Create the script in `scripts/` with `@name`, `@desc`, `@sudo` metadata.
2. Add the filename to the `SCRIPTS` array in `run.sh`.
3. Add an entry to the `SCRIPTS` array in `index.html`.
4. Update `README.md` script list.

## Script Styling Rules
All scripts must use these consistent conventions:
- **Colours**: `RED`, `YELLOW`, `GREEN`, `CYAN`, `BOLD`, `DIM`, `RESET` (same ANSI codes).
- **Helpers**: `ok()` → green `✔`, `warn()` → yellow `!`, `die()` → red `✖`.
- **Spinner**: Braille characters (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) in cyan.
- **User prompts**: Read from `/dev/tty` (not stdin) for `curl | bash` compatibility.
- Scripts must NOT require `sudo` to launch. Escalate dynamically when needed.

## README Style Guidelines
When adding/editing a feature in the `README.md`, always adhere to:
1. **Keep it Minimal**: Avoid long, verbose paragraphs or extensive prose.
2. **List Features Concisely**: Use concise bulleted lists.
3. **Show Core Commands**: Present execution commands in syntax-highlighted code blocks.
4. **No Fluff**: Keep the overall footprint as minimal as possible while remaining informative.