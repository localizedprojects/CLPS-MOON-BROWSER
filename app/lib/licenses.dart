import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The licence texts the app adds to Flutter's own NOTICES (Learn › Credits ›
/// Open-source licences, [showLicensePage]): the IBM Plex fonts (SIL OFL 1.1,
/// read from the licence files bundled beside them), the Material Icons font
/// (CC BY 4.0) and, on the web, the engine's Roboto (Apache 2.0), and the
/// notices of the software compiled into the chart bundle
/// (`assets/charts/index.html`): MIT, the BSD-3-Clause licences of the d3
/// modules and the maplibre-gl stylesheet inside plotly.js, and gl-mat4's
/// zlib licence. The list matches the chart-bundle table of
/// THIRD_PARTY_NOTICES.md, which was checked against the unminified
/// plotly.js-basic-dist 4.1.2 build. Flutter's NOTICES already holds the Dart
/// and Flutter packages, but not those two fonts.

/// The bundled IBM Plex licence files and the typeface each one covers.
const plexLicenseAssets = <(String, String)>[
  ('IBM Plex Sans', 'assets/fonts/LICENSE-IBMPlexSans.txt'),
  ('IBM Plex Mono', 'assets/fonts/LICENSE-IBMPlexMono.txt'),
];

const _mit = 'Permission is hereby granted, free of charge, to any person obtaining a copy of this software and '
    'associated documentation files (the "Software"), to deal in the Software without restriction, including without '
    'limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the '
    'Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:'
    '\n\n'
    'The above copyright notice and this permission notice shall be included in all copies or substantial portions '
    'of the Software.'
    '\n\n'
    'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO '
    'THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE '
    'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF '
    'CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER '
    'DEALINGS IN THE SOFTWARE.';

/// The chart bundle's third-party software, as its banner lists it: the
/// packages each MIT notice covers, then its copyright line (from the
/// packages' LICENSE files, and for the code plotly.js includes, the notices
/// it carries).
const chartBundleNotices = <(List<String>, String)>[
  (['react', 'react-dom', 'scheduler'], 'Copyright (c) Meta Platforms, Inc. and affiliates.'),
  (['plotly.js'], 'Copyright (c) 2016-2024 Plotly Technologies Inc.'),
  (['native-promise-only'], 'Native Promise Only v0.8.1 (c) Kyle Simpson'),
  (['polybooljs'], 'Copyright 2016 Sean Connelly (@voidqk), http://syntheti.cc'),
  (['object-assign'], '(c) Sindre Sorhus'),
];

// The BSD-3-Clause texts as the d3 packages' LICENSE files give them: D3 3
// (Plotly's @plotly/d3 3.8.2) names Michael Bostock in clause 3 and the
// disclaimer; the later modules say "the author" and "the copyright owner".
const _bsdHead = 'Redistribution and use in source and binary forms, with or without modification, are permitted '
    'provided that the following conditions are met:'
    '\n\n'
    '* Redistributions of source code must retain the above copyright notice, this list of conditions and the '
    'following disclaimer.'
    '\n\n'
    '* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the '
    'following disclaimer in the documentation and/or other materials provided with the distribution.'
    '\n\n';
const _bsdD3v3 = '$_bsdHead'
    '* The name Michael Bostock may not be used to endorse or promote products derived from this software without '
    'specific prior written permission.'
    '\n\n'
    'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED '
    'WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR '
    'PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MICHAEL BOSTOCK BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, '
    'SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR '
    'SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF '
    'LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY '
    'OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.';
const _bsdD3 = '$_bsdHead'
    '* Neither the name of the author nor the names of contributors may be used to endorse or promote products '
    'derived from this software without specific prior written permission.'
    '\n\n'
    '$_bsdOwnerDisclaimer';
const _bsdOwnerDisclaimer = 'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED '
    'WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR '
    'PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, '
    'INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF '
    'SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY '
    'THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING '
    'IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.';
