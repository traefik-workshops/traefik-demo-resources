import type { McpServer } from '../../types'
import { config } from '../../lib/config'

interface Props {
  enabled: Set<string>
  onChange: (enabled: Set<string>) => void
}

export default function McpServerToggles({ enabled, onChange }: Props) {
  const servers: McpServer[] = config.mcpServers

  if (servers.length === 0) return null

  function toggle(id: string) {
    const next = new Set(enabled)
    next.has(id) ? next.delete(id) : next.add(id)
    onChange(next)
  }

  return (
    <div className="flex flex-col gap-2">
      <span className="text-xs uppercase tracking-wider" style={{ color: 'var(--color-text-muted)' }}>
        MCP Servers
      </span>
      <div className="flex flex-col gap-1">
        {servers.map((srv) => {
          const active = enabled.has(srv.id)
          return (
            <label
              key={srv.id}
              className="flex items-center gap-2 cursor-pointer select-none text-xs py-1 px-2 rounded transition-colors"
              style={{
                background: active ? 'rgba(245, 158, 11, 0.08)' : 'transparent',
                color: active ? 'var(--color-accent-amber)' : 'var(--color-text-secondary)',
              }}
            >
              <input
                type="checkbox"
                checked={active}
                onChange={() => toggle(srv.id)}
                className="accent-amber-400"
              />
              {srv.label}
              {active && (
                <span
                  className="ml-auto w-1.5 h-1.5 rounded-full animate-pulse"
                  style={{ background: 'var(--color-accent-amber)' }}
                />
              )}
            </label>
          )
        })}
      </div>
    </div>
  )
}
