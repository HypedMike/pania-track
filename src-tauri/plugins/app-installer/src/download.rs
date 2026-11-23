//! Downloading the APK, in Rust, with progress.
//!
//! Redirects are followed by hand so every hop is checked against the [`Policy`] *before* it is
//! requested: the address the webview gave, and wherever GitHub redirects to (its CDN), must be
//! https and on an allowed host. The file is written to `<target>.part` and only renamed into
//! place when it is complete, so a half-downloaded APK is never handed to the installer.

use super::progress::{Progress, Tracker};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
use ureq::http::{header, StatusCode, Uri};

pub struct Policy {
    pub https_only: bool,
    pub host_allowed: fn(&str) -> bool,
    pub max_bytes: u64,
}

impl Policy {
    /// GitHub release assets: github.com redirects to its `*.githubusercontent.com` CDN.
    pub fn github_releases() -> Self {
        Policy {
            https_only: true,
            host_allowed: |host| host == "github.com" || host.ends_with(".githubusercontent.com"),
            max_bytes: 200 * 1024 * 1024,
        }
    }
}

const MAX_REDIRECTS: usize = 5;

fn check(uri: &Uri, policy: &Policy) -> Result<(), String> {
    let scheme = uri.scheme_str().unwrap_or("");
    if policy.https_only && scheme != "https" {
        return Err("the download must use https".into());
    }
    if scheme != "https" && scheme != "http" {
        return Err("unsupported address".into());
    }
    match uri.host() {
        Some(host) if (policy.host_allowed)(host) => Ok(()),
        Some(host) => Err(format!("downloads from {host} are not allowed")),
        None => Err("address without a host".into()),
    }
}

fn part_path(target: &Path) -> PathBuf {
    let mut name = target.file_name().unwrap_or_default().to_os_string();
    name.push(".part");
    target.with_file_name(name)
}

