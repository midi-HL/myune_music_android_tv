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

0. [What's new & feature overview](#0-whats-new--feature-overview)
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

## 0. What's new & feature overview

### 0.1 What's new in v1.6.1

> Semantic versioning: new features bump the minor version, bug-only fixes bump the patch,
> and each release gets its **own tag / Release** (`v1.0.0` → `v1.1.0` → `v1.1.1` →
> `v1.1.2` → `v1.2.0` → `v1.3.0` → `v1.4.0` → `v1.5.0` → `v1.5.1` → `v1.6.0` → **`v1.6.1`**). This lets the in-app update check see new builds via
> `/releases/latest` and keeps every build individually rollback-able.
> **Bug fixes are listed in the Release notes** of the matching version.

| Area | Changes |
| --- | --- |
| D-pad | Full geometric focus-navigation audit; offscreen-page focus isolation, same-row/column priority, visibility filtering; progress bar never swallows arrow keys, settings sliders adjust with Left/Right and can be left with Up/Down |
| Now-playing page | Restored desktop layout scale (fixed the too-small UI and thin control bar); smooth area-based scaling at any resolution; controls auto-hide after 5 s of inactivity and wake on any arrow / OK / media key |
| Music & lyrics | Bilibili recommendations limited to the music category; subtitle / lyric auto-detection; lyric-source priority dialog gained Up/Down buttons so a remote can reorder sources |
| Artwork | Only the 320x180 TV banner was redrawn; the square / round phone launcher icons are untouched |
| Network drives (this backport) | See "2026-11-12 backport" below |
| Gamepad / remote | Every new screen, menu, star button, toggle and dialog is fully D-pad reachable with a visible focus highlight; soft keyboard and Back behaviour unchanged |
| **v1.2.0 now-playing focus fix** | Lyric lines are excluded from D-pad focus (they used to steal initial focus, lose all focus after Left/Right, and let OK trigger an off-screen favorites button); the page now focuses the control bar on open and pulls focus back whenever it lands on an invisible node |
| **v1.2.0 Bilibili cover art** | The left panel now downloads and shows the video cover automatically (async fetch from the cover URL encoded in the proxy URL when `albumArt` is empty), scaled with square `BoxFit.cover` and capped decode size |
| **v1.2.0 Bilibili audio quality** | No more fixed 360P + first audio track; requests clarity tiers 127 → 80 → 16 and picks the **highest available** track in `dash.audio[]` by Hi-Res / Dolby / bitrate priority |
| **v1.3.0 read-only Google Drive** | Fourth network source; LAN QR pairing (zero typing on TV), `drive.readonly` only, local auth helper `tools/gdrive_auth.py`, credentials stored only on the TV; shares browse / playback / favourites / metadata pipeline with WebDAV / FTP |
| **v1.4.0 visual normalization** | Font sizes, line spacing, lyric blur strength and background blur radius are normalized by `UiScaleScope.visualScale`, and Android system font scaling is capped, so the 30.0 / 6.0 / 4.0 values in Lyrics Settings render at the same visual pixel size as on desktop. **No setting defaults were changed.** |
| **v1.4.0 lyric selection** | A real-time "Lyric selection" block is appended to the now-playing Lyrics Settings: online / embedded / external files (all formats auto-detected) / refetch online. Changes apply immediately and **write no persistent settings**; the full 6-item source priority dialog in Settings is untouched. |
| **v1.4.0 GDrive notes** | Documented the Testing-status 7-day `refresh_token` expiry, 100 test-user cap, annual restricted-scope security assessment, plus one-command re-authorization and an in-app expiry hint. |
| **v1.5.0 title fix (primary)** | Song title / artist no longer scale with the cover; pinned to desktop 20 / 14 visual pixels. Large-screen inflation capped at 1.0; Android default lyric settings unified to 30.0 / 550 / 6.0 / 4.0. |
| **v1.5.0 performance constraint** | Kept v1.4.0 one-shot static blur and visual quality; **added no real-time / per-frame gaussian blur**. The previous build was confirmed smooth except for a brief hitch when opening. |
| **v1.5.0 Drive pairing helper** | New `gdrive-pair/` (Go + Fyne, Kazumi-inspired Material 3 dark / rounded cards / side nav + top bar): auto-redirect to Settings when Google info is missing, persistent local config, direct authorization-code entry, TV pairing via the existing protocol; phone pairing page restyled to match. |
| **v1.5.1 real font fix** | An A/B pixel comparison showed v1.5.0's value was identical to the old clamp lower bound (zero visual change); now explicitly 15 / 10.5 visual pixels with no clamp, plus anti-regression assertions. |
| **v1.5.1 Windows helper** | Added `gdrive-pair-windows-amd64.exe` alongside Linux amd64 / arm64; no phone native app (rationale in `gdrive-pair/README.md`). |
| **v1.6.0 Bilibili folders** | New "Bilibili folders" section: list the account's fav folders (name / item count, default first), open one to read its videos with load-more. Uses the existing QR login cookies, no packet capture needed. Coexists with the local starred favorites as two separate entries. |
| **v1.6.0 history constraint** | "History" keeps reading the on-device `BiliLibraryStore`; no Bilibili server-side watch-history API. |
| **v1.6.1 global D-pad fix** | Four root causes fixed: (1) when focus sits on `rootScope`, `Shortcuts` cannot find `Actions` and arrow keys do nothing while the guard only fires on focus *changes* — a deadlock, fixed with a global key-level fallback that lands focus on the first visible control; (2) the container test (width >= 85% **OR** height >= 80%) wrongly treated full-width list rows as page containers, now only true page containers and tall side rails are excluded; (3) geometric scoring let DOWN jump across zones to the rail or bottom playback bar, fixed with `_NavZone` (UP/DOWN locked to the current zone, LEFT/RIGHT may still cross); (4) the play page's page-level `Shortcuts`/`Actions` swallowed arrow keys inside the lyrics drawer, so `51e3940` unifies **all** arrow-key handling in the global `_onHardwareKey` (editable focus passes through, sliders go to `handleSliderKey`, everything else uses `moveFocus(lockZone: true)`). Covers artist / statistics / all-songs / local favorites / history / search results / recommendations / Bilibili folders / lyrics settings drawer. |

**2026-11-12: backport from [XYkadicloud/myune_music v0.9.5-network.1](https://github.com/XYkadicloud/myune_music/releases/tag/v0.9.5-network.1)**

That branch is based on upstream v0.9.5 and fixes/optimises the network-drive (WebDAV / FTP)
pipeline. The parts that make sense on Android TV were ported back (desktop-only Google Drive
OAuth and its file-management UI were **not** ported):

- **Embedded tags / cover / lyrics**: fetch only the file header via HTTP `Range`, parse FLAC
  `METADATA_BLOCK` and MP3 `ID3v2` in pure Dart for title / artist / album / duration /
  cover / embedded lyrics. Results use a memory -> disk -> network cache; metadata JSON and
  cover binaries are stored separately and hydrated on startup, so a restart never re-reads.
- **Network-drive songs in Favourites**: WebDAV / FTP songs can be starred individually or
  added with "Add all to favourites", then appear directly in the built-in **Favourites**
  playlist with real title, artist, duration and cover; play with one click, **no more drilling
  into "Network media -> Network drive" every time**. **Bilibili is excluded** — it keeps its
  own favourites / history store.
- **Stability**: network proxy URLs are no longer mangled by `path.normalize()` (which broke
  the cover worker); WebDAV first-byte timeout raised to 45 s (below mpv's 60 s) so slow
  NAS bridges no longer cause `loading failed`.
- **Remote usability**: all new actions live in the existing TV "More" menu; the per-song star
  is a separate focusable button. Everything is reachable with the D-pad.

### 0.2 Features added compared with upstream

Baseline: [xiaobaimc/myune_music v0.9.5](https://github.com/xiaobaimc/myune_music), a
Windows / Linux desktop local player (Flutter + Rust / mpv). This port keeps its playback and
UI capabilities and adds:

| Capability | Upstream desktop | StarNote (this port) |
| --- | --- | --- |
| Platform | Windows / Linux desktop | **Android / Android TV / plain Android TV boxes**, one APK auto-adapts |
| Input | Mouse / keyboard | **Remote / D-pad / keyboard / gamepad only** operation, geometric focus navigation + native-style highlight |
| File access | Local disk paths | Added **Android SAF** (`ACTION_OPEN_DOCUMENT_TREE`, `content://` -> `fd://`) and in-app UI scaling without changing system DPI |
| Scaling | Fixed desktop layout | Area-based smooth scaling at any resolution; now-playing page matches desktop visual size |
| Immersive playback | Controls auto-hide on mouse idle | Same behaviour, plus **wake-up from remote / gamepad keys** |
| TV entry point | None | Leanback launcher, TV banner, gamepad icons, media keys, Back / drawer logic |
| Network drives | None | **WebDAV / FTP** clients + local stream proxy (HTTP Range / resume), stream on demand |
| Network audio metadata | None | Embedded tag / cover / lyric reading with on-disk cache (backported from network.1) |
| Network audio favourites | None | Network-drive songs go straight into Favourites with metadata preview and one-click play (Bilibili excluded) |
| Bilibili | None | Login-free search / playback, music-category recommendations, QR login, multi-part, favourites / history, official CC subtitles |
| Audio formats | Common formats | Extra legacy formats (APE / WavPack / TTA / TAK / DSD / AIFF / CAF / WMA / MIDI / AC3 / DTS …), video containers playable as audio-only |
| Delivery & licensing | Source only | Apache-2.0, bilingual README / NOTICE / third-party notices, **fixed release signing**, GitHub Actions 3-ABI builds (arm64-v8a / armeabi-v7a / x86_64) |
| App info | Points upstream | About / update check point to this repository; full Git history preserved for rollback |

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
| This fork's version | `1.6.1` (see `lib/tv/tv_app_info.dart`) |

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

## 7. Network media (WebDAV / FTP / Google Drive / Bilibili)

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
- **Favourites (Bilibili excluded)**: each audio row has its own focusable star button, and
  "More -> Add all to favourites" adds a whole directory. Favourited songs appear directly in
  the built-in **Favourites** playlist with one-click playback — no more drilling into the
  network-drive folders. Full song objects (title / artist / album / duration / cover) are
  persisted, so metadata survives a restart.
- **Embedded metadata preview**: FLAC / ID3v2 tags are read from the file header on demand;
  the list shows the real "title · artist" and duration, and the cover is backfilled into the
  now-playing page and Favourites. "More -> Read tags & covers in this folder" prefetches a
  whole directory; the "Read embedded tags" toggle disables the extra traffic. Only metadata
  and covers are cached — **audio files are never cached** — and the cache is hydrated on
  startup. Embedded lyrics are used as one of the lyric sources.
- **First-byte / URL stability**: WebDAV header timeout is 45 s (below mpv's 60 s) to avoid
  `loading failed` on slow NAS bridges; proxy URLs are no longer broken by path normalisation.
- Passwords live in local `SharedPreferences` only; never committed, never logged.

### 7.1b Read-only Google Drive (QR pairing)

**Read-only**: only `drive.readonly` is requested. No upload / create / rename /
delete operations exist, so cloud files are never modified.

Why QR pairing instead of signing in on the TV:

- Android TV / boxes usually have no system browser, so the desktop loopback
  OAuth flow cannot open the consent page;
- Google's **device-code flow** (short code on TV) only allows limited scopes
  (`drive.file` / `drive.appdata`) and **does not support `drive.readonly`**,
  so an existing music library cannot be read;
- Google's token endpoint disallows direct browser calls (CORS), OOB callbacks
  are deprecated, and private IPs cannot be registered as redirect URIs, so a
  pure web page cannot obtain a long-lived `refresh_token`.

Therefore pairing happens over the **local network**: the TV shows a QR code, a
phone / PC on the same WiFi opens the pairing page, and credentials are POSTed
**straight to the TV** — no third-party service, zero typing on the TV. The
pairing server only listens while the dialog is open, stops immediately on
close, and uses a one-time pairing code to prevent stray submissions.

One-time setup (about 3 minutes):

1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
   create an OAuth client of type "**Desktop app**"; note `client_id` and
   `client_secret`.
2. On the OAuth consent screen enable the Google Drive API, add
   `https://www.googleapis.com/auth/drive.readonly` as a test scope, and add
   your own account under "**Test users**" (required for unverified apps).
3. On the TV open "Network media -> Network drive -> **Add Google Drive**";
   a QR code, LAN address and a 6-character pairing code are shown.
4. On a PC run (Python 3 stdlib only, no dependencies):

   ```bash
   python tools/gdrive_auth.py \
     --client-id "xxxx.apps.googleusercontent.com" \
     --client-secret "GOCSPX-xxxx" \
     --pair-url "http://192.168.1.20:18780/?pair=AB3D7K"
   ```

   A browser opens the Google login page; after consent the script pushes the
   `refresh_token` to the TV. `--pair-url` is the QR content (or paste the
   address shown on screen).
5. The TV shows "paired + account"; press "Done". Select the source to browse
   your Drive, with the same playback, queue, starred favourites and embedded
   tag / cover reading as WebDAV / FTP.

> A `refresh_token` can also be generated manually with
> [Google OAuth Playground](https://developers.google.com/oauthplayground/)
> and pasted into the pairing page. Credentials live only in the TV's local
> `SharedPreferences`, never logged or committed. Google reachability required.

**About test users and token lifetime (important)**

- Each user creates **their own** Cloud project and is its only test user, so
  **anyone can complete the steps above**. The 100-user cap applies to a single
  project's test allowlist; a self-hosted project has exactly one user.
- However, apps in **Testing** status are issued `refresh_token`s that **expire
  after 7 days** (Google's rule: only exempt when the sole requested scopes are
  `userinfo.email/profile/openid`; this app requests `drive.readonly`). So expect
  to **re-run `gdrive_auth.py` roughly once a week**: open "Add Google Drive"
  on the TV again to get a fresh QR / `--pair-url`, then run the same command —
  no other changes needed. The app reports "authorization expired" with the same
  guidance when the token stops working.
- Shipping **one client that works out of the box for everyone** requires
  publishing the consent screen to In production and passing OAuth verification.
  `drive.readonly` is a **Restricted scope**, which additionally requires brand
  verification (owned domain + privacy policy), an allowed app category, an
  end-to-end demo video, a narrowest-scope justification, and an **annual
  third-party security assessment** by a Google-empanelled assessor (paid).
  Desktop-app `client_secret` values are explicitly non-secret per Google, so
  secrecy cannot bypass this. A "published but unverified" app is technically
  usable by any Google account but carries a 100-user cap and a danger warning.
  For a personal / self-hosted open-source project, per-user credentials remain
  the pragmatic choice.

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
| `v1.1.2` (later builds) | Now-playing scale restoration and auto-hiding controls, network-drive backport (embedded tags / favourites), D-pad reachability fixes (assets were replaced via `--clobber`) |
| **`v1.2.0`** | **Dedicated release tags from now on; fixed now-playing D-pad focus (lyric lines stealing focus / focus loss / stray activation of off-screen favorites), Bilibili video cover auto-display with square scaling, highest available Bilibili audio quality** |
| **`v1.3.0`** | **New read-only Google Drive source: LAN QR pairing, zero typing on TV, local auth helper; model / proxy / service / TV entry and bilingual docs** |
| **`v1.4.0`** | **Now-playing visual normalization, real-time lyric selection inside Lyrics Settings, Google Drive testing-status limits and re-auth guidance** |
| **`v1.5.0`** | **Fixed oversized song/artist title and large-screen inflation; kept one-shot static blur with no new real-time blur; added a Go/Fyne Google Drive pairing helper and restyled phone pairing page** |
| **`v1.5.1`** | **Actually fixed song/artist title size (A/B verified), added Windows helper, confirmed QR pairing page as the mobile fallback** |
| **`v1.6.0`** | **Added two-level Bilibili account favorites browsing (coexisting with local starred favorites); history stays local** |
| **`v1.6.1`** | **Fixed global D-pad deadlock and full-width list rows being misclassified as containers; all main content areas are D-pad reachable again** |

```bash
git checkout tv-v4-focus-fix      # return to an anchor
git revert <commit>               # undo a change while keeping the audit trail
```

## 14. Credits

- [xiaobaimc/myune_music](https://github.com/xiaobaimc/myune_music) — upstream desktop app and its Apache-2.0 source
- [mpv_audio_kit](https://github.com/ales-drnz/mpv_audio_kit) (BSD-3-Clause) and the mpv / FFmpeg communities
- [lyricGeter](https://github.com/WisteriaZy/lyricGeter) — reference for lyric fetching and parsing
- Xiaomi MiSans font, and the Flutter / Rust / Dart open-source communities
