#!/usr/bin/env nu

# Nutuck: Pure Nushell Dotfile Linker
# Implements "Tuckr-like" logic with variable expansion and OS detection.

def main [--overwrite, --dry-run, --unlink, --status] {
    # Security: Refuse to run as root on Unix
    if $nu.os-info.name != "windows" {
        let current_uid = (do -i { id -u } | complete).stdout | str trim
        if $current_uid == "0" or $env.USER? == "root" {
            print $"(ansi red)Error: Running as root is unsafe. Please run as a normal user.(ansi reset)"
            exit 1
        }
    }

    # Validate mutually exclusive flags
    if $unlink and $status {
        print $"(ansi red)Error: Cannot use --unlink and --status together.(ansi reset)"
        exit 1
    }

    let mode = if $unlink { "unlink" } else if $status { "status" } else { "link" }

    if $mode == "link" or $mode == "unlink" {
        print $"(ansi cyan)Starting Nutuck... Mode: ($mode | str upcase)(ansi reset)"
    } else {
        print $"(ansi cyan)Nutuck Status Report(ansi reset)"
        print $"(ansi grey)Legend: [OK] Correct | [MISS] Missing | [DIFF] Different target | [TYPE] Not a symlink(ansi reset)\n"
    }
    
    # 1. Setup Environment Variables for "Smart" paths
    let env_vars = (setup-env-vars)
    
    # 2. Load Configuration and Locate Configs Directory
    let script_dir = ($env.FILE_PWD | path expand)
    
    # Attempt to read config.toml
    let config_file = ($script_dir | path join "config.toml")
    let config = if ($config_file | path exists) {
        open $config_file
    } else {
        { mode: "git" }
    }

    # Determine Configs directory based on mode
    let configs_dir = if $config.mode == "git" {
        # git mode: Auto-detect location
        let parent_configs = ($script_dir | path join ".." "Configs" | path expand)
        let current_configs = ($script_dir | path join "Configs" | path expand)
        
        if ($parent_configs | path exists) {
            $parent_configs
        } else if ($current_configs | path exists) {
            $current_configs
        } else {
            $parent_configs
        }
    } else if $config.mode == "path" {
        if ($config.config_path? | is-empty) {
            print $"(ansi red)Error: mode is 'path' but 'config_path' is missing or empty in config.toml(ansi reset)"
            return
        }
        $config.config_path | path join "Configs"
    } else {
        print $"(ansi red)Error: Unknown mode '($config.mode)' in config.toml.(ansi reset)"
        return
    }

    if not ($configs_dir | path exists) {
        print $"(ansi red)Error: Configs directory not found at ($configs_dir)(ansi reset)"
        return
    }

    # 3. Process Packages
    let packages = (ls $configs_dir | where type == dir)
    
    for pkg in $packages {
        let pkg_name = ($pkg.name | path basename)
        
        if (should-process-package $pkg.name) {
            if $mode != "status" {
                print $"\n(ansi blue)Processing package: ($pkg_name)(ansi reset)"
            }
            process-package $pkg.name $env_vars $overwrite $dry_run $mode
        }
    }
    
    if $mode != "status" {
        print $"\n(ansi green)Nutuck complete!(ansi reset)"
    }
}

# --- Core Logic ---

def setup-env-vars [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")
    
    # Base variables
    mut vars = {
        HOME: $home
    }

    # Platform specific additions
    if $os == "windows" {
        $vars = ($vars | merge {
            APPDATA: $env.APPDATA
            LOCALAPPDATA: $env.LOCALAPPDATA
        })
    }

    # Dynamic Plugin Loading
    let script_dir = ($env.FILE_PWD | path expand)
    let app_dir = ($script_dir | path join "Applications")
    
    if ($app_dir | path exists) {
        let plugins = (ls $app_dir | where name ends-with ".nu")
        
        for plugin in $plugins {
            let result = (do { ^$nu.current-exe $plugin.name } | complete)
            
            if $result.exit_code == 0 {
                try {
                    let plugin_vars = ($result.stdout | from json)
                    $vars = ($vars | merge $plugin_vars)
                } catch {
                    print $"(ansi red)Error parsing JSON from ($plugin.name | path basename)(ansi reset)"
                }
            } else {
                print $"(ansi red)Error executing plugin ($plugin.name | path basename)(ansi reset)"
            }
        }
    }
    
    $vars
}