/// The d3 modules plotly.js compiles into the chart bundle (plotly.js 4.1.2's
/// dependencies at its release): each package, then its licence text with the
/// copyright line of that package's LICENSE file.
const chartBundleD3Notices = <(String, String)>[
  ('@plotly/d3', 'BSD 3-Clause License (D3 3.8.2)\n\n@plotly/d3 3.8.2 (a fork of d3 v3), compiled into plotly.js.\n\n'
      'Copyright (c) 2010-2016, Michael Bostock\nAll rights reserved.\n\n$_bsdD3v3'),
  ('d3-format', 'BSD 3-Clause License\n\nd3-format 1.4.5, compiled into plotly.js.\n\n'
      'Copyright 2010-2015 Mike Bostock\nAll rights reserved.\n\n$_bsdD3'),
  ('d3-time', 'BSD 3-Clause License\n\nd3-time 1.1.0, compiled into plotly.js.\n\n'
      'Copyright 2010-2016 Mike Bostock\nAll rights reserved.\n\n$_bsdD3'),
  ('d3-time-format', 'BSD 3-Clause License\n\nd3-time-format 2.3.0, compiled into plotly.js.\n\n'
      'Copyright 2010-2017 Mike Bostock\nAll rights reserved.\n\n$_bsdD3'),
];

/// The other non-MIT parts of plotly.js 4.1.2 in the chart bundle: the
/// maplibre-gl stylesheet (its LICENSE.txt: the MapLibre and the
/// mapbox-gl-js BSD 3-Clause texts) and gl-mat4 (zlib, its LICENSE.md).
const chartBundleOtherNotices = <(String, String)>[
  ('maplibre-gl', 'BSD 3-Clause License\n\n'
      'The stylesheet of maplibre-gl 6.11.2, which plotly.js carries; the basic bundle never adds it to the page.\n\n'
      'Copyright (c) 2023, MapLibre contributors\n\nAll rights reserved.\n\n'
      '$_bsdHead'
      '* Neither the name of MapLibre GL JS nor the names of its contributors may be used to endorse or promote '
      'products derived from this software without specific prior written permission.'
      '\n\n'
      '$_bsdOwnerDisclaimer'
      '\n\n'
      'Contains code from mapbox-gl-js v1.13 and earlier'
      '\n\n'
      'Version v1.13 of mapbox-gl-js and earlier are licensed under a BSD-3-Clause license'
      '\n\n'
      'Copyright (c) 2020, Mapbox'
      '\n\n'
      '$_bsdHead'
      '* Neither the name of Mapbox GL JS nor the names of its contributors may be used to endorse or promote '
      'products derived from this software without specific prior written permission.'
      '\n\n'
      '$_bsdOwnerDisclaimer'),
  ('gl-mat4', 'zlib License\n\ngl-mat4 1.2.0, compiled into plotly.js.\n\n'
      'Copyright (c) 2013 Brandon Jones, Colin MacKenzie IV'
      '\n\n'
      "This software is provided 'as-is', without any express or implied warranty. In no event will the authors be "
      'held liable for any damages arising from the use of this software.'
      '\n\n'
      'Permission is granted to anyone to use this software for any purpose, including commercial applications, and '
      'to alter it and redistribute it freely, subject to the following restrictions:'
      '\n\n'
      ' 1. The origin of this software must not be misrepresented you must not claim that you wrote the original '
      'software. If you use this software in a product, an acknowledgment in the product documentation would be '
      'appreciated but is not required.'
      '\n\n'
      ' 2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the '
      'original software.'
      '\n\n'
      ' 3. This notice may not be removed or altered from any source distribution.'),
];

