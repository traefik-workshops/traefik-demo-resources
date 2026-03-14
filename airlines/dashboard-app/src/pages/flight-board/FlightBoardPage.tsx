import { useEffect, useState, useMemo } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { useFlightBoard } from '../../hooks/useFlightBoard'
import { formatTime, statusColor } from '../../lib/utils'
import type { Flight } from '../../types'

// ── FlapChar — single split-flap character ────────────────────────────────
function FlapChar({ char, color }: { char: string; color?: string }) {
  const [displayed, setDisplayed] = useState(char)
  const [flipping, setFlipping] = useState(false)

  useEffect(() => {
    if (char === displayed) return
    setFlipping(true)
    const t = setTimeout(() => { setDisplayed(char); setFlipping(false) }, 120)
    return () => clearTimeout(t)
  }, [char])

  return (
    <span
      className="inline-block w-[1ch] text-center tabular-nums"
      style={{
        color: color ?? 'var(--color-flap-text)',
        transform: flipping ? 'rotateX(-90deg)' : 'rotateX(0deg)',
        transition: 'transform 0.12s ease-in',
        display: 'inline-block',
        transformOrigin: 'center',
      }}
    >
      {displayed || '\u00A0'}
    </span>
  )
}

// ── FlapText — padded string of FlapChars ─────────────────────────────────
function FlapText({ text, len, color }: { text: string; len: number; color?: string }) {
  const padded = text.padEnd(len, ' ').slice(0, len)
  return (
    <span style={{ fontFamily: 'Roboto Mono, monospace', letterSpacing: '0.05em' }}>
      {padded.split('').map((ch, i) => <FlapChar key={i} char={ch} color={color} />)}
    </span>
  )
}

// ── Clock with flapping digits ────────────────────────────────────────────
function FlapClock() {
  const [time, setTime] = useState(() =>
    new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false })
  )
  useEffect(() => {
    const t = setInterval(() => setTime(
      new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false })
    ), 1000)
    return () => clearInterval(t)
  }, [])
  return <FlapText text={time} len={8} color="var(--color-traefik-teal-bright)" />
}

// ── Flight row ────────────────────────────────────────────────────────────
function FlightRow({ flight, isNew }: { flight: Flight; isNew?: boolean }) {
  const sc = statusColor(flight.status)
  return (
    <motion.tr
      initial={isNew ? { opacity: 0, x: -20 } : { opacity: 0 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, height: 0 }}
      transition={{ duration: 0.4 }}
      style={{ borderBottom: '1px solid rgba(36,161,193,0.1)' }}
    >
      <td className="px-3 py-2"><FlapText text={flight.flight_number ?? ''} len={8}  color="var(--color-traefik-teal-bright)" /></td>
      <td className="px-3 py-2"><FlapText text={`${flight.origin ?? ''}>${flight.destination ?? ''}`} len={8} /></td>
      <td className="px-3 py-2"><FlapText text={formatTime(flight.departure_time)} len={5} /></td>
      <td className="px-3 py-2"><FlapText text={flight.destination ?? ''} len={20} /></td>
      <td className="px-3 py-2"><FlapText text={flight.gate ?? '—'} len={4} /></td>
      <td className="px-3 py-2"><FlapText text={flight.terminal ?? '—'} len={2} /></td>
      <td className="px-3 py-2"><FlapText text={flight.aircraft ?? '—'} len={8} /></td>
      <td className="px-3 py-2">
        <span className="px-2 py-0.5 rounded text-xs uppercase tracking-wide" style={{ background: `${sc}22`, color: sc }}>
          {flight.status}
        </span>
      </td>
    </motion.tr>
  )
}

