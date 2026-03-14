import { type ReactNode, type ButtonHTMLAttributes } from 'react'

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'ghost' | 'danger'
  size?: 'sm' | 'md'
  children: ReactNode
}

const VARIANTS = {
  primary: {
    background: 'var(--color-accent-amber)',
    color: '#0f172a',
    border: 'transparent',
  },
  ghost: {
    background: 'transparent',
    color: 'var(--color-text-secondary)',
    border: 'var(--color-border)',
  },
  danger: {
    background: 'transparent',
    color: 'var(--color-accent-red)',
    border: 'var(--color-accent-red)',
  },
}

const SIZES = {
  sm: 'px-3 py-1.5 text-xs',
  md: 'px-4 py-2 text-xs',
}

export default function Button({ variant = 'ghost', size = 'md', children, style, ...props }: Props) {
  const v = VARIANTS[variant]
  return (
    <button
      className={`${SIZES[size]} rounded-lg font-medium uppercase tracking-wide border transition-opacity hover:opacity-80 disabled:opacity-40 disabled:cursor-not-allowed`}
      style={{ background: v.background, color: v.color, borderColor: v.border, ...style }}
      {...props}
    >
      {children}
    </button>
  )
}
