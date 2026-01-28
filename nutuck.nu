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
    
    # Check for Administrator privileges on Windows (only needed for linking/unlinking)
    if $nu.os-info.name == "windows" and $mode != "status" {
        let is_admin = (do -i { net session } | complete).exit_code == 0
        if not $is_admin {
            print $"(ansi red)Error: This script requires Administrator privileges on Windows to manage symbolic links.(ansi reset)"
            print $"(ansi yellow)Please run this terminal as Administrator or enable Developer Mode.(ansi reset)"
            return
        }
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
    walk-and-process $pkg_path $env_map.HOME $env_map $overwrite $dry_run $mode
}

def walk-and-process [current_path: string, target_base: string, env_map: record, overwrite: bool, dry_run: bool, mode: string] {
    let items = (ls -a $current_path)
    
    for item in $items {
        let name = ($item.name | path basename)
        
        if $name == ".nutuck-ignore" or $name == ".nutuck_ignore" or $name == ".DS_Store" or $name == ".git" {
            continue
        }
        
        # Variable Expansion
        let target_name = if ($name | str starts-with "%") and ($name | str ends-with "%") {
            let var_key = ($name | str substring 1..-2)
            if ($var_key in $env_map) {
                $env_map | get $var_key
            } else {
                print $"(ansi red)Warning: Unknown variable %($var_key)% in path. Skipping.(ansi reset)"
                null
            }
        } else {
            $name
        }

        if $target_name == null { continue }
        
        let is_absolute = if $nu.os-info.name == "windows" {
            ($target_name | str contains ":") or ($target_name | str starts-with "\\") or ($target_name | str starts-with "/")
        } else {
             $target_name | str starts-with "/"
        }

        let new_target_base = if $is_absolute {
             $target_name
        } else {
             $target_base | path join $target_name
        }

        if $item.type == "dir" {
            walk-and-process $item.name $new_target_base $env_map $overwrite $dry_run $mode
        } else {
            handle-file $item.name $new_target_base $overwrite $dry_run $mode
        }
    }
}

def handle-file [src: string, dest: string, overwrite: bool, dry_run: bool, mode: string] {
    if $mode == "status" {
        check-status $src $dest
    } else if $mode == "unlink" {
        perform-unlink $src $dest $dry_run
    } else {
        perform-link $src $dest $overwrite $dry_run
    }
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

def check-status [src: string, dest: string] {
    let src_display = ($src | path basename)
    # Truncate dest for display if too long
    # let dest_display = if ($dest | str length) > 50 { "..." + ($dest | str substring ($dest | str length) - 47..) } else { $dest }
    let dest_display = $dest

    if not ($dest | path exists) {
         print $"(ansi red)[MISS](ansi reset) ($dest_display)"
         return
    }
    
    let type = ($dest | path type)
    if $type != "symlink" {
         print $"(ansi yellow)[TYPE](ansi reset) ($dest_display) (Found: ($type))"
         return
    }
    
    if (is-linked-correctly $src $dest) {
         print $"(ansi green)[ OK ](ansi reset) ($dest_display)"
    } else {
         print $"(ansi yellow)[DIFF](ansi reset) ($dest_display) -> (get-symlink-target $dest)"
    }
}

def perform-unlink [src: string, dest: string, dry_run: bool] {
    if not ($dest | path exists) { return }
    
    if (is-linked-correctly $src $dest) {
        if $dry_run {
            print $"(ansi cyan)[Dry Run] Unlinking: ($dest)(ansi reset)"
        } else {
            print $"Unlinking: ($dest)"
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

def perform-link [src: string, dest: string, overwrite: bool, dry_run: bool] {
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
        print $"(ansi cyan)[Dry Run] Linking: ($src | path basename) -> ($dest)(ansi reset)"
        return
    }

    print $"Linking: ($src | path basename) -> ($dest)"
    
    try {
        if $nu.os-info.name == "windows" {
            # Windows Symlink
            let w_dest = ($dest | str replace -a "/" "\\")
            let w_src = ($src | str replace -a "/" "\\")
            ^cmd /c mklink $w_dest $w_src
        } else {
            # Unix Symlink
            ^ln -s $src $dest
        }
    } catch {
        print $"(ansi red)Failed to link ($dest)(ansi reset)"
    }
}
