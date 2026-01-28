def main [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")
    
    let path = if $os == "windows" {
        ($env.APPDATA | path join "Code" "User")
    } else if $os == "macos" {
        ($home | path join "Library" "Application Support" "Code" "User")
    } else {
        ($home | path join ".config" "Code" "User")
    }
    
    { CODE_USER: $path } | to json
}
