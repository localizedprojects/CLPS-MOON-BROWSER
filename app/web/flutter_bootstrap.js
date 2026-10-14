{{flutter_js}}
{{flutter_build_config}}

// Everything loads from this app's own host, so the app works offline and
// from one host (no request leaves it):
// - CanvasKit from the app's canvaskit/ folder (copied into the build)
//   instead of the gstatic.com CDN.
// - The engine's fallback fonts from the app's fonts/ folder instead of
//   fonts.gstatic.com. The engine always loads Roboto as its last-resort
//   font, at the fixed path roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2
//   under this base. The file there is Roboto Regular (Apache-2.0, from the
//   Flutter SDK's material_fonts, LICENSE.txt beside it) subset to Latin,
//   Greek, punctuation, arrows, maths and shapes, stored as plain TrueType
//   (CanvasKit reads it whatever the extension). The app's own text is IBM
//   Plex (bundled assets). A character that neither Plex nor this Roboto
//   has would make the engine ask fonts/ for a Noto font, which is not
//   here: the app's strings must stay within these two fonts.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "fonts/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
