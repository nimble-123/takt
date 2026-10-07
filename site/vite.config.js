import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

// The app version lives in project.yml and is bumped by release-please,
// so the site never needs a manual version update.
const projectYml = readFileSync(fileURLToPath(new URL('../project.yml', import.meta.url)), 'utf8')
const version = projectYml.match(/MARKETING_VERSION:\s*([\d.]+)/)?.[1] ?? '0.0.0'

export default defineConfig({
  base: process.env.SITE_BASE ?? '/takt/',
  define: {
    __TAKT_VERSION__: JSON.stringify(version),
  },
  server: {
    fs: { allow: ['..'] },
  },
  build: {
    target: 'es2022',
    assetsInlineLimit: 0,
  },
})
