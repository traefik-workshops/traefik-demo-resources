import { type InputHTMLAttributes, type SelectHTMLAttributes, type ReactNode } from 'react'

interface BaseProps {
  label: string
}

interface InputProps extends BaseProps, InputHTMLAttributes<HTMLInputElement> {
  as?: 'input'
}

interface SelectProps extends BaseProps, SelectHTMLAttributes<HTMLSelectElement> {
  as: 'select'
  children: ReactNode
}

type Props = InputProps | SelectProps

const fieldStyle = {
  background: 'var(--color-bg-tertiary)',
  borderColor: 'var(--color-border)',
  color: 'var(--color-text-primary)',
}

export default function FormField(props: Props) {
  const { label, as = 'input', ...rest } = props
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-xs uppercase tracking-wider" style={{ color: 'var(--color-text-muted)' }}>
        {label}
      </span>
      {as === 'select' ? (
        <select
          className="px-3 py-2 rounded-lg text-sm border outline-none"
          style={fieldStyle}
          {...(rest as SelectHTMLAttributes<HTMLSelectElement>)}
        />
      ) : (
        <input
          className="px-3 py-2 rounded-lg text-sm border outline-none"
          style={fieldStyle}
          {...(rest as InputHTMLAttributes<HTMLInputElement>)}
        />
      )}
    </label>
  )
}
