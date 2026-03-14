interface Tab {
  id: string
  label: string
  count?: number
}

interface Props {
  tabs: Tab[]
  active: string
  onChange: (id: string) => void
}

export default function TabBar({ tabs, active, onChange }: Props) {
  return (
    <div className="flex gap-1 border-b" style={{ borderColor: 'var(--color-border)' }}>
      {tabs.map((tab) => {
        const isActive = tab.id === active
        return (
          <button
            key={tab.id}
            onClick={() => onChange(tab.id)}
            className="px-4 py-2.5 text-xs uppercase tracking-wider font-medium transition-all border-b-2 -mb-px"
            style={{
              color: isActive ? 'var(--color-accent-amber)' : 'var(--color-text-muted)',
              borderBottomColor: isActive ? 'var(--color-accent-amber)' : 'transparent',
              background: 'transparent',
            }}
          >
            {tab.label}
            {tab.count !== undefined && (
              <span className="ml-1.5 text-xs opacity-60">({tab.count})</span>
            )}
          </button>
        )
      })}
    </div>
  )
}
