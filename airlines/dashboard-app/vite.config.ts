import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const dashboard = process.env.DASHBOARD ?? 'flight-ops'

const entries: Record<string, string> = {
  'flight-ops':    './src/entries/flight-ops.tsx',
  'passenger-svc': './src/entries/passenger-svc.tsx',
  'airport-ops':   './src/entries/airport-ops.tsx',
  'flight-board':  './src/entries/flight-board.tsx',
}

const entry = entries[dashboard]
if (!entry) throw new Error(`Unknown DASHBOARD: ${dashboard}`)

export default defineConfig({
  plugins: [react(), tailwindcss()],
  base: '/',
  build: {
    outDir: '../helm/files/dashboard-app',
    emptyOutDir: true,
    rollupOptions: {
      input: entry,
      output: {
        entryFileNames: 'assets/index.js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/index[extname]',
      },
    },
  },
})