def should-process-package [pkg_path: string] {
    let name = ($pkg_path | path basename)
    let os = $nu.os-info.name
    
    # 1. Check Name Suffix
    if ($name | str ends-with "_windows") and ($os != "windows") { return false }
    if ($name | str ends-with "_macos") and ($os != "macos" and $os != "darwin") { return false }
    if ($name | str ends-with "_linux") and ($os != "linux") { return false }

    # 2. Check .nutuck-ignore
    mut ignore_file = ($pkg_path | path join ".nutuck-ignore")
    if not ($ignore_file | path exists) {
        $ignore_file = ($pkg_path | path join ".nutuck_ignore")
    }

    if ($ignore_file | path exists) {
        let content = (open $ignore_file | lines | each { str trim } | where { $in != "" })
        if ("all" in $content) { return false }
        if ($os in $content) { return false }
    }
    
    return true
}

def process-package [pkg_path: string, env_map: record, overwrite: bool, dry_run: bool, mode: string] {
    let path_ignores = (load-package-path-ignores $pkg_path)
    let directory_link = (get-directory-link $pkg_path $env_map $path_ignores)

    if $directory_link != null {
        handle-target $directory_link.src $directory_link.dest "dir" $overwrite $dry_run $mode
    } else {
        walk-and-process $pkg_path $env_map.HOME $env_map $overwrite $dry_run $mode true [] $path_ignores
    }
}

def walk-and-process [current_path: string, target_base: string, env_map: record, overwrite: bool, dry_run: bool, mode: string, is_package_root: bool, rel_parts: list<string>, path_ignores: list<string>] {
    let items = (ls -a $current_path)
    
    for item in $items {
        let name = ($item.name | path basename)
        let next_rel_parts = ($rel_parts | append $name)
        
        if (should-ignore-item $name $is_package_root) or (should-ignore-relative-path $next_rel_parts $path_ignores) {
            continue
        }
        
        # Variable Expansion
        let target_name = (expand-target-name $name $env_map)

        if $target_name == null { continue }
        
        let new_target_base = (join-target-path $target_base $target_name)

        if $item.type == "dir" {
            walk-and-process $item.name $new_target_base $env_map $overwrite $dry_run $mode false $next_rel_parts $path_ignores
        } else {
            handle-target $item.name $new_target_base "file" $overwrite $dry_run $mode
        }
    }
}

def load-package-path-ignores [pkg_path: string] {
    mut ignore_file = ($pkg_path | path join ".nutuck-path-ignore")
    if not ($ignore_file | path exists) {
        $ignore_file = ($pkg_path | path join ".nutuck_path_ignore")
    }

    if not ($ignore_file | path exists) {
        return []
    }

    open $ignore_file | lines | each { str trim } | where { |line| $line != "" and not ($line | str starts-with "#") }
}

def should-ignore-relative-path [rel_parts: list<string>, path_ignores: list<string>] {
    if ($path_ignores | is-empty) {
        return false
    }

    let rel_path = ($rel_parts | str join "/")
    for rule in $path_ignores {
        if $rel_path == $rule {
            return true
        }

        if ($rel_path | str starts-with ($rule + "/")) {
            return true
        }
    }

    false
}

def should-ignore-item [name: string, is_package_root: bool] {
    if $name == ".nutuck-ignore" or $name == ".nutuck_ignore" or $name == ".DS_Store" or $name == ".git" {
        return true
    }

    if $is_package_root and ($name == "README.md" or $name == "LICENSE") {
        return true
    }

    false
}

