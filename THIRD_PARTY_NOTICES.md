# Third-party notices

Lunar Horizon's own code is under the MIT licence ([LICENSE](LICENSE)). This file lists the third-party material that the app ships, with the licence stated in each package's own licence file (versions from `app/pubspec.lock`, `charts/package-lock.json` and `pipeline/requirements.txt`, checked on 7 November 2026).

## App (web app and Android APK)

Built with the Flutter SDK 3.44.6 (BSD 3-Clause) from the dependency graph of `app/pubspec.yaml` without its test-only packages (`flutter pub deps --no-dev`). Some packages are used only at build time or only on platforms this project does not ship (Windows, Linux); they are listed because they are in that graph.

| Package | Licence |
|---|---|
| Flutter SDK (`flutter`, `flutter_web_plugins`, `sky_engine`) | BSD 3-Clause |
| `archive` 4.3.0 | MIT; parts derived from zlib.js (MIT), JZlib and bzip2 (BSD-style) and PointyCastle (Bouncy Castle, MIT), see its `LICENSE-other.md` |
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
| inside Plotly.js, without licence comments: `@plotly/d3` 3.8.2 (a fork of d3 v3), `d3-format` 1.4.5, `d3-time-format` 2.3.0, `d3-time` 1.1.0 | BSD 3-Clause | Michael (Mike) Bostock |
| inside Plotly.js: the stylesheet of `maplibre-gl` 6.11.2 (the basic bundle carries it but never adds it to the page) | BSD 3-Clause | MapLibre contributors; Mapbox |
| inside Plotly.js: `gl-mat4` 1.2.0 | zlib | Brandon Jones, Colin MacKenzie IV |
| inside Plotly.js: `culori` 4.0.2, `world-calendars` 1.0.4, `is-mobile` 5.0.0, `fast-isnumeric` 1.1.4, `is-string-blank` 1.0.1, `base64-arraybuffer` 1.0.2, `events` 3.3.0, `is-browser` 2.1.0, `has-hover` 1.0.1, `has-passive-events` 1.0.0, `mouse-event-offset` 3.0.2, `parse-svg-path` 0.2.0, `point-in-polygon` 1.1.0 | MIT | Dan Burzo; alexcjohnson (from Keith Wood's jQuery Calendars); Julian Gruber; Alex Johnson; Alex Johnson; Niklas von Hertzen; Joyent, Inc. and other Node contributors; Forbes Lindesay; Dima Yv; Dmitry Ivanov; Matt DesLauriers; Jake Rosoman; James Halliday |
| `@fontsource/ibm-plex-sans`, `@fontsource/ibm-plex-mono` 5.3.0 | SIL OFL 1.1 | IBM Corp. |

Plotly.js builds the packages marked "inside Plotly.js" into its own file. Only `native-promise-only`, `polybooljs` and `object-assign` keep a licence comment there. The list and the versions come from the unminified `plotly.js-basic-dist` 4.1.2 build, which names every file it bundles, and from the `package-lock.json` of plotly.js 4.1.2. The BSD 3-Clause and zlib texts are [at the end of this file](#licence-texts-for-the-chart-bundle). The MIT text is in the [README](README.md#data-sources-and-credits).

Build tools, not shipped: `vite` 8.3.4, `@vitejs/plugin-react` 6.1.2, `vite-plugin-singlefile` 2.3.3, `vitest` 4.1.11, `@types/react` and `@types/react-dom` (MIT); `typescript` 5.9.3 (Apache 2.0).

## Fonts in the app

- IBM Plex Sans and IBM Plex Mono, Copyright © 2017 IBM Corp., SIL Open Font License 1.1 (`app/assets/fonts/LICENSE-IBMPlexSans.txt`, `LICENSE-IBMPlexMono.txt`).

## Data

- NASA/JPL NAIF SPICE kernels, LRO LOLA products from the PDS Geosciences Node and JPL Horizons output: public NASA data, credited in the [README](README.md#data-sources-and-credits). NAIF's rules let anyone use its kernels: <https://naif.jpl.nasa.gov/naif/rules.html>. The repository does not hold the kernels or the DEMs; it holds 48 cached Horizons responses for the south-pole checks (`pipeline/validation/horizons_cache/`) and 40 for the Whole Moon checks (`pipeline/validation/global/`).
- Whole Moon data (1.14.0). The shapefile and the elevation models are NASA PDS products, US Government works in the public domain with no use restrictions (SLDEM2015 also contains SELENE/Kaguya Terrain Camera data from JAXA, credited through Barker et al. 2016); JPL Horizons is a public NASA/JPL service. The app's Credits and `docs/references.md` cite them too:
  - Site coordinates: the LROC "Anthropogenic Features on the Moon" shapefile (LRO-L-LROC-5-RDR-V1.0, LROLRC_2001 `EXTRAS/SHAPEFILE/ANTHROPOGENIC_OBJECTS`, 2026-08-14 version, 71 records), <https://data.lroc.im-ldi.com/lroc/view_rdr/SHAPEFILE_ANTHROPOGENIC_OBJECTS>. Its coordinates were measured by Wagner, R. V., Nelson, D. M., Plescia, J. B., Robinson, M. S., Speyerer, E. J., & Mazarico, E. (2017), *Coordinates of anthropogenic features on the Moon*, Icarus 283, 92–103, <https://doi.org/10.1016/j.icarus.2016.05.011>; cite the paper. Only the coordinates and record fields of 20 records are used (quoted in `app/assets/data/global/sites.json`); the shapefile itself is not in the repository.
  - Terrain: LOLA LDEM_16, LDEM_64 and LDEM_512 (LRO-L-LOLA-4-GDR-V1.0) and SLDEM2015 512 px/deg (LOLA + SELENE/Kaguya Terrain Camera; Barker, M. K., et al. (2016), *A new lunar digital elevation model from the Lunar Orbiter Laser Altimeter and SELENE Terrain Camera*, Icarus 273, 346–355, <https://doi.org/10.1016/j.icarus.2015.07.039>), from the PDS Geosciences Node (LOLA volume `LROLOL_1XXX`, <https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/>: `lola_gdr/cylindrical/` and `sldem2015/tiles/`). The repository does not hold them; it holds products derived from them.
  - Cross-check: JPL Horizons, <https://ssd.jpl.nasa.gov/horizons/>, a NASA/JPL service, queried for 10 Whole Moon sites on 2026-11-09.
- The files in `app/assets/data/` (with `app/assets/data/global/`) are this project's output, derived from that data, under the MIT licence.

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

## Licence texts for the chart bundle

These are the BSD 3-Clause and zlib texts of the chart bundle parts above, copied from each package's own licence file.

### `@plotly/d3` 3.8.2 (`LICENSE`)

```text
Copyright (c) 2010-2016, Michael Bostock
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* The name Michael Bostock may not be used to endorse or promote products
  derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL MICHAEL BOSTOCK BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### `d3-format` 1.4.5, `d3-time-format` 2.3.0 and `d3-time` 1.1.0 (`LICENSE`)

The three files have the same text. Only the first line differs: `Copyright 2010-2015 Mike Bostock` (`d3-format`), `Copyright 2010-2017 Mike Bostock` (`d3-time-format`) and `Copyright 2010-2016 Mike Bostock` (`d3-time`). This is the `d3-format` file:

```text
Copyright 2010-2015 Mike Bostock
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the author nor the names of contributors may be used to
  endorse or promote products derived from this software without specific prior
  written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### `maplibre-gl` 6.11.2 (`LICENSE.txt`, its MapLibre and mapbox-gl-js parts)

```text
Copyright (c) 2023, MapLibre contributors

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Neither the name of MapLibre GL JS nor the names of its contributors
      may be used to endorse or promote products derived from this software
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


-------------------------------------------------------------------------------

Contains code from mapbox-gl-js v1.13 and earlier

Version v1.13 of mapbox-gl-js and earlier are licensed under a BSD-3-Clause license

Copyright (c) 2020, Mapbox
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
* Neither the name of Mapbox GL JS nor the names of its contributors
  may be used to endorse or promote products derived from this software
  without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### `gl-mat4` 1.2.0 (`LICENSE.md`)

```text
Copyright (c) 2013 Brandon Jones, Colin MacKenzie IV

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

 1. The origin of this software must not be misrepresented you must not
    claim that you wrote the original software. If you use this software
    in a product, an acknowledgment in the product documentation would be
    appreciated but is not required.

 2. Altered source versions must be plainly marked as such, and must not
    be misrepresented as being the original software.

 3. This notice may not be removed or altered from any source distribution.
```
