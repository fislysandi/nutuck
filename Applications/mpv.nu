def main [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")
    
    let path = if $os == "windows" {
        ($env.APPDATA | path join "mpv")
    } else {
        # Standard XDG path for Linux and macOS
        ($home | path join ".config" "mpv")
    }
    
    { MPV_HOME: $path } | to json
}