def expand-target-name [name: string, env_map: record] {
    if ($name | str starts-with "%") and ($name | str ends-with "%") {
        let var_key = ($name | str substring 1..-2)
        if ($var_key in $env_map) {
            return ($env_map | get $var_key)
        }

        print $"(ansi red)Warning: Unknown variable %($var_key)% in path. Skipping.(ansi reset)"
        return null
    }

    $name
}

def is-absolute-target [target_name: string] {
    if $nu.os-info.name == "windows" {
        return (($target_name | str contains ":") or ($target_name | str starts-with "\\") or ($target_name | str starts-with "/"))
    }

    $target_name | str starts-with "/"
}

def join-target-path [target_base: string, target_name: string] {
    if (is-absolute-target $target_name) {
        $target_name
    } else {
        $target_base | path join $target_name
    }
}

def handle-target [src: string, dest: string, kind: string, overwrite: bool, dry_run: bool, mode: string] {
    if $mode == "status" {
        check-status $src $dest $kind
    } else if $mode == "unlink" {
        perform-unlink $src $dest $kind $dry_run
    } else {
        perform-link $src $dest $kind $overwrite $dry_run
    }
}

def collect-deployable-files [current_path: string, rel_parts: list<string>, is_package_root: bool, path_ignores: list<string>] {
    mut files = []

    for item in (ls -a $current_path) {
        let name = ($item.name | path basename)
        let next_parts = ($rel_parts | append $name)

        if (should-ignore-item $name $is_package_root) or (should-ignore-relative-path $next_parts $path_ignores) {
            continue
        }

        if $item.type == "dir" {
            let nested = (collect-deployable-files $item.name $next_parts false $path_ignores)
            for entry in $nested {
                $files = ($files | append $entry)
            }
        } else {
            $files = ($files | append { parts: $next_parts })
        }
    }

    $files
}

def parent-parts [parts: list<string>] {
    if ($parts | length) <= 1 {
        return []
    }

    mut result = []
    let max_index = (($parts | length) - 2)

    for idx in 0..$max_index {
        $result = ($result | append ($parts | get $idx))
    }

    $result
}

def common-prefix [paths: list<list<string>>] {
    if ($paths | is-empty) {
        return []
    }

    mut prefix = ($paths | first)

    for path_parts in ($paths | skip 1) {
        let limit = if (($prefix | length) < ($path_parts | length)) {
            $prefix | length
        } else {
            $path_parts | length
        }

        if $limit == 0 {
            return []
        }

        mut next_prefix = []

        for idx in 0..($limit - 1) {
            if (($prefix | get $idx) == ($path_parts | get $idx)) {
                $next_prefix = ($next_prefix | append ($prefix | get $idx))
            } else {
                break
            }
        }

        $prefix = $next_prefix

        if ($prefix | is-empty) {
            return []
        }
    }

    $prefix
}

def join-path-parts [base: string, parts: list<string>] {
    mut current = $base

    for part in $parts {
        $current = ($current | path join $part)
    }

    $current
}

def resolve-target-parts [parts: list<string>, env_map: record] {
    mut current = $env_map.HOME

    for part in $parts {
        let target_name = (expand-target-name $part $env_map)
        if $target_name == null {
            return null
        }

        $current = (join-target-path $current $target_name)
    }

    $current
}

def is-safe-directory-target [dest: string, env_map: record] {
    let expanded_dest = ($dest | path expand)
    let anchor_scopes = (get-directory-link-scopes $env_map)

    for scope in $anchor_scopes {
        let rel_parts = (relative-path-parts $expanded_dest $scope.root)

        if $rel_parts == null {
            continue
        }

        if ($rel_parts | is-empty) {
            return false
        }

        for protected_root in $scope.protected_roots {
            if $rel_parts == $protected_root {
                return false
            }
        }

        return true
    }

    false
}