/// The small MIT packages plotly.js 4.1.2 compiles in without a licence
/// comment: each package, its version, then the copyright line of its
/// LICENSE file (is-mobile and has-hover ship none: their package.json gives
/// the MIT licence and the author).
const chartBundlePlotlyMitNotices = <(String, String, String)>[
  ('culori', '4.0.2', 'Copyright (c) 2018 Dan Burzo'),
  ('world-calendars', '1.0.4',
      'Copyright (c) 2016 alexcjohnson\n\nBatch-converted from Calendars for jQuery 2.0.2, written by Keith Wood '
      '(August 2009), available under the MIT licence.'),
  ('is-mobile', '5.0.0', 'Julian Gruber (the author in its package.json, which gives the MIT licence; the package has '
      'no licence file).'),
  ('fast-isnumeric', '1.1.4', 'Copyright (c) 2015 Alex Johnson'),
  ('is-string-blank', '1.0.1', 'Copyright (c) 2015 Alex Johnson'),
  ('base64-arraybuffer', '1.0.2', 'Copyright (c) 2012 Niklas von Hertzen'),
  ('events', '3.3.0', 'Copyright Joyent, Inc. and other Node contributors.'),
  ('is-browser', '2.1.0', 'Copyright (c) 2013 Forbes Lindesay'),
  ('has-hover', '1.0.1', 'Dima Yv (the author in its package.json, which gives the MIT licence; the package has no '
      'licence file).'),
  ('has-passive-events', '1.0.0', 'Copyright (c) 2017 Dmitry Ivanov'),
  ('mouse-event-offset', '3.0.2', 'Copyright (c) 2014 Matt DesLauriers'),
  ('parse-svg-path', '0.2.0', 'Copyright (c) 2013 Jake Rosoman <jkroso@gmail.com>'),
  ('point-in-polygon', '1.1.0', 'Copyright (c) 2016 James Halliday'),
];

/// The Material Icons font's licence (a copy of the Flutter SDK's
/// material_fonts/MaterialIcons_LICENSE.txt) and the attribution put before it.
const materialIconsLicenseAsset = 'assets/fonts/LICENSE-MaterialIcons.txt';
const materialIconsAttribution = 'Material Icons font by Google, from the Flutter SDK, licensed under the Creative '
    'Commons Attribution 4.0 International licence (https://creativecommons.org/licenses/by/4.0/). The app ships '
    'only the icons it uses (the font is subset by icon tree shaking); the icons are not changed otherwise.';

/// The web build's Roboto licence (Apache 2.0): the engine's last-resort
/// font, a subset of the Flutter SDK's Roboto Regular in web/fonts/roboto/.
const robotoLicenseAsset = 'web/fonts/roboto/LICENSE.txt';
const robotoNote = 'Roboto Regular by Google, from the Flutter SDK, subset to the characters the app needs; the '
    'web version draws with it where IBM Plex has no glyph.';

/// The entries [registerAppLicenses] adds, for the licence page; [load] reads
/// a bundled text file (the app's asset bundle by default); [web] adds the
/// web build's Roboto (Android draws with the system's own fonts).
Stream<LicenseEntry> appLicenses({Future<String> Function(String key)? load, bool web = kIsWeb}) async* {
  final read = load ?? rootBundle.loadString;
  for (final (font, asset) in plexLicenseAssets) {
    yield LicenseEntryWithLineBreaks([font], await read(asset));
  }
  yield LicenseEntryWithLineBreaks(['Material Icons'], '$materialIconsAttribution\n\n${await read(materialIconsLicenseAsset)}');
  if (web) yield LicenseEntryWithLineBreaks(['Roboto'], '$robotoNote\n\n${await read(robotoLicenseAsset)}');
  for (final (packages, copyright) in chartBundleNotices) {
    yield LicenseEntryWithLineBreaks(packages, 'MIT License\n\n$copyright\n\n$_mit');
  }
  for (final (package, version, copyright) in chartBundlePlotlyMitNotices) {
    yield LicenseEntryWithLineBreaks([package], 'MIT License\n\n$package $version, compiled into plotly.js.\n\n$copyright\n\n$_mit');
  }
  for (final (package, text) in [...chartBundleD3Notices, ...chartBundleOtherNotices]) {
    yield LicenseEntryWithLineBreaks([package], text);
  }
}

/// Adds [appLicenses] to Flutter's [LicenseRegistry] (once, from `main`).
void registerAppLicenses() => LicenseRegistry.addLicense(appLicenses);
