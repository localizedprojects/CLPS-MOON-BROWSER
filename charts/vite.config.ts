/// <reference types="vitest/config" />
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import { viteSingleFile } from 'vite-plugin-singlefile'
import plotlyPkg from './node_modules/plotly.js-basic-dist-min/package.json'
import reactPkg from './node_modules/react/package.json'
import reactDomPkg from './node_modules/react-dom/package.json'
import schedulerPkg from './node_modules/scheduler/package.json'

/**
 * Third-party notices for the shipped bundle. The minifier keeps legal
 * comments (`@license`, `/*!`) inline, which covers React and the libraries
 * plotly.js bundles, but plotly.js's own header is a plain comment, so a
 * `/*!` banner names every runtime package with its version and licence
 * (versions read from each package.json).
 */
function notices(): string {
  const line = (p: { name: string; version: string; license?: string }, who: string) =>
    ` * ${p.name} v${p.version} | ${who} | ${p.license ?? 'see package'} license`
  return [
    '/*! Lunar Horizon charts. Third-party software in this file:',
    line(plotlyPkg, 'Copyright 2012-2026, Plotly, Inc.'),
    line(reactPkg, 'Copyright (c) Meta Platforms, Inc. and affiliates.'),
    line(reactDomPkg, 'Copyright (c) Meta Platforms, Inc. and affiliates.'),
    line(schedulerPkg, 'Copyright (c) Meta Platforms, Inc. and affiliates.'),
    ' * IBM Plex Sans and IBM Plex Mono (via @fontsource) | Copyright IBM Corp. | SIL Open Font License 1.1',
    ' * The MIT and OFL texts are in the packages above; the notices bundled with plotly.js follow inline.',
    ' */',
  ].join('\n')
}

/**
 * Chrome < 64 cannot parse Unicode property escapes (\p{...}): Plotly's
 * slugify has two as regex literals, a SyntaxError for the whole bundle on
 * Android 7's WebView (Chrome 51). Each becomes the same regex wherever the
 * browser builds it and, where it cannot, an approximation over ASCII and the
 * common BMP blocks. Only the default file name of Plotly.downloadImage uses
 * them, which the charts never call (they use Plotly.toImage).
 */
const PLOTLY_REGEXES: Array<[literal: string, source: string, fallback: string]> = [
  ['/[\\p{S}\\p{P}]/gu', '[\\p{S}\\p{P}]',
    '/[!-\\/:-@[-`{-~\\xA1-\\xBF\\xD7\\xF7\\u2010-\\u2027\\u2030-\\u205E\\u20A0-\\u20CF\\u2100-\\u2BFF\\u3001-\\u3003\\u3008-\\u3020\\uFF01-\\uFF0F]/g'],
  ['/[\\p{Cc}\\p{Cf}\\uFE00-\\uFE0F\\u20E3]/gu', '[\\p{Cc}\\p{Cf}\\uFE00-\\uFE0F\\u20E3]',
    '/[\\0-\\x1F\\x7F-\\x9F\\xAD\\u0600-\\u0605\\u061C\\u06DD\\u070F\\u180E\\u200B-\\u200F\\u202A-\\u202E\\u2060-\\u2064\\u2066-\\u206F\\uFEFF\\uFFF9-\\uFFFB\\uFE00-\\uFE0F\\u20E3]/g'],
]
function plotlyOldRegex(): Plugin {
  return {
    name: 'ph:plotly-old-regex',
    apply: 'build',
    transform(code, id) {
      if (!id.includes('plotly.js-basic-dist-min')) return null
      let out = code
      for (const [lit, src, fallback] of PLOTLY_REGEXES) {
        if (!out.includes(lit)) this.error(`plotly.js no longer has ${lit}: recheck the Chrome 51 regex fallback`)
        const safe = `(function(){try{return new RegExp(${JSON.stringify(src)},"gu")}catch(e){return ${fallback}}})()`
        out = out.split(lit).join(safe)
      }
      return { code: out, map: null }
    },
  }
}

/**
 * Chrome < 61 runs no <script type="module">, so the inlined bundle is built
 * as one IIFE (output.format) and served as a classic script at the end of
 * <body>, where it runs once the page is parsed, as the deferred module did.
 */
function classicScript(): Plugin {
  return {
    name: 'ph:classic-script',
    apply: 'build',
    enforce: 'post', // after vite:singlefile has inlined the script
    generateBundle(_, bundle) {
      for (const f of Object.values(bundle)) {
        if (f.type !== 'asset' || !f.fileName.endsWith('.html')) continue
        const html = String(f.source)
        const m = /<script type="module" crossorigin>([\s\S]*?)<\/script>\n?/.exec(html)
        if (!m || !html.includes('</body>')) this.error('index.html: no inlined module script to make classic')
        const js = m[1]
        // replacer functions: the bundle's "$&" and "$1" are code, not patterns
        f.source = html.replace(m[0], () => '').replace('</body>', () => `<script>${js}</script>\n  </body>`)
      }
    },
  }
}

// Single self-contained index.html: Android WebViews refuse ES-module
// <script src> loads from file:// assets, but inline scripts work.
export default defineConfig(({ command }) => ({
  base: './',
  plugins: [react(), plotlyOldRegex(), viteSingleFile(), classicScript()],
  build: {
    outDir: '../app/assets/charts',
    emptyOutDir: true,
    // The app supports Android 7.0+, whose stock WebView is Chrome 51 (the
    // API 24 emulator's: 51.0.2704). Newer syntax (async/await, object
    // spread, ?? ?. ...) is a SyntaxError there and every chart stays blank,
    // so the whole bundle (the libraries too) is lowered to what Chrome 51
    // parses; the CSS follows the same target. The runtime APIs newer than
    // Chrome 51 that the bundle names are polyfilled first
    // (src/polyfills.ts), feature-tested (globalThis, ResizeObserver, ...)
    // or on a path Chrome 51 never takes (React's view transitions).
    // src/bundleTarget.test.ts checks all three. Sorting (stable only from
    // Chrome 70) goes through format.ts sortedStable.
    // chartMinChromeMajor (app/lib/widgets/chart_bridge.dart) equals this.
    target: ['es2015', 'chrome51'],
    chunkSizeWarningLimit: 6000,
    rolldownOptions: {
      output: {
        format: 'iife', // a classic script: see classicScript()
        strict: true, // "use strict" for the whole script, as the module was
        // keep @license / /*! comments (React, plotly.js's bundled notices); drop the rest
        comments: { legal: true, annotation: false, jsdoc: false },
        banner: command === 'build' ? notices() : undefined,
      },
    },
  },
  test: { environment: 'node', include: ['src/**/*.test.ts'] },
}))
