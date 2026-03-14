import { useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

export interface ToastItem {
  id: string
  message: string
  type: 'success' | 'error' | 'info'
}

interface Props {
  toasts: ToastItem[]
  onRemove: (id: string) => void
}

const TYPE_COLORS = {
  success: 'var(--color-accent-green)',
  error:   'var(--color-accent-red)',
  info:    'var(--color-accent-blue)',
}

function ToastEntry({ toast, onRemove }: { toast: ToastItem; onRemove: (id: string) => void }) {
  useEffect(() => {
    const t = setTimeout(() => onRemove(toast.id), 3500)
    return () => clearTimeout(t)
  }, [toast.id, onRemove])

  return (
    <motion.div
      layout
      initial={{ opacity: 0, x: 40 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: 40 }}
      className="flex items-center gap-3 px-4 py-3 rounded-lg border shadow-lg text-sm cursor-pointer"
      style={{
        background: 'var(--color-bg-secondary)',
        borderColor: TYPE_COLORS[toast.type],
        color: 'var(--color-text-primary)',
      }}
      onClick={() => onRemove(toast.id)}
    >
      <span style={{ color: TYPE_COLORS[toast.type] }}>
        {toast.type === 'success' ? '✓' : toast.type === 'error' ? '✕' : 'ℹ'}
      </span>
      {toast.message}
    </motion.div>
  )
}

export default function Toast({ toasts, onRemove }: Props) {
  return (
    <div className="fixed bottom-6 right-6 z-50 flex flex-col gap-2 max-w-sm">
      <AnimatePresence>
        {toasts.map((t) => (
          <ToastEntry key={t.id} toast={t} onRemove={onRemove} />
        ))}
      </AnimatePresence>
    </div>
  )
}
