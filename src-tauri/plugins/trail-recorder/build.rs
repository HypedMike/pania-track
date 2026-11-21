const COMMANDS: &[&str] = &["start", "stop", "take_points", "request_permissions"];

fn main() {
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .build();
}
