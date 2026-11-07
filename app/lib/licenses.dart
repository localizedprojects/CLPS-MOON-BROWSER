import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The licence texts the app adds to Flutter's own NOTICES (Learn › Credits ›
/// Open-source licences, [showLicensePage]): the IBM Plex fonts (SIL OFL 1.1,
/// read from the licence files bundled beside them) and the MIT notices of the
/// software compiled into the chart bundle (`assets/charts/index.html`).
/// Flutter's NOTICES already holds the Dart and Flutter packages.

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

/// The entries [registerAppLicenses] adds, for the licence page; [load] reads
/// a bundled text file (the app's asset bundle by default).
Stream<LicenseEntry> appLicenses({Future<String> Function(String key)? load}) async* {
  final read = load ?? rootBundle.loadString;
  for (final (font, asset) in plexLicenseAssets) {
    yield LicenseEntryWithLineBreaks([font], await read(asset));
  }
  for (final (packages, copyright) in chartBundleNotices) {
    yield LicenseEntryWithLineBreaks(packages, 'MIT License\n\n$copyright\n\n$_mit');
  }
}

/// Adds [appLicenses] to Flutter's [LicenseRegistry] (once, from `main`).
void registerAppLicenses() => LicenseRegistry.addLicense(appLicenses);
