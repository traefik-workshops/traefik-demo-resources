interface Props {
  label: string
  value: number | string
  color?: string
  icon?: string
}

export default function StatCard({ label, value, color = '#e2e8f0', icon }: Props) {
  return (
    <div
      className="rounded-lg p-4 flex flex-col gap-1 border"
      style={{
        background: 'var(--color-bg-glass)',
        borderColor: 'var(--color-border-glass)',
        backdropFilter: 'blur(8px)',
      }}
    >
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-widest" style={{ color: 'var(--color-text-muted)' }}>
          {label}
        </span>
        {icon && <span className="text-base">{icon}</span>}
      </div>
      <span className="text-2xl font-semibold tabular-nums" style={{ color }}>
        {value}
      </span>
    </div>
  )
}
