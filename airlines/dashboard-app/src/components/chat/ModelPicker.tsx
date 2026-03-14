import { useEffect, useState } from 'react'
import type { AiModel } from '../../types'
import { config } from '../../lib/config'

interface Props {
  value: string
  onChange: (modelId: string) => void
}

export default function ModelPicker({ value, onChange }: Props) {
  const [models, setModels] = useState<AiModel[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch(`${config.aiGatewayUrl}/models`, {
      headers: config.aiGatewayToken
        ? { Authorization: `Bearer ${config.aiGatewayToken}` }
        : {},
    })
      .then((r) => r.json())
      .then((data) => {
        const list: AiModel[] = data.data ?? data
        setModels(list)
        if (!value && list.length > 0) onChange(list[0].id)
      })
      .catch(() => setModels([]))
      .finally(() => setLoading(false))
  }, [])

  return (
    <div className="flex flex-col gap-1">
      <label className="text-xs uppercase tracking-wider" style={{ color: 'var(--color-text-muted)' }}>
        Model
      </label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={loading}
        className="px-2 py-1.5 rounded text-xs border outline-none w-full"
        style={{
          background: 'var(--color-bg-tertiary)',
          borderColor: 'var(--color-border)',
          color: loading ? 'var(--color-text-muted)' : 'var(--color-text-primary)',
        }}
      >
        {loading && <option>Loading models…</option>}
        {models.map((m) => (
          <option key={m.id} value={m.id}>
            {m.name ?? m.id}
          </option>
        ))}
      </select>
    </div>
  )
}