/// Downloads `url` to `target`, calling `on_progress` as bytes arrive and once more when done.
/// Returns the size. On any error nothing is left at `target`.
pub fn download(url: &str, target: &Path, policy: &Policy, mut on_progress: impl FnMut(Progress)) -> Result<u64, String> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .max_redirects(0)
        .http_status_as_error(false)
        .timeout_connect(Some(Duration::from_secs(15)))
        .timeout_recv_body(Some(Duration::from_secs(30)))
        .user_agent("pania-updater")
        .build()
        .into();

    let mut current: Uri = url.parse().map_err(|_| "invalid address".to_string())?;
    let response = {
        let mut hops = 0;
        loop {
            check(&current, policy)?;
            let response = agent.get(current.clone()).call().map_err(|e| format!("could not connect: {e}"))?;
            let status = response.status();
            if status == StatusCode::OK {
                break response;
            }
            if matches!(status.as_u16(), 301 | 302 | 303 | 307 | 308) {
                hops += 1;
                if hops > MAX_REDIRECTS {
                    return Err("too many redirects".into());
                }
                let location = response
                    .headers()
                    .get(header::LOCATION)
                    .and_then(|v| v.to_str().ok())
                    .ok_or("redirect without a location")?;
                current = location.parse().map_err(|_| "invalid redirect address".to_string())?;
                if current.scheme().is_none() {
                    return Err("relative redirects are not followed".into());
                }
                continue;
            }
            return Err(format!("server answered {}", status.as_u16()));
        }
    };

    let total = response.body().content_length();
    if total.is_some_and(|t| t > policy.max_bytes) {
        return Err("file is larger than expected".into());
    }
    if let Some(dir) = target.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let part = part_path(target);
    let result = (|| -> Result<u64, String> {
        let mut reader = response.into_body().into_reader();
        let mut file = fs::File::create(&part).map_err(|e| e.to_string())?;
        let mut tracker = Tracker::new(total, Instant::now());
        let mut buf = vec![0u8; 64 * 1024];
        let mut downloaded: u64 = 0;
        if let Some(p) = tracker.update(Instant::now(), 0) {
            on_progress(p);
        }
        loop {
            let n = reader.read(&mut buf).map_err(|e| format!("download interrupted: {e}"))?;
            if n == 0 {
                break;
            }
            downloaded += n as u64;
            if downloaded > policy.max_bytes {
                return Err("file is larger than expected".into());
            }
            file.write_all(&buf[..n]).map_err(|e| e.to_string())?;
            if let Some(p) = tracker.update(Instant::now(), downloaded) {
                on_progress(p);
            }
        }
        file.flush().map_err(|e| e.to_string())?;
        if downloaded == 0 {
            return Err("empty download".into());
        }
        if total.is_some_and(|t| t != downloaded) {
            return Err("download incomplete".into());
        }
        on_progress(tracker.finish(downloaded));
        Ok(downloaded)
    })();

    match result {
        Ok(size) => {
            fs::rename(&part, target).map_err(|e| e.to_string())?;
            Ok(size)
        }
        Err(e) => {
            let _ = fs::remove_file(&part);
            let _ = fs::remove_file(target);
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{BufRead, BufReader},
        net::TcpListener,
        sync::{Arc, Mutex},
        thread,
    };

    enum Reply {
        Body { bytes: usize, chunk: usize, pause_ms: u64 },
        Redirect(String),
        Status(u16),
        /// Promises `declared` bytes but sends only `sent`, then closes.
        Truncated { declared: usize, sent: usize },
        /// No Content-Length: sends `bytes` then closes.
        Unsized { bytes: usize },
    }

    /// A tiny HTTP server on localhost. Returns its port and the paths it was asked for.
    fn serve(routes: Vec<(&'static str, Reply)>) -> (u16, Arc<Mutex<Vec<String>>>) {
        serve_with(|_| routes.into_iter().map(|(p, r)| (p.to_string(), r)).collect())
    }

    /// Like `serve`, but the routes may mention the server's own port (for redirects).
    fn serve_with(build: impl FnOnce(u16) -> Vec<(String, Reply)>) -> (u16, Arc<Mutex<Vec<String>>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let routes = build(port);
        let seen = Arc::new(Mutex::new(Vec::new()));
        let log = seen.clone();
        let routes = Arc::new(routes);
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let (routes, log) = (routes.clone(), log.clone());
                thread::spawn(move || {
                    let mut stream = stream;
                    let mut line = String::new();
                    let mut reader = BufReader::new(stream.try_clone().unwrap());
                    reader.read_line(&mut line).unwrap();
                    loop {
                        let mut h = String::new();
                        reader.read_line(&mut h).unwrap();
                        if h == "\r\n" || h.is_empty() {
                            break;
                        }
                    }
                    let path = line.split_whitespace().nth(1).unwrap_or("/").to_string();
                    log.lock().unwrap().push(path.clone());
                    let reply = routes.iter().find(|(p, _)| *p == path).map(|(_, r)| r);
                    let data = |n: usize| (0..n).map(|i| (i % 251) as u8).collect::<Vec<u8>>();
                    let _ = match reply {
                        Some(Reply::Body { bytes, chunk, pause_ms }) => {
                            let body = data(*bytes);
                            let _ = write!(stream, "HTTP/1.1 200 OK\r\nContent-Length: {bytes}\r\nConnection: close\r\n\r\n");
                            for c in body.chunks(*chunk) {
                                if stream.write_all(c).is_err() {
                                    break;
                                }
                                thread::sleep(Duration::from_millis(*pause_ms));
                            }
                            Ok(())
                        }
                        Some(Reply::Redirect(to)) => write!(stream, "HTTP/1.1 302 Found\r\nLocation: {to}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),
                        Some(Reply::Truncated { declared, sent }) => {
                            let _ = write!(stream, "HTTP/1.1 200 OK\r\nContent-Length: {declared}\r\nConnection: close\r\n\r\n");
                            stream.write_all(&data(*sent))
                        }
                        Some(Reply::Unsized { bytes }) => {
                            let _ = write!(stream, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n");
                            stream.write_all(&data(*bytes))
                        }
                        Some(Reply::Status(code)) => write!(stream, "HTTP/1.1 {code} X\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),
                        None => write!(stream, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),
                    };
                });
            }
        });
        (port, seen)
    }

    fn local_policy(max_bytes: u64) -> Policy {
        Policy { https_only: false, host_allowed: |h| h == "127.0.0.1", max_bytes }
    }

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("pania-dl-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        dir.join("update.apk")
    }

    #[test]
    fn downloads_a_file_and_reports_size_speed_and_completion() {
        let (port, _) = serve(vec![("/a.apk", Reply::Body { bytes: 600_000, chunk: 30_000, pause_ms: 20 })]);
        let target = temp("ok");
        let mut reports: Vec<Progress> = vec![];
        let size = download(&format!("http://127.0.0.1:{port}/a.apk"), &target, &local_policy(10_000_000), |p| reports.push(p)).unwrap();
        assert_eq!(size, 600_000);
        let written = fs::read(&target).unwrap();
        assert_eq!(written.len(), 600_000);
        assert!(written.iter().enumerate().all(|(i, &b)| b == (i % 251) as u8), "content must match");
        assert!(!part_path(&target).exists(), "no .part file left behind");
        assert!(reports.len() >= 3, "{} reports", reports.len());
        assert!(reports.windows(2).all(|w| w[0].downloaded <= w[1].downloaded), "monotonic");
        assert!(reports.iter().all(|p| p.total == Some(600_000)));
        let last = reports.last().unwrap();
        assert!(last.done && last.downloaded == 600_000);
        assert!(reports.iter().any(|p| p.speed_bps > 100_000.0), "a speed was measured");
        assert!(reports.iter().filter(|p| !p.done).any(|p| p.eta_seconds.is_some()), "an eta was reported mid-download");
        let _ = fs::remove_dir_all(target.parent().unwrap());
    }

    #[test]
    fn follows_a_chain_of_allowed_redirects() {
        let (port, seen) = serve_with(|port| {
            vec![
                ("/a".into(), Reply::Redirect(format!("http://127.0.0.1:{port}/b"))),
                ("/b".into(), Reply::Redirect(format!("http://127.0.0.1:{port}/real.apk"))),
                ("/real.apk".into(), Reply::Body { bytes: 1000, chunk: 1000, pause_ms: 0 }),
            ]
        });
        let target = temp("redir");
        assert_eq!(download(&format!("http://127.0.0.1:{port}/a"), &target, &local_policy(1 << 20), |_| {}).unwrap(), 1000);
        assert_eq!(seen.lock().unwrap().as_slice(), ["/a", "/b", "/real.apk"]);
        let _ = fs::remove_dir_all(target.parent().unwrap());
    }

    #[test]
    fn a_redirect_loop_gives_up() {
        let (port, seen) = serve_with(|port| vec![("/loop".into(), Reply::Redirect(format!("http://127.0.0.1:{port}/loop")))]);
        let target = temp("loop");
        let err = download(&format!("http://127.0.0.1:{port}/loop"), &target, &local_policy(1 << 20), |_| {}).unwrap_err();
        assert!(err.contains("too many redirects"), "{err}");
        assert_eq!(seen.lock().unwrap().len(), MAX_REDIRECTS + 1);
    }

    #[test]
    fn a_relative_redirect_is_refused() {
        let (port, _) = serve(vec![("/rel", Reply::Redirect("/elsewhere.apk".into()))]);
        let err = download(&format!("http://127.0.0.1:{port}/rel"), &temp("rel"), &local_policy(1 << 20), |_| {}).unwrap_err();
        assert!(err.contains("relative") || err.contains("invalid redirect"), "{err}");
    }

    #[test]
    fn a_redirect_to_a_host_that_is_not_allowed_is_never_requested() {
        let (port, _) = serve(vec![("/go", Reply::Redirect("http://evil.example/steal.apk".into()))]);
        let target = temp("evil");
        let err = download(&format!("http://127.0.0.1:{port}/go"), &target, &local_policy(1 << 20), |_| {}).unwrap_err();
        assert!(err.contains("evil.example") && err.contains("not allowed"), "{err}");
        assert!(!target.exists());
    }

    #[test]
    fn production_policy_refuses_http_and_foreign_hosts() {
        let policy = Policy::github_releases();
        let target = temp("policy");
        for bad in ["http://github.com/x/y.apk", "https://evil.example/y.apk", "https://github.com.evil.example/y.apk", "file:///etc/passwd", "ftp://github.com/x"] {
            assert!(download(bad, &target, &policy, |_| {}).is_err(), "{bad}");
        }
        assert!((policy.host_allowed)("github.com") && (policy.host_allowed)("objects.githubusercontent.com"));
        assert!(!(policy.host_allowed)("githubusercontent.com.evil.example") && !(policy.host_allowed)("notgithub.com"));
    }

    #[test]
    fn errors_leave_nothing_behind() {
        let (port, _) = serve(vec![
            ("/missing", Reply::Status(404)),
            ("/short", Reply::Truncated { declared: 100_000, sent: 40_000 }),
            ("/big", Reply::Body { bytes: 50_000, chunk: 50_000, pause_ms: 0 }),
            ("/unsized-big", Reply::Unsized { bytes: 300_000 }),
            ("/empty", Reply::Body { bytes: 0, chunk: 1, pause_ms: 0 }),
        ]);
        let base = format!("http://127.0.0.1:{port}");
        let target = temp("err");
        let policy = local_policy(100_000);
        for (path, expect) in [("/missing", "404"), ("/short", "incomplete|interrupted"), ("/unsized-big", "larger"), ("/empty", "empty")] {
            let err = download(&format!("{base}{path}"), &target, &policy, |_| {}).unwrap_err();
            assert!(expect.split('|').any(|e| err.contains(e)), "{path}: {err}");
            assert!(!target.exists() && !part_path(&target).exists(), "{path}: files left behind");
        }
        // A declared size over the limit is refused before reading the body.
        let err = download(&format!("{base}/big"), &target, &local_policy(10_000), |_| {}).unwrap_err();
        assert!(err.contains("larger"), "{err}");
    }

    #[test]
    fn garbage_addresses_and_dead_servers_fail_cleanly() {
        let target = temp("junk");
        for bad in ["", "not a url", "http://", "http://127.0.0.1:1/never-listening"] {
            assert!(download(bad, &target, &local_policy(1000), |_| {}).is_err(), "{bad:?}");
        }
    }
}
