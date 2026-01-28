# Nutuck

A pure Nushell implementation of a "Tuckr-like" dotfile manager.

## 1. Overview
Nutuck is a lightweight, dependency-free (other than Nushell) dotfile manager designed for cross-platform environments. It manages symbolic links between your dotfiles repository and your system's configuration paths.

**Key Features:**
- **Zero Dependencies**: Written entirely in Nushell.
- **Cross-Platform**: Works on Windows (requires Admin), macOS, and Linux.
- **Smart Variables**: Uses `%VARIABLE%` syntax in directory names to map to dynamic, OS-specific paths (e.g., `%APPDATA%`, `%CODE_USER%`).
- **Conditional Packages**: Automatically filters packages based on OS suffixes (e.g., `_windows`, `_macos`).
- **Plugin System**: Extensible variable definitions via simple Nushell scripts in `Applications/`.

## 2. Directory Structure

The repository relies on a specific structure relative to the `nutuck` script:

```
.
├── Configs/                   # Your actual dotfiles live here
│   ├── git/                   # Package: "git"
│   │   └── .gitconfig         # Links to ~/.gitconfig
│   ├── vscode/                # Package: "vscode"
│   │   └── %CODE_USER%/       # Dynamic Folder (Maps to OS-specific VS Code path)
│   │       └── settings.json  # Links to that mapped path
│   └── powershell_windows/    # Package: "powershell" (Windows Only)
│       └── ...
├── nutuck/                    # The Nutuck tool itself
│   ├── Applications/          # Plugin scripts defining variables
│   ├── nutuck.nu              # Main executable script
│   └── ...
```

## 3. Usage

### Prerequisites
- **Nushell** must be installed and in your PATH.
- **Windows Users**: You must run your terminal as **Administrator** or enable **Developer Mode** to create symbolic links.

### Basic Commands
Run the script from the root of your repository (or inside `nutuck/`):

```bash
# Link all packages (Safe: skips if target exists and is different)
nu nutuck/nutuck.nu

# Dry run (See what would happen without changes)
nu nutuck/nutuck.nu --dry-run

# Check status of links
nu nutuck/nutuck.nu --status

# Force overwrite existing files
nu nutuck/nutuck.nu --overwrite

# Unlink (Remove symlinks)
nu nutuck/nutuck.nu --unlink
```

### Configuration (`config.toml`)
Located at `nutuck/config.toml`.
- `mode = "git"` (Default): Auto-detects `Configs/` folder in the parent directory.
- `mode = "path"`: Uses a hardcoded path specified in `config_path`.

## 4. Creating Packages

To add a new tool (e.g., `mpv`):

1.  Create a folder `Configs/mpv`.
2.  Place files inside relative to the user's **HOME** directory.
    -   `Configs/mpv/.config/mpv/mpv.conf` -> Links to `~/.config/mpv/mpv.conf`.

### Using Smart Variables
If a tool lives in a weird location (like `%APPDATA%` on Windows vs `~/.config` on Linux), use Smart Variables.

1.  Check `nutuck/Applications/*.nu` to see available variables (or add your own).
    -   Example: `vscode.nu` defines `CODE_USER`.
2.  Create a folder with the variable name wrapped in `%`.
    -   `Configs/vscode/%CODE_USER%/settings.json`
3.  Nutuck will expand `%CODE_USER%` to the correct path for the current OS.

### OS-Specific Packages
Suffix your package folder name to restrict it to an OS:
-   `Configs/autohotkey_windows` (Runs only on Windows)
-   `Configs/i3_linux` (Runs only on Linux)
-   `Configs/yabai_macos` (Runs only on macOS)

## 5. Plugin System (Applications/)
Nutuck loads variables dynamically by executing scripts in `nutuck/Applications/`.
Each script must:
1.  Be named `toolname.nu`.
2.  Output a JSON object with variable definitions.

**Example (`vscode.nu`):**
```nu
def main [] {
    let path = if $nu.os-info.name == "windows" { ... } else { ... }
    { CODE_USER: $path } | to json
}
```
This defines the `%CODE_USER%` variable available for use in folder names.
