def main [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")
    
    let path = if $os == "windows" {
        ($env.APPDATA | path join "nushell")
    } else if $os == "macos" {
        ($home | path join "Library" "Application Support" "nushell")
    } else {
        ($home | path join ".config" "nushell")
    }
    
    { NU_HOME: $path } | to json
}
