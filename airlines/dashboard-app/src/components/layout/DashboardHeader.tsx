import { useEffect, useState } from 'react'
import { formatClock, formatDate } from '../../lib/utils'

interface Props {
  title: string
  subtitle: string
  online?: boolean
  countdown?: number
  onRefresh?: () => void
}

export default function DashboardHeader({ title, subtitle, online = true, countdown, onRefresh }: Props) {
  const [clock, setClock] = useState(formatClock())
  const [date, setDate] = useState(formatDate())

  useEffect(() => {
    const t = setInterval(() => {
      setClock(formatClock())
      setDate(formatDate())
    }, 1000)
    return () => clearInterval(t)
  }, [])

  return (
    <header
      className="flex items-center justify-between px-6 py-4 border-b"
      style={{
        background: 'linear-gradient(135deg, var(--color-bg-secondary) 0%, var(--color-bg-primary) 100%)',
        borderColor: 'var(--color-border)',
      }}
    >
      {/* Left — logo + title */}
      <div className="flex items-center gap-4">
        <div
          className="w-10 h-10 rounded-lg flex items-center justify-center text-sm font-bold"
          style={{ background: 'var(--color-accent-amber)', color: '#0f172a' }}
        >
          TK
        </div>
        <div>
          <div className="text-sm font-semibold tracking-wide" style={{ color: 'var(--color-text-primary)' }}>
            {title}
          </div>
          <div className="text-xs" style={{ color: 'var(--color-text-muted)' }}>
            {subtitle}
          </div>
        </div>
      </div>

      {/* Right — status + clock + countdown */}
      <div className="flex items-center gap-6 text-xs" style={{ color: 'var(--color-text-secondary)' }}>
        <div className="flex items-center gap-1.5">
          <span
            className="w-1.5 h-1.5 rounded-full"
            style={{ background: online ? 'var(--color-accent-green)' : 'var(--color-accent-red)' }}
          />
          {online ? 'ONLINE' : 'OFFLINE'}
        </div>

        {countdown !== undefined && onRefresh && (
          <button
            onClick={onRefresh}
            className="flex items-center gap-1 hover:opacity-80 transition-opacity"
            title="Refresh now"
          >
            ↻ {countdown}s
          </button>
        )}

        <div className="text-right">
          <div className="font-medium tabular-nums" style={{ color: 'var(--color-text-primary)' }}>
            {clock}
          </div>
          <div style={{ color: 'var(--color-text-muted)' }}>{date}</div>
        </div>
      </div>
    </header>
  )
}
