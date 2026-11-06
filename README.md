# Sketch3D — Android app + web source

**Sketch3D** is a single-file 3D spatial sketchbook. Draw pressure-tapered tube
strokes on 3D surfaces, orbit around them, and export to **GLB / OBJ / USDA /
USDZ / PNG**. Built in plain HTML/JS/CSS with [Three.js r128](https://threejs.org/)
— no framework, no build step.

This repository holds both targets:

| Target | Stack | Entry point |
|---|---|---|
| **Web / PWA** | Vanilla JS + Three.js r128, served statically | [`index.html`](index.html) |
| **Android** | Rust [`wry`](https://github.com/tauri-apps/wry) + [`tao`](https://github.com/tauri-apps/tao) shell, Gradle build | [`android/`](android/) |

## 📦 Download the APK

**→ [github.com/kipzitox/Sketch3D-android/releases](https://github.com/kipzitox/Sketch3D-android/releases)**

Release `v4.3-android` ships `Sketch3D-v4.3-release.apk` with three ABIs:

| ABI | Device class |
|---|---|
| `arm64-v8a` | Modern phones (recommended) |
| `armeabi-v7a` | Older 32-bit phones |
| `x86_64` | Emulators, Chromebooks |

The APK is **fully offline**: the web app, Three.js and the fonts are bundled
into the assets and served from `https://app.assets/`, so the app works with no
network at all.

> The release APK is signed with the Android debug key so it installs without
> extra setup. See [`android/README.md`](android/README.md#release-signing) to
> generate a proper release keystore.

## ✨ Features

- **3D drawing** — pressure-tapered tube strokes on an infinite grid, with
  orthographic / perspective cameras and a navigation gizmo.
- **Drawing surfaces** — draw on planes, cylinders or spheres.
- **Export** — GLB, OBJ, USDA, USDZ, PNG and the native JSON scene format.
  On Android the files are written straight to the **Downloads** folder.
- **Autosave** — IndexedDB (with a localStorage fallback) restores your scene
  on relaunch.
- **PWA** — installable, cache-first service worker, works offline on the web
  too.

## 🖥️ Run the web build

It is a static file — serve the repository root with any static server:

```bash
python -m http.server 8000
# → http://127.0.0.1:8000/index.html
```

## 📱 Build the Android app

Requires the Android SDK, JDK 17, a Rust toolchain with the NDK targets and
`cargo-ndk`:

```powershell
git clone https://github.com/kipzitox/Sketch3D-android.git
cd Sketch3D-android
cd android
.\build-apk.ps1              # → dist\Sketch3D-v4.3-release.apk
.\publish.ps1                # build + upload to the GitHub release
```

Full instructions, toolchain versions and troubleshooting:
[`android/README.md`](android/README.md).

## 🔌 How the export bridge works

In a WebView, `<a download>` does nothing — so every export in `index.html`
now goes through one helper:

```js
saveBlob(name, blob, mime)
  ├─ window.AndroidBridge.saveToDownloads(...)  → Kotlin → MediaStore/Downloads
  └─ <a download>                                → normal browsers
```

The bridge is **feature-detected**, so the web build behaves exactly as before.

## 📂 Layout

```
index.html            ← the entire application (single-file constraint)
manifest.json, sw.js  ← PWA manifest + cache-first service worker
android/              ← Rust wry/tao shell + Gradle project
  rust/               ← native host (asset loader, https scheme, IPC)
  app/                ← Kotlin activity + Exporter bridge
  tools/              ← DevTools-protocol helpers for debugging
  build-apk.ps1       ← assets → cargo-ndk → Gradle → dist/
  publish.ps1         ← build + GitHub Release upload
.github/workflows/    ← CI: build + publish the APK on `v*` tags
architecture-11.md    ← architecture notes
gotchas-11.md         ← pitfalls and constraints
handoff-11.md         ← development log
schema-11.md          ← scene/save-format schema
```

## ⚖️ License

Source code: [Polyform Noncommercial 1.0.0](LICENSE) — free for personal,
educational and non-profit use; commercial use requires permission.

**Your artwork is yours**: everything you draw and export is yours, with no
restrictions. See [`LICENSE-USAGE.md`](LICENSE-USAGE.md).
