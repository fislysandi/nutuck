def main [] {
    let os = $nu.os-info.name
    if $os == "windows" {
        # Standard Package ID for Windows Terminal
        let package_id = "Microsoft.WindowsTerminal_8wekyb3d8bbwe"
        let local_app_data = $env.LOCALAPPDATA
        let config_path = ($local_app_data | path join "Packages" $package_id "LocalState")
        
        { WT_CONFIG_DIR: $config_path } | to json
    } else {
        {} | to json
    }
}
