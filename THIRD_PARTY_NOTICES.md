# Third-party notices

Lunar Horizon's own code is under the MIT licence ([LICENSE](LICENSE)). This file lists the third-party material that the app ships, with the licence stated in each package's own licence file (versions from `app/pubspec.lock`, `charts/package-lock.json` and `pipeline/requirements.txt`, checked on 7 November 2026).

## App (web app and Android APK)

Built with the Flutter SDK 3.44.6 (BSD 3-Clause) from the dependency graph of `app/pubspec.yaml` without its test-only packages (`flutter pub deps --no-dev`). Some packages are used only at build time or only on platforms this project does not ship (Windows, Linux); they are listed because they are in that graph.

| Package | Licence |
|---|---|
| Flutter SDK (`flutter`, `flutter_web_plugins`, `sky_engine`) | BSD 3-Clause |
| `archive` 4.3.0 | MIT; parts derived from zlib.js (MIT), JZlib and bzip2 (BSD-style), see its `LICENSE-other.md` |
| `cupertino_icons` 1.0.9 (the CupertinoIcons font) | MIT |
| `provider` 6.1.5+1 | MIT |
| `intl` 0.20.3, `share_plus` 13.3.1, `shared_preferences` 2.5.6, `web` 1.1.1, `webview_flutter` 4.14.1, `webview_flutter_android` 4.14.1 | BSD 3-Clause |

Packages these bring in:

- **MIT:** `nested`, `posix`, `uuid`, `yaml`.
- **Apache 2.0:** `clock`, `material_color_utilities`.
- **BSD 3-Clause, with parts under the zlib licence:** `vector_math`.
- **BSD 3-Clause:** `args`, `characters`, `code_assets`, `collection`, `cross_file`, `crypto`, `ffi`, `ffi_leak_tracker`, `file`, `fixnum`, `hooks`, `jni`, `jni_flutter`, `jni_util`, `logging`, `meta`, `mime`, `objective_c`, `package_config`, `path`, `path_provider` (with `path_provider_android`, `_foundation`, `_linux`, `_platform_interface` and `_windows`), `platform`, `plugin_platform_interface`, `pub_semver`, `record_use`, `share_plus_platform_interface`, `shared_preferences_android`, `_foundation`, `_linux`, `_platform_interface`, `_web` and `_windows`, `source_span`, `string_scanner`, `term_glyph`, `typed_data`, `url_launcher_linux`, `url_launcher_platform_interface`, `url_launcher_web`, `url_launcher_windows`, `webview_flutter_platform_interface`, `webview_flutter_wkwebview`, `win32`, `xdg_directories`.

**Material Icons font.** `uses-material-design: true` bundles `MaterialIcons-Regular.otf` by Google from the Flutter SDK (`bin/cache/artifacts/material_fonts`). Its licence file there, `MaterialIcons_LICENSE.txt`, is the Creative Commons Attribution 4.0 International licence (CC BY 4.0). Release builds keep only the icons the app uses (Flutter's icon tree shaking).

**Flutter engine.** The engine, and CanvasKit in the web build (served from the app's own `canvaskit/` folder), include third-party components such as Skia, ICU, HarfBuzz, FreeType, BoringSSL, zlib, libpng, libwebp and Wuffs, each under its own licence. Every Flutter build carries the full licence texts of these components and of the Dart packages in its `NOTICES` file (`assets/NOTICES` in the web build).

**Android libraries.** The APK also contains AndroidX libraries (for example `androidx.webkit`, `androidx.annotation`, `androidx.core`, `androidx.datastore` and `androidx.preference`, used by the plugins above), the Kotlin standard library and `kotlinx-coroutines`, all under the Apache License 2.0 (as their Maven POM files state).

## Web app files

- Roboto Regular, subset (`app/web/fonts/roboto/`): Apache License 2.0, `LICENSE.txt` beside it. It is the engine's last-resort font.

## Chart bundle (`app/assets/charts/index.html`)

| Package | Licence | Copyright |
|---|---|---|
| `react` 19.3.0, `react-dom` 19.3.0, `scheduler` 0.28.0 | MIT | Meta Platforms, Inc. and affiliates |
| `plotly.js-basic-dist-min` 4.1.2 | MIT | Plotly Technologies Inc. |
| inside Plotly.js: `native-promise-only` 0.8.1, `polybooljs`, `object-assign` | MIT | Kyle Simpson; Sean Connelly; Sindre Sorhus |
| `@fontsource/ibm-plex-sans`, `@fontsource/ibm-plex-mono` 5.3.0 | SIL OFL 1.1 | IBM Corp. |

Build tools, not shipped: `vite` 8.3.4, `@vitejs/plugin-react` 6.1.2, `vite-plugin-singlefile` 2.3.3, `vitest` 4.1.11, `@types/react` and `@types/react-dom` (MIT); `typescript` 5.9.3 (Apache 2.0).

## Fonts in the app

- IBM Plex Sans and IBM Plex Mono, Copyright © 2017 IBM Corp., SIL Open Font License 1.1 (`app/assets/fonts/LICENSE-IBMPlexSans.txt`, `LICENSE-IBMPlexMono.txt`).

## Data

- NASA/JPL NAIF SPICE kernels, LRO LOLA products from the PDS Geosciences Node and JPL Horizons output: public NASA data, credited in the [README](README.md#data-sources-and-credits). NAIF's rules let anyone use its kernels: <https://naif.jpl.nasa.gov/naif/rules.html>. The repository does not hold the kernels or the DEMs; it holds 48 cached Horizons responses (`pipeline/validation/horizons_cache/`).
- The files in `app/assets/data/` are this project's output, derived from that data, under the MIT licence.

## Python pipeline and library

| Package | Licence |
|---|---|
| SpiceyPy 8.2.0 (wraps NAIF's CSPICE toolkit, whose terms are NAIF's rules above) | MIT |
| NumPy 2.5.3 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 |
| Pillow 12.3.0 | MIT-CMU |
| Requests 2.34.2 | Apache 2.0 |
| pytest 9.1.1 | MIT |
| matplotlib (optional `plot` extra of `pylib/`) | Matplotlib licence (PSF-based) |

## Demo video soundtrack

- Piano sound: FluidR3_GM SoundFont by Frank Wen (MIT licence). The music and the UI sounds are original (see [docs/submission.md](docs/submission.md#references)).

## Tools (used, not shipped)

Flutter <https://flutter.dev> (BSD 3-Clause); Node.js <https://nodejs.org> (MIT); Python <https://www.python.org> (PSF-2.0); Blender 5.1 <https://www.blender.org> (GPL-2.0-or-later); FFmpeg 6.1.1 <https://ffmpeg.org> (LGPL-2.1-or-later; the Ubuntu build used is configured with `--enable-gpl`); FluidSynth 2.3.4 (LGPL-2.1-or-later); Playwright (Apache 2.0) with Chromium (BSD 3-Clause); mido 1.3.3 and pyloudnorm 0.2.0 (MIT) and SciPy <https://scipy.org> (BSD 3-Clause), used by the demo-video audio scripts, which are not in the repository.