// ── Section (Departures / Arrivals) ───────────────────────────────────────
function BoardSection({ title, flights }: { title: string; flights: Flight[] }) {
  const COLS = ['Flight', 'Route', 'Time', 'Destination', 'Gate', 'T', 'Aircraft', 'Status']
  return (
    <div className="mb-8">
      <div
        className="flex items-center gap-3 px-3 py-2 mb-1 text-xs uppercase tracking-widest font-medium"
        style={{ background: 'rgba(36,161,193,0.1)', color: 'var(--color-traefik-teal)' }}
      >
        <span>◈</span>
        <span>{title}</span>
        <span style={{ color: 'rgba(36,161,193,0.5)' }}>({flights.length})</span>
      </div>
      <table className="w-full text-xs" style={{ fontFamily: 'Roboto Mono, monospace' }}>
        <thead>
          <tr style={{ borderBottom: '1px solid rgba(36,161,193,0.2)' }}>
            {COLS.map((h) => (
              <th key={h} className="px-3 py-2 text-left uppercase tracking-wider" style={{ color: 'rgba(36,161,193,0.5)', fontSize: '0.65rem' }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          <AnimatePresence>
            {flights.length === 0 ? (
              <tr><td colSpan={8} className="px-3 py-6 text-center" style={{ color: 'rgba(36,161,193,0.3)' }}>No flights</td></tr>
            ) : (
              flights.map((f) => <FlightRow key={f.flight_id} flight={f} />)
            )}
          </AnimatePresence>
        </tbody>
      </table>
    </div>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────
export default function FlightBoardPage() {
  const { flights, connected, loading } = useFlightBoard()

  const sortedFlights = useMemo(() =>
    [...flights].sort((a, b) => a.departure_time?.localeCompare(b.departure_time ?? '') ?? 0),
    [flights],
  )

  return (
    <div
      className="min-h-screen flex flex-col"
      style={{ background: 'var(--color-board-bg)', fontFamily: 'Roboto Mono, monospace' }}
    >
      {/* Header */}
      <header
        className="flex items-center justify-between px-6 py-4 border-b"
        style={{ background: 'var(--color-traefik-navy-dark)', borderColor: 'rgba(36,161,193,0.2)' }}
      >
        <div className="flex items-center gap-4">
          <div
            className="w-10 h-10 rounded flex items-center justify-center text-sm font-bold"
            style={{ background: 'var(--color-traefik-teal)', color: 'var(--color-traefik-navy-dark)' }}
          >
            TK
          </div>
          <div>
            <div className="text-sm font-semibold" style={{ color: 'var(--color-traefik-teal-bright)' }}>
              TRAEFIK AIRLINES
            </div>
            <div className="text-xs" style={{ color: 'rgba(36,161,193,0.5)' }}>
              FLIGHT INFORMATION
            </div>
          </div>
        </div>

        <div className="flex items-center gap-6 text-xs">
          <div className="flex items-center gap-2">
            <span
              className="w-2 h-2 rounded-full"
              style={{
                background: connected ? 'var(--color-status-on-time)' : 'var(--color-status-cancelled)',
                boxShadow: connected ? '0 0 6px var(--color-status-on-time)' : 'none',
              }}
            />
            <span style={{ color: connected ? 'var(--color-status-on-time)' : 'var(--color-status-cancelled)' }}>
              {connected ? 'LIVE' : 'OFFLINE'}
            </span>
          </div>
          <div style={{ color: 'var(--color-traefik-teal-bright)', fontSize: '1.1rem' }}>
            <FlapClock />
          </div>
          <div style={{ color: 'rgba(36,161,193,0.5)' }}>
            {new Date().toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}
          </div>
        </div>
      </header>

      {/* Board */}
      <main className="flex-1 p-6">
        {loading ? (
          <div className="flex items-center justify-center h-64">
            <div className="text-sm animate-pulse" style={{ color: 'var(--color-traefik-teal)' }}>
              Loading board…
            </div>
          </div>
        ) : (
          <BoardSection title="All Flights" flights={sortedFlights} />
        )}
      </main>

      {/* Footer */}
      <footer
        className="px-6 py-3 text-xs flex items-center justify-between border-t"
        style={{ background: 'var(--color-traefik-navy-dark)', borderColor: 'rgba(36,161,193,0.2)', color: 'rgba(36,161,193,0.4)' }}
      >
        <span>FLIGHTS: {sortedFlights.length}</span>
        <span>TRAEFIK AIRLINES INFORMATION SYSTEM</span>
        <span>{new Date().toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}</span>
      </footer>
    </div>
  )
}
