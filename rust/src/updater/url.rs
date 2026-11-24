//! Which download addresses the updater accepts.
//!
//! The app asks the updater to download and install an APK, so the address is checked here,
//! in Rust, before anything reaches the native side: only assets of this project's GitHub
//! releases. (Android additionally refuses to install an APK that is not signed with the same
//! key as the installed app, so this is a second lock, not the only one.)

/// Releases of this repository. Must match `repoUrl` in `lib/core/app_info.dart`.
const RELEASE_PREFIX: &str = "https://github.com/HypedMike/pania-track/releases/download/";

pub fn validate_download_url(url: &str) -> Result<(), String> {
    let rest = url
        .strip_prefix(RELEASE_PREFIX)
        .ok_or("updates can only be downloaded from this project's GitHub releases")?;
    let ok_chars = rest
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '/' | '.' | '-' | '_' | '+'));
    // `<tag>/<file>.apk`: exactly two non-empty segments, no way to climb out of the path.
    let mut parts = rest.split('/');
    let (tag, file, extra) = (parts.next(), parts.next(), parts.next());
    let shaped = matches!((tag, file, extra), (Some(t), Some(f), None)
        if !t.is_empty() && !f.is_empty() && f.ends_with(".apk") && t != ".." && f != "..");
    if ok_chars && shaped && !rest.contains("..") {
        Ok(())
    } else {
        Err("not a release APK address".into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_a_release_apk() {
        assert!(validate_download_url("https://github.com/HypedMike/pania-track/releases/download/v1.4.0/pania-1.4.0.apk").is_ok());
    }

    #[test]
    fn rejects_everything_else() {
        for bad in [
            "",
            "http://github.com/HypedMike/pania-track/releases/download/v1/p.apk",
            "https://github.com/HypedMike/pania-track/releases/latest",
            "https://github.com/HypedMike/pania-track/releases/download/v1/p.zip",
            "https://github.com/HypedMike/pania-track/releases/download/v1/p.apk?x=1",
            "https://github.com/HypedMike/pania-track/releases/download/v1/p.apk#f",
            "https://github.com/HypedMike/pania-track/releases/download/v1/sub/p.apk",
            "https://github.com/HypedMike/pania-track/releases/download/../p.apk",
            "https://github.com/HypedMike/pania-track/releases/download/v1/../../x.apk",
            "https://github.com/HypedMike/pania-track/releases/download//p.apk",
            "https://github.com/HypedMike/pania-track/releases/download/v1/",
            "https://github.com.evil.example/HypedMike/pania-track/releases/download/v1/p.apk",
            "https://evil.example/https://github.com/HypedMike/pania-track/releases/download/v1/p.apk",
            "https://github.com/HypedMike/other-repo/releases/download/v1/p.apk",
            "https://github.com/HypedMike/pania-track/releases/download/v1/p.apk\n",
            "https://github.com/HypedMike/pania-track/releases/download/v1/p%2e.apk",
        ] {
            assert!(validate_download_url(bad).is_err(), "{bad:?} must be rejected");
        }
    }
}
