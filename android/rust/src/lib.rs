// Sketch3D — native Android shell (wry + tao).
//
// The 3D application itself is the web build (`index.html`, Three.js r128).
// This crate only hosts it inside the system WebView and keeps the Android
// event loop alive; it is intentionally thin so the web app stays the single
// source of truth.
//
// Android glue recap (see wry's MOBILE.md):
//   * `WRY_ANDROID_PACKAGE` / `WRY_ANDROID_LIBRARY` /
//     `WRY_ANDROID_KOTLIN_FILES_OUT_DIR` are read by wry's build.rs, which
//     generates WryActivity.kt / Rust.kt / … into the Kotlin source folder.
//   * `tao::android_binding!` wires the JNI lifecycle callbacks
//     (onCreate/onStart/onResume/…) of `com.notebysebas.sketch3d.Rust`.
//   * `wry::android_binding!` wires the WebView-specific JNI callbacks.

use tao::{
    event::{Event, StartCause, WindowEvent},
    event_loop::{ControlFlow, EventLoop, EventLoopWindowTarget},
    window::{Window, WindowBuilder},
};
use wry::WebView;

/// Custom protocol handled by wry's Android asset loader. The web app is
/// served straight from the APK `assets/` folder, which gives it a stable
/// https origin — IndexedDB and localStorage keep working there.
const ASSET_PROTOCOL: &str = "app";
const START_URL: &str = "app://assets/index.html";

#[cfg(target_os = "android")]
fn init_logging() {
    android_logger::init_once(
        android_logger::Config::default()
            .with_max_level(log::LevelFilter::Info)
            .with_tag("sketch3d"),
    );
}

#[cfg(not(target_os = "android"))]
fn init_logging() {
    let _ = env_logger::try_init();
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn stop_unwind<F: FnOnce() -> T, T>(f: F) -> T {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(value) => value,
        Err(err) => {
            eprintln!("attempt to unwind out of `rust` with err: {err:?}");
            std::process::abort()
        }
    }
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn _start_app() {
    stop_unwind(|| main());
}

/// Entry point invoked by the Android runtime.
///
/// `android.app.lib_name` in AndroidManifest.xml points at `libsketch3d.so`,
/// and the generated `Rust.kt` object calls into the bindings below.
#[no_mangle]
#[inline(never)]
pub extern "C" fn start_app() {
    #[cfg(target_os = "android")]
    {
        // JNI names: Java_com_notebysebas_sketch3d_Rust_*
        tao::android_binding!(
            com_notebysebas,
            sketch3d,
            Rust,
            wry::android_setup, // invoked at the end of Activity.onCreate
            _start_app
        );
        wry::android_binding!(com_notebysebas, sketch3d);
    }
}

fn main() {
    init_logging();

    let event_loop = EventLoop::new();
    let mut webview: Option<WebView> = None;
    let mut window: Option<Window> = None;

    event_loop.run(move |event, event_loop, control_flow| {
        *control_flow = ControlFlow::Wait;

        match event {
            Event::NewEvents(StartCause::Init) => {
                let win = build_window(event_loop).expect("failed to create window");
                webview.replace(build_webview(&win).expect("failed to create webview"));
                window.replace(win);
            }
            Event::WindowEvent {
                event: WindowEvent::CloseRequested { .. },
                ..
            } => {
                webview.take();
                window.take();
                *control_flow = ControlFlow::Exit;
            }
            _ => (),
        }
    });
}

fn build_window(
    event_loop: &EventLoopWindowTarget<()>,
) -> Result<Window, Box<dyn std::error::Error>> {
    let window = WindowBuilder::new()
        .with_title("Sketch3D")
        .build(event_loop)?;
    Ok(window)
}

fn build_webview(window: &Window) -> Result<WebView, Box<dyn std::error::Error>> {
    #[cfg(target_os = "android")]
    {
        use wry::WebViewBuilderExtAndroid;

        // `with_asset_loader` serves the APK `assets/` folder through
        // WebViewAssetLoader; `with_https_scheme` makes the origin
        // https://app.assets (secure context, stable storage).
        let webview = wry::WebViewBuilder::new()
            .with_asset_loader(ASSET_PROTOCOL.to_string())
            .with_https_scheme(true)
            .with_url(START_URL)
            .with_devtools(true)
            .build(window)?;
        Ok(webview)
    }

    #[cfg(not(target_os = "android"))]
    {
        let webview = wry::WebViewBuilder::new()
            .with_url(START_URL)
            .with_devtools(true)
            .build(window)?;
        Ok(webview)
    }
}
