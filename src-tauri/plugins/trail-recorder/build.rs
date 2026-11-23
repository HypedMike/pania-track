const COMMANDS: &[&str] = &["start", "stop", "take_points", "request_permissions", "live_update_status", "open_live_update_settings"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .build();
}
