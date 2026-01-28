def main [] {
    let os = $nu.os-info.name
    let home = $env.HOME? | default ($env.USERPROFILE? | default "~")
    
    let path = if $os == "windows" {
        ($env.APPDATA | path join "Blender Foundation" "Blender")
    } else if $os == "macos" {
        ($home | path join "Library" "Application Support" "Blender")
    } else {
        ($home | path join ".config" "blender")
    }
    
    { BLENDER_CONFIG: $path } | to json
}
