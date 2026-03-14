import { statusColor } from '../../lib/utils'

interface Props {
  status: string
  pulse?: boolean
}

export default function StatusBadge({ status, pulse }: Props) {
  const color = statusColor(status)
  return (
    <span
      className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-xs font-medium uppercase tracking-wide"
      style={{ background: `${color}22`, color }}
    >
      {pulse && (
        <span
          className="w-1.5 h-1.5 rounded-full animate-pulse"
          style={{ background: color }}
        />
      )}
      {status}
    </span>
  )
}