def get-directory-link-scopes [env_map: record] {
    mut scopes = [
        {
            root: ($env_map.HOME | path expand)
            protected_roots: [
                []
                [".config"]
                [".local"]
                [".local" "share"]
                ["Library"]
                ["Library" "Application Support"]
                ["Library" "Preferences"]
                ["AppData"]
                ["AppData" "Roaming"]
                ["AppData" "Local"]
                ["Documents"]
            ]
        }
    ]

    if ("APPDATA" in $env_map) {
        $scopes = ($scopes | append {
            root: (($env_map | get APPDATA) | path expand)
            protected_roots: [ [] ]
        })
    }

    if ("LOCALAPPDATA" in $env_map) {
        $scopes = ($scopes | append {
            root: (($env_map | get LOCALAPPDATA) | path expand)
            protected_roots: [ [] ]
        })
    }

    $scopes
}

def normalize-path-parts [path_value: string] {
    (($path_value | path expand) | str replace -a "\\" "/" | split row "/" | where { |part| $part != "" })
}

def relative-path-parts [path_value: string, root_value: string] {
    let path_parts = (normalize-path-parts $path_value)
    let root_parts = (normalize-path-parts $root_value)

    if ($root_parts | length) > ($path_parts | length) {
        return null
    }

    for idx in 0..(($root_parts | length) - 1) {
        if (($path_parts | get $idx) != ($root_parts | get $idx)) {
            return null
        }
    }

    if ($path_parts | length) == ($root_parts | length) {
        return []
    }

    let start = ($root_parts | length)
    let end = (($path_parts | length) - 1)

    $path_parts | slice $start..$end
}

def can-overwrite-target [dest: string] {
    let dest_type = ($dest | path type)

    if $dest_type == null {
        return true
    }

    if $dest_type == "dir" {
        print $"(ansi red)Refusing to remove real directory: ($dest)(ansi reset)"
        print $"(ansi yellow)Use a stronger manual cleanup step before rerunning. --overwrite only removes files and symlinks.(ansi reset)"
        return false
    }

    true
}

def get-directory-link [pkg_path: string, env_map: record, path_ignores: list<string>] {
    let files = (collect-deployable-files $pkg_path [] true $path_ignores)
    if ($files | is-empty) {
        return null
    }

    let parent_paths = ($files | each { |entry| parent-parts $entry.parts })
    let shared_parts = (common-prefix $parent_paths)

    if ($shared_parts | is-empty) {
        return null
    }

    let dest = (resolve-target-parts $shared_parts $env_map)
    if $dest == null {
        return null
    }

    if not (is-safe-directory-target $dest $env_map) {
        return null
    }

    let src = (join-path-parts $pkg_path $shared_parts)
    { src: $src, dest: $dest }
}

def get-symlink-target [path: string] {
    # Cross-platform way to get symlink target
    # Path must be a symlink
    try {
        let meta = (ls -l $path | first)
        if ($meta.type == "symlink") {
            return $meta.target
        }
    }
    null
}

def is-linked-correctly [src: string, dest: string] {
    if not ($dest | path exists) { return false }
    if ($dest | path type) != "symlink" { return false }
    
    # Check target
    # We compare absolute paths
    let real_src = ($src | path expand)
    let real_dest_target = ($dest | path expand)
    
    $real_src == $real_dest_target
}

def check-status [src: string, dest: string, kind: string] {
    # Truncate dest for display if too long
    # let dest_display = if ($dest | str length) > 50 { "..." + ($dest | str substring ($dest | str length) - 47..) } else { $dest }
    let dest_display = $dest

    if not ($dest | path exists) {
         print $"(ansi red)[MISS](ansi reset) ($dest_display) [($kind)]"
         return
    }
    
    let type = ($dest | path type)
    if $type != "symlink" {
         print $"(ansi yellow)[TYPE](ansi reset) ($dest_display) [($kind)] (Found: ($type))"
         return
    }
    
     if (is-linked-correctly $src $dest) {
         print $"(ansi green)[ OK ](ansi reset) ($dest_display) [($kind)]"
     } else {
         print $"(ansi yellow)[DIFF](ansi reset) ($dest_display) [($kind)] -> (get-symlink-target $dest)"
     }
}

