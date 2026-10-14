/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
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

// Single self-contained index.html: Android WebViews refuse ES-module
// <script src> loads from file:// assets, but inline scripts work.
export default defineConfig(({ command }) => ({
  base: './',
  plugins: [react(), viteSingleFile()],
  build: {
    outDir: '../app/assets/charts',
    emptyOutDir: true,
    chunkSizeWarningLimit: 6000,
    rolldownOptions: {
      output: {
        // keep @license / /*! comments (React, plotly.js's bundled notices); drop the rest
        comments: { legal: true, annotation: false, jsdoc: false },
        banner: command === 'build' ? notices() : undefined,
      },
    },
  },
  test: { environment: 'node', include: ['src/**/*.test.ts'] },
}))
