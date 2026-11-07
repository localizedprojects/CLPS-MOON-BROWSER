import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The licence texts the app adds to Flutter's own NOTICES (Learn › Credits ›
/// Open-source licences, [showLicensePage]): the IBM Plex fonts (SIL OFL 1.1,
/// read from the licence files bundled beside them), the Material Icons font
/// (CC BY 4.0) and, on the web, the engine's Roboto (Apache 2.0), and the
/// notices of the software compiled into the chart bundle
/// (`assets/charts/index.html`): MIT, and the BSD-3-Clause and ISC licences of
/// the d3 modules inside plotly.js. Flutter's NOTICES already holds the Dart
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
    'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED '
    'WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR '
    'PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, '
    'INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF '
    'SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY '
    'THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING '
    'IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.';
const _isc = 'Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is '
    'hereby granted, provided that the above copyright notice and this permission notice appear in all copies.'
    '\n\n'
    'THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING '
    'ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, '
    'DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, '
    'WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE '
    'USE OR PERFORMANCE OF THIS SOFTWARE.';

/// The d3 modules plotly.js compiles into the chart bundle (plotly.js 4.1.2's
/// dependencies at its release): each package, then its licence text with the
/// copyright line of that package's LICENSE file.
const chartBundleD3Notices = <(String, String)>[
  ('@plotly/d3', 'BSD 3-Clause License (D3 3.8.2)\n\nCopyright (c) 2010-2016, Michael Bostock\nAll rights reserved.\n\n$_bsdD3v3'),
  ('d3-format', 'BSD 3-Clause License\n\nCopyright 2010-2015 Mike Bostock\nAll rights reserved.\n\n$_bsdD3'),
  ('d3-time', 'BSD 3-Clause License\n\nCopyright 2010-2016 Mike Bostock\nAll rights reserved.\n\n$_bsdD3'),
  ('d3-time-format', 'BSD 3-Clause License\n\nCopyright 2010-2017 Mike Bostock\nAll rights reserved.\n\n$_bsdD3'),
  ('d3-interpolate', 'ISC License\n\nCopyright 2010-2021 Mike Bostock\n\n$_isc'),
  ('d3-color', 'ISC License\n\nCopyright 2010-2022 Mike Bostock\n\n$_isc'),
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
  for (final (package, text) in chartBundleD3Notices) {
    yield LicenseEntryWithLineBreaks([package], text);
  }
}

/// Adds [appLicenses] to Flutter's [LicenseRegistry] (once, from `main`).
void registerAppLicenses() => LicenseRegistry.addLicense(appLicenses);
