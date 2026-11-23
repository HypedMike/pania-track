const COMMANDS: &[&str] = &["can_install", "open_install_settings", "download_and_install"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .build();
}
