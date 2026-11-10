# 🎵 StarNote · Myune Music Android TV Edition

**[简体中文](README.md) · English**

> An **Android / Android TV port** of the desktop music player
> [xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music).
> Fully operable with nothing but a remote, a keyboard, or a gamepad;
> playback features stay essentially the same as the upstream desktop app.

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47.5-blue?logo=flutter" alt="Flutter 3.47.5" />
  <img src="https://img.shields.io/badge/Android%20TV-Leanback-brightgreen" alt="Android TV" />
  <img src="https://img.shields.io/badge/ABI-arm64%20%7C%20armv7%20%7C%20x86__64-orange" alt="ABI" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-lightgrey" alt="Apache 2.0" /></a>
</p>

---

## Contents

1. [What this is](#1-what-this-is)
2. [Upstream source repository](#2-upstream-source-repository)
3. [Parity with upstream](#3-parity-with-upstream)
4. [Developer & maintainer](#4-developer--maintainer)
5. [TV / remote / keyboard / gamepad controls](#5-tv--remote--keyboard--gamepad-controls)
6. [What was adapted](#6-what-was-adapted)
7. [Network media (WebDAV / FTP / Bilibili)](#7-network-media-webdav--ftp--bilibili)
8. [Downloads & ABIs](#8-downloads--abis)
9. [Update checks](#9-update-checks)
10. [Building from source](#10-building-from-source)
11. [License](#11-license)
12. [Feedback & contributions](#12-feedback--contributions)
13. [Rollback](#13-rollback)
14. [Credits](#14-credits)

---

## 1. What this is

**StarNote** (星音 StarNote, *Myune Music TV Edition*) is an independently maintained
**Android / Android TV port** of the desktop player
[Myune Music](https://github.com/xiaobaimc/myune_music). The app label `星音 StarNote` is
injected by CI into `android:label` and shared by phone launchers and the Android TV
launcher; a 320×180 TV banner is provided as well.

**One APK, automatic TV detection.** The TV input and focus paths activate only when the
device is detected as a TV. On ordinary phones and tablets none of those code paths run,
and the existing phone behaviour (immersive mode, UI scaling, SAF) is unchanged.

> This is not an official upstream release and is not affiliated with the upstream author.
> All upstream copyright and Apache-2.0 notices are preserved.

## 2. Upstream source repository

| Item | Value |
| --- | --- |
| Upstream repository | [github.com/xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music) |
| Upstream author | `xiaobaimc` |
| Upstream project | A **Windows / Linux desktop** local music player built with Flutter 3.47.5 / Dart 3.10 (it originally had no `android/` directory) |
| Upstream baseline version | `0.9.5` |
| Upstream license | **Apache License 2.0** |
| Original upstream README | [UPSTREAM_README.md](UPSTREAM_README.md) (preserved verbatim) |
| **This fork's repository** | [github.com/midi-HL/myune_music_android_tv](https://github.com/midi-HL/myune_music_android_tv) |
| This fork's license | **Apache License 2.0** (same as upstream) |
| This fork's version | `1.1.2` (see `lib/tv/tv_app_info.dart`) |

The **full upstream commit history is preserved** (no squash, no history rewrite). All port
work is recorded as additional commits and tags so it can be rolled back at any time. See
[NOTICE](NOTICE) and [ANDROID_PORT_HANDOFF.md](ANDROID_PORT_HANDOFF.md).

## 3. Parity with upstream

The goal is to *bring the desktop app to Android TV*, not to rewrite the player. The
following features are inherited from upstream and stay essentially the same as the desktop
version:

- Library: folder playlists, manual playlists, automatic artist / album grouping
- Lyrics: embedded lyrics, external `lrc / yrc / qrc / krc`, word-by-word lyrics, online
  lyric sources, translation / romanisation lines, lyric display settings
- Playback: `mpv_audio_kit` + libmpv, effects / equaliser, ReplayGain, play modes, seeking
- Player page: word-by-word lyrics, animated `MeshGradient` background, blurred cover art,
  playing-queue drawer
- Appearance: Material 3, theme colours, custom fonts and backgrounds, page visibility settings
- Metadata: Rust + `flutter_rust_bridge` / `cargokit` for covers, duration and embedded tags
- Extras: fuzzy / pinyin / initial-letter search, local playback statistics, audio analysis page
- **The upstream Windows / Linux builds and features are unaffected by this port**

**What differs lives in the platform layer, the input layer and the new network-media entry**
(see §6–§7): Android platform isolation, SAF storage access, the TV launcher entry and
branding, remote / keyboard / gamepad input, spatial focus navigation, TV control
reachability, app info / update checks pointing at this repository, a fixed release
signature, and the new WebDAV / FTP / Bilibili streaming in the "Network media" page.
Existing local-music playback logic has not been replaced and remains unaffected.

## 4. Developer & maintainer

| Item | Value |
| --- | --- |
| Port developer / maintainer | **辰星 \| Edwin 3J \| HLmidi** |
| GitHub | [github.com/midi-HL](https://github.com/midi-HL) |
| Contact | [t.me/Edwin_hlcx](https://t.me/Edwin_hlcx) |
| Upstream author | `xiaobaimc` (retains copyright and license of the original repository) |

The in-app **Settings → General → App info & notes → About** dialog shows exactly this
information, sourced from `lib/tv/tv_app_info.dart`; it no longer shows the PC version's
app info.

## 5. TV / remote / keyboard / gamepad controls

Design rule: **with no mouse and no touchscreen, a plain remote can do everything** —
import music, pick a song, control playback, adjust lyric settings and effects, manage the
queue, and reach every settings item.

| Input | Behaviour |
| --- | --- |
| D-pad ↑ ↓ ← → | Moves focus to the nearest focusable widget **in that visual half-plane**; no counter-intuitive jumps to the other side of the screen |
| OK / Enter / Space | Activates the focused widget |
| Back / Esc / gamepad B (○) | Closes overlays → drawers → player page → returns to the TV home screen; Back on the "Now playing" drawer equals the ✕ close button |
| Media keys (play/pause, prev/next, seek) | Direct playback control; remotes without media keys use focusable controls instead |
| Xbox / PlayStation gamepads | Mapped by **physical position**: A/✕ confirm, B/○ back, bumpers / triggers for track skip and seeking |
| Settings → TV & input → Gamepad icons | Switch between Auto / Xbox / PlayStation display icons (icons only, no functional change) |
| Settings → TV & input → Key learning | Records vendor-private keyCodes and binds them to logical actions for non-standard remotes |
| Volume | Volume icon opens a **vertical** slider, ↑/↓ adjusts, Back closes; no on-screen text hints |
| Seek bar | Excluded from D-pad focus (a Slider would swallow all four directions); drag with mouse/touch, or seek with media keys / triggers |
| Effects / EQ sliders | Horizontal: ←/→ changes value, ↑/↓ leaves. Vertical bands: ↑/↓ changes value, ←/→ leaves |
| Focus highlight | Native-style translucent primary-colour background; **no outline, no double highlight** |
| Mouse / touch | Every TV control also keeps a tap path, useful when debugging focus issues |

### 5.1 Text input and the soft keyboard

A TV has no mouse, and the D-pad must not get trapped between several text fields. Every
place that needs typing therefore uses a **"field button → single-field input dialog"** flow:

- Press OK on a field button ("Search keyword", "Server address", "Port", "Password", …)
  to open the input dialog.
- The field is `autofocus` and `TextInput.show` is invoked explicitly, so OK on the remote
  **always brings up the soft keyboard**.
- D-pad moves between IME candidates, OK confirms; "Done / Search" or the dialog's
  "Confirm" button submits.
- The global TV input layer **does not intercept any key (including Esc) while a text field
  is focused**, so it cannot steal the IME's cursor handling.
- Dialog buttons (Cancel / Confirm / Close) are all remote-reachable and one always has
  the initial focus.

### 5.2 Bilibili QR-code login

Login needs **no typing on the TV**: the dialog shows a QR code rendered by `qr_flutter`,
you scan it with the Bilibili mobile app and confirm on your phone. The TV polls the state
every 2 seconds ("waiting / scanned / expired / success") and offers
"Refresh QR code / Log out / Close". Only the login cookie is stored locally; no account
or password is saved.

## 6. What was adapted

1. **Android platform isolation** — `window_manager` / `tray_manager` / `hotkey_manager` /
   `flutter_single_instance` initialise on desktop only; desktop title bars removed, hotkey
   settings hidden, immersive fullscreen, in-app UI scaling, landscape two-pane layout;
   `MpvAudioKit` and Rust initialisation retained.
2. **SAF storage access** — native `ci/MainActivity.kt` provides
   `ACTION_OPEN_DOCUMENT_TREE`, persistent URI permissions, recursive audio enumeration and
   byte reads; `android_content_resolver.dart` turns `content://` into playable `fd://` and a
   private cache file for metadata parsing.
3. **TV launcher entry** — idempotent injection of `LEANBACK_LAUNCHER`,
   `android.software.leanback` / touchscreen / gamepad (all `required="false"`),
   `android:banner`, a 320×180 banner and branded launcher icons in five densities; app
   label `星音 StarNote`.
4. **Input layer** — `ci/MainActivity.kt` broadcasts raw key events via `dispatchKeyEvent()`
   + `EventChannel` **without consuming them**; `lib/tv/` implements TV detection, key
   normalisation, logical actions, back/drawer handling, settings UI, gamepad icons and
   input dispatch with persistence.
5. **Focus navigation** — automatic initial focus on cold start, route changes and drawer
   opening; strict geometric search using global `RenderBox` `Rect.center`, allowing
   cross-FocusScope movement on the main screen while locking focus inside modal overlays;
   `Scrollable.ensureVisible()` auto-scrolls clipped targets into view;
   `FocusHighlightStrategy.alwaysTraditional` keeps native focus states visible.
6. **Control reachability** — `TvPointerOnlySlider` for seek bars, `TvAdjustableSlider` for
   settings sliders, vertical volume bar, a custom focusable TV rail, the restored "Lyric
   display settings" button in the player control row, and Back == ✕ for drawers.
7. **App info** — About dialog and update checks point at this repository; `TvAppInfo` is
   the single source of truth for project metadata.
8. **CI** — GitHub Actions generates the Android runner, injects the TV Manifest and
   branding, and builds three single-ABI release APKs (arm64-v8a / armeabi-v7a / x86_64).
9. **Network media** (see §7) — a new "Network media" navigation entry with WebDAV / FTP
   clients, a Bilibili Web API client, and a loopback-only HTTP streaming proxy with Range
   support that wraps remote streams into `http://` URLs for the existing `Media()` playback
   path. `AudioService` and the playing queue needed no changes.
10. **Fixed release signing** — CI enforces one keystore for all builds; missing signing
    secrets or a detected `CN=Android Debug` certificate fail the build. All three ABIs share
    the same certificate, so later versions can be installed over the previous one.

Per-round fix notes and rollback anchors are in [ANDROID_PORT_HANDOFF.md](ANDROID_PORT_HANDOFF.md).

## 7. Network media (WebDAV / FTP / Bilibili)

Solves the limited local storage of a TV: **stream on demand, never cache to disk**. Remote
files are read through the local proxy only while playing, so the whole NAS library costs no
TV storage. The entry is "Network media" in the main rail, with two tabs.

### 7.1 Network drives / shared drives

- Protocols: **WebDAV** (the "web…" network-drive protocol: HTTP / HTTPS, Basic Auth,
  PROPFIND directory listing) and **FTP** (anonymous / user+password, PASV, REST resume).
- Left pane manages connections (add / edit / delete); right pane browses directories.
  "Up / Refresh / Play all audio / Add all to queue" plus a "Play now / Enqueue" tap-mode
  toggle are available.
- Recognises `mp3 / flac / wav / m4a / aac / ogg / opus / wma / ape / aiff / dsf / m4b…`.
- Passwords live in local `SharedPreferences` only; never committed, never logged.

### 7.2 Bilibili

Following the feature scope and interaction of
[BiliMusic-Desktop](https://github.com/licpp/BiliMusic-Desktop):

- Keyword search, pagination, BV / av number / full-link parsing, multi-part (分 P) expansion
- Play a single part, play all parts, or enqueue the whole group
- Audio stream (DASH audio track, default and lighter) / video stream switch
- Search history and **QR-code login** (login optional for search and playback)
- WBI signing, CDN `Referer` / `User-Agent` / `Cookie` headers, fallback to legacy endpoints

### 7.3 Implementation notes

- Each remote stream is encoded as
  `http://127.0.0.1:<port>/starnote/<base64url JSON>`. Ports are a fixed candidate range
  `18765–18774` with a fixed token, so **URLs in the playing queue still work after an app
  restart**; metadata (title / artist / album / duration) is embedded in the URL too, so no
  re-enumeration is needed.
- The proxy supports HTTP `Range` and emits correct `200` / `206`, `Accept-Ranges`,
  `Content-Length` and `Content-Range`, so remote streams are seekable. If the upstream does
  not report a total length it falls back to a `200` sequential stream to avoid truncation.
- `RemoteMediaRegistry` intercepts proxy URLs during metadata parsing so they never go
  through `File.exists()` / local tag reading (which would show "file not found"); local
  paths keep the original full pipeline.
- CI injects `android:usesCleartextTraffic="true"` so plain-HTTP WebDAV and the loopback
  proxy work.

## 8. Downloads & ABIs

| ABI | Target devices | Artifact |
| --- | --- | --- |
| `arm64-v8a` | Most modern Android TVs, boxes and phones | `myune-music-arm64-v8a-release.apk` |
| `armeabi-v7a` | Older 32-bit ARM devices | `myune-music-armeabi-v7a-release.apk` |
| `x86_64` (AMD64 / 64-bit x86) | x86-64 TV boxes and Android emulators | `myune-music-x86_64-release.apk` |

📦 Downloads: [GitHub Releases](https://github.com/midi-HL/myune_music_android_tv/releases)

> **Why there is no x86 (32-bit) APK**: the upstream `libmpv-r13` release ships prebuilt
> `libmpv.so` only for `arm64-v8a`, `armeabi-v7a` and `x86_64`, and `mpv_audio_kit`'s
> `abiFilters` does not include `x86`. An x86 32-bit build would lack the native playback
> library and produce no sound, so this port **does not ship** that ABI rather than deliver a
> knowingly broken package. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Install with a file manager or `adb install`. Starting with this version all APKs use the
**same fixed release signature** (`CN=StarNote TV`); all three ABIs share the certificate,
so later versions can be **installed over the previous one with no uninstall/reinstall**.
CI refuses builds with missing signing secrets or a detected Android Debug certificate, so
cross-ABI signature mismatches can no longer occur.

> Upgrading from `v1.0.0` (debug-signed) for the first time still requires one uninstall
> because the certificate changed; every upgrade after that installs cleanly.

## 9. Update checks

Both **Settings → General → Check for updates** and the silent startup check query:

```
https://api.github.com/repos/midi-HL/myune_music_android_tv/releases/latest
```

They **no longer check the upstream PC desktop repository** `xiaobaimc/myune_music`.
Release tags follow `vX.Y.Z` (e.g. `v1.0.0`) and correspond to `TvAppInfo.version` in
`lib/tv/tv_app_info.dart`. The About dialog's repository / Issues / Releases links point
here as well.

## 10. Building from source

You do **not** need Flutter / Rust / NDK locally: building and APK verification are handled
entirely by [`.github/workflows/build_android.yml`](.github/workflows/build_android.yml)
on GitHub Actions.

Toolchain: Flutter `3.47.5` / Dart 3.10, Rust stable, JDK 21, Android SDK 36,
NDK `28.2.13676358`, CMake `3.22.1`.

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64   # or android-arm / android-x64
```

Fixed release signing requires four repository secrets under
`Settings → Secrets and variables → Actions`: `ANDROID_KEYSTORE_BASE64` (base64 of the JKS),
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. CI writes
`android/key.properties` from them and switches to `signingConfigs.release`; **any missing
value fails the build** instead of falling back to the template debug signature. The
keystore and passwords are never committed.

Upstream has no `android/` directory, so CI generates the runner with
`flutter create --platforms=android`, then injects `ci/MainActivity.kt`, the TV Manifest
patch and `ci/branding/` assets. Each ABI is built in its own job so Rust/cargokit and
libmpv download tasks cannot overwrite each other's outputs.

## 11. License

- **Source code: Apache License 2.0** — full text in [LICENSE](LICENSE) (same as upstream)
- Changes made to upstream: [NOTICE](NOTICE), [ANDROID_PORT_HANDOFF.md](ANDROID_PORT_HANDOFF.md)
- Original upstream README: [UPSTREAM_README.md](UPSTREAM_README.md)
- Third-party components and native libraries: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- Font: MiSans by Xiaomi, free for commercial use, copyright remains with Xiaomi

> ⚠️ **GPL / LGPL obligations for native libraries**: the APK contains `libmpv.so`
> downloaded at build time by `mpv_audio_kit` (mpv / FFmpeg ecosystem, possibly including
> GPL components). Apache-2.0 applies to the **Dart / Kotlin / Rust source** in this
> repository; distributing the binary still requires satisfying GPL / LGPL license texts,
> copyright notices, NOTICE and source-availability (or written offer) obligations.
> See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the official mpv / FFmpeg
> licenses. Complete your own compliance review before distributing built APKs publicly.

## 12. Feedback & contributions

- Issues: [GitHub Issues](https://github.com/midi-HL/myune_music_android_tv/issues)
- Pull requests: [GitHub PRs](https://github.com/midi-HL/myune_music_android_tv/pulls)
- For upstream desktop (Windows / Linux) problems, please use the
  [upstream issue tracker](https://github.com/xiaobaimc/myune_music/issues); this fork
  only handles Android / Android TV issues.

## 13. Rollback

Full history and anchor tags are preserved:

| Tag | Meaning |
| --- | --- |
| `baseline-558a71f-0713` | Early Android port baseline |
| `baseline-4168e51-pre-tv` | State immediately before TV work started |
| `tv-v2-focus-fix` / `tv-v3-focus-fix` / `tv-v4-focus-fix` | Successive TV focus fix rounds |
| `v1.0.0` | First open-source release (app info / update checks / three ABIs, debug-signed) |
| `v1.1.0` | Network media (WebDAV / FTP / Bilibili) + fixed release signing |
| `v1.1.1` | Network playback fixes, Bilibili pagination redesign, play history / favorites, legacy audio format support |
| `v1.1.2` | Full D-pad navigation audit, music-only recommendations, Bilibili subtitles / lyrics, redesigned branding |

```bash
git checkout tv-v4-focus-fix      # return to an anchor
git revert <commit>               # undo a change while keeping the audit trail
```

## 14. Credits

- [xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music) — upstream desktop app and its Apache-2.0 source
- [mpv_audio_kit](https://github.com/ales-drnz/mpv_audio_kit) (BSD-3-Clause) and the mpv / FFmpeg communities
- [lyricGeter](https://github.com/WisteriaZy/lyricGeter) — reference for lyric fetching and parsing
- Xiaomi MiSans font, and the Flutter / Rust / Dart open-source communities
