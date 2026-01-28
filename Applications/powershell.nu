def main [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")
    
    let path = if $os == "windows" {
        ($env.USERPROFILE | path join "Documents" "PowerShell")
    } else {
        # macOS and Linux use the same path for PowerShell Core usually
        ($home | path join ".config" "powershell")
    }
    
    { PS_PROFILE_DIR: $path } | to json
}
