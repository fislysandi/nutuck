def main [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")

    let config_root = if $os == "windows" {
        $env.USERPROFILE? | default "~"
    } else {
        ($home | path join ".claude")
    }

    if ($config_root | is-empty) {
        {} | to json
    } else {
        {
            CLAUDE_CONFIG_ROOT: $config_root
        } | to json
    }
}