def perform-unlink [src: string, dest: string, kind: string, dry_run: bool] {
    if not ($dest | path exists) { return }
    
    if (is-linked-correctly $src $dest) {
        if $dry_run {
            print $"(ansi cyan)[Dry Run] Unlinking ($kind): ($dest)(ansi reset)"
        } else {
            print $"Unlinking ($kind): ($dest)"
            try { rm $dest } catch { print $"(ansi red)Failed to unlink ($dest)(ansi reset)" }
            
            # Optional: Clean up empty parent directory
            let parent = ($dest | path dirname)
            if (ls $parent | is-empty) {
                print $"Removing empty directory: ($parent)"
                try { rmdir $parent }
            }
        }
    } else {
        # Warning: skipping unlink because it's not ours or it's a real file
        # print $"(ansi grey)Skip Unlink: ($dest) does not point to ($src)(ansi reset)"
    }
}

def perform-link [src: string, dest: string, kind: string, overwrite: bool, dry_run: bool] {
    # Check if already linked correctly - Smart Existence Check
    if (is-linked-correctly $src $dest) {
        # print $"(ansi green)Skip: ($dest) already linked(ansi reset)"
        return
    }

    # Ensure parent directory exists
    let parent = ($dest | path dirname)
    let parent_type = ($parent | path type)

    if $parent_type == null {
        if $dry_run {
            print $"(ansi grey)[Dry Run] mkdir ($parent)(ansi reset)"
        } else {
            mkdir $parent
        }
    } else {
        # Check if parent is a directory
         if ($parent | path type) != "dir" {
             # Technically could be a symlink to a dir, which 'path type' reports as symlink
             # Try entering it
             let is_dir = do { try { cd $parent; true } catch { false } }
             if not $is_dir {
                 print $"(ansi red)Error: Parent ($parent) exists but is not a directory.(ansi reset)"
                 return
             }
         }
    }
    
    # Check if link/file exists (and we know it's not correct from check above)
    if ($dest | path type) != null {
        if $overwrite {
             if not (can-overwrite-target $dest) {
                 return
             }

              if $dry_run {
                  print $"(ansi yellow)[Dry Run] Overwriting: ($dest)(ansi reset)"
              } else {
                 print $"(ansi yellow)Overwriting: ($dest)(ansi reset)"
                 try { rm $dest } catch { rm -f $dest }
             }
        } else {
             print $"(ansi yellow)Skip: ($dest) exists. Use --overwrite to fix.(ansi reset)"
             return
        }
    }
    
    if $dry_run {
        print $"(ansi cyan)[Dry Run] Linking ($kind): ($src | path basename) -> ($dest)(ansi reset)"
        return
    }

    print $"Linking ($kind): ($src | path basename) -> ($dest)"
    
    try {
        if $nu.os-info.name == "windows" {
            # Windows Symlink
            let w_dest = ($dest | str replace -a "/" "\\")
            let w_src = ($src | str replace -a "/" "\\")
            if $kind == "dir" {
                ^cmd /c mklink /D $w_dest $w_src
            } else {
                ^cmd /c mklink $w_dest $w_src
            }
        } else {
            # Unix Symlink
            ^ln -s $src $dest
        }
    } catch {
        print $"(ansi red)Failed to link ($dest)(ansi reset)"
        if $nu.os-info.name == "windows" {
            print $"(ansi yellow)Windows may require Developer Mode or elevated permissions for symlink creation.(ansi reset)"
        }
    }
}
