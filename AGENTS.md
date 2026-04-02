# Nutuck - Agent Documentation

This file documents the internal logic and workflows for AI Agents (LLMs) interacting with or modifying the Nutuck dotfile manager.

## 1. System Architecture

Nutuck is a **symlink manager**. It mirrors a directory structure from a source (`Configs/`) to a target (usually `$HOME`).

### Core Logic (`nutuck.nu`)
1.  **Environment Setup**: 
    -   Loads standard env vars (`HOME`, `APPDATA`, `LOCALAPPDATA`).
    -   Executes all scripts in `Applications/*.nu` and merges their JSON output into the environment map.
2.  **Config Discovery**: Finds the `Configs/` directory (usually `../Configs`).
3.  **Traversal**: Walks through each directory in `Configs/`.
4.  **Variable Expansion**: If a folder name is `%VAR%`, it looks up `VAR` in the environment map. If found, it changes the traversal base path to that value.
5.  **Linking**:
    -   **Windows**: `cmd /c mklink` (Hard requirement: Admin/Dev Mode).
    -   **Unix**: `ln -s`.

## 2. Working with Variables

When a user asks to configure a tool that has different paths on different OSs (e.g., VS Code, Sublime, Obsidian), you must use **Smart Variables**.

### How to identify variables
1.  **Read** files in `nutuck/Applications/`.
2.  Look for the JSON output structure.
    - Example: `Applications/vscode.nu` returns `{ "CODE_USER": "..." }`.
3. The variable name to use in the folder structure is `%CODE_USER%`.
4. For tools with platform-specific paths, create or use an appropriate variable.

### How to add new variables
If a supported tool is missing (e.g., "Obsidian"):
1.  Create `nutuck/Applications/obsidian.nu`.
2.  Implement logic to determine the path based on `$nu.os-info.name`.
3.  Output `{ OBSIDIAN_VAULT: $path } | to json`.
4.  You can now use `%OBSIDIAN_VAULT%` in the `Configs/` structure.

## 3. Creating Configuration Packages

When asked to "add dotfiles for X":

1.  **Determine Structure**:
    -   Does X use standard XDG paths (`~/.config/x`)? 
        -   -> Create `Configs/x/.config/x/config_file`.
    -   Does X use platform-specific paths?
        -   -> Check for an existing variable in `Applications/`.
        -   -> If none, create a simple relative structure or add a new plugin.

2.  **Platform Specifics**:
    -   If the config is **strictly** for one OS, append the suffix to the package name in `Configs/`.
        -   `Configs/pwsh_windows/`
    -   If the config is shared but has minor differences, consider using the `%VARIABLE%` approach which handles the path difference, effectively sharing the file.

## 4. Maintenance Tasks

### Fixing Broken Links
If `nu nutuck/nutuck.nu --status` reports `[DIFF]` or `[MISS]`:
1.  Verify the source file exists in `Configs/`.
2.  Verify the target path logic (is the `%VARIABLE%` resolving correctly?).
3.  Run with `--overwrite` if the target is just an old file.

### Adding Ignored Files
To prevent specific files from being linked on specific OSs without separating the whole package:
1.  Create `.nutuck-ignore` in the package root.
2.  List the OS names (`windows`, `macos`, `linux`) to ignore.

## 5. Code Style for Plugins (`Applications/*.nu`)
-   **Pure Nushell**: No external binary calls if possible.
-   **Output**: MUST output valid JSON.
-   **Error Handling**: Return a safe default or empty JSON object on failure, do not crash.
-   **Idempotency**: The script should be read-only (do not modify files).
