interface Props {
  value: string
  onChange: (v: string) => void
  placeholder?: string
}

export default function SearchInput({ value, onChange, placeholder = 'Search…' }: Props) {
  return (
    <input
      type="text"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      className="px-3 py-2 rounded-lg text-sm border outline-none transition-colors"
      style={{
        background: 'var(--color-bg-tertiary)',
        borderColor: 'var(--color-border)',
        color: 'var(--color-text-primary)',
      }}
      onFocus={(e) => (e.target.style.borderColor = 'var(--color-accent-amber)')}
      onBlur={(e) => (e.target.style.borderColor = 'var(--color-border)')}
    />
  )
}
