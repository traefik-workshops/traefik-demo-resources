export function formatTime(ts: string): string {
  if (!ts) return '--:--'
  return new Date(ts).toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
}

export function formatDateTime(ts: string): string {
  if (!ts) return '--'
  return new Date(ts).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
}

export function formatClock(): string {
  return new Date().toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  })
}

export function formatDate(): string {
  return new Date().toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

export const STATUS_COLORS: Record<string, string> = {
  scheduled:  '#94a3b8',
  boarding:   '#06b6d4',
  departed:   '#78909c',
  'in-flight': '#42a5f5',
  landed:     '#00e676',
  delayed:    '#ffab00',
  cancelled:  '#ff5252',
  confirmed:  '#22c55e',
  pending:    '#f59e0b',
  active:     '#22c55e',
  closed:     '#78909c',
  open:       '#3b82f6',
}

export function statusColor(status: string): string {
  return STATUS_COLORS[status?.toLowerCase()] ?? '#94a3b8'
}

export function isUrgentStatus(status: string): boolean {
  return ['boarding', 'delayed', 'cancelled'].includes(status?.toLowerCase())
}

export function cn(...classes: (string | undefined | false | null)[]): string {
  return classes.filter(Boolean).join(' ')
}
