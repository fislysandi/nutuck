def main [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")

    let config_root = if $os == "windows" {
        $env.APPDATA? | default ($env.USERPROFILE? | default "~")
    } else {
        ($home | path join ".config")
    }

    let data_root = if $os == "windows" {
        $env.LOCALAPPDATA? | default ($env.USERPROFILE? | default "~")
    } else {
        ($home | path join ".local" "share")
    }

    let state_root = if $os == "windows" {
        $env.LOCALAPPDATA? | default ($env.USERPROFILE? | default "~")
    } else {
        ($home | path join ".local" "state")
    }

    if ($config_root | is-empty) {
        {} | to json
    } else {
        {
            OPENCODE_CONFIG_ROOT: $config_root
            OPENCODE_DATA_ROOT: $data_root
            OPENCODE_STATE_ROOT: $state_root
        } | to json
    }
}
