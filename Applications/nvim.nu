def main [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")
    
    let config_path = if $os == "windows" {
        ($env.LOCALAPPDATA | path join "nvim")
    } else {
        ($home | path join ".config" "nvim")
    }
    
    { NVIM_CONFIG: $config_path } | to json
}
