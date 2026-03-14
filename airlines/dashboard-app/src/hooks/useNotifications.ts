import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { Notification } from '../types'

const BASE = '/api/notifications'

async function fetchNotifications(): Promise<Notification[]> {
  const res = await fetch(`${BASE}/notifications`)
  if (!res.ok) throw new Error('Failed to fetch notifications')
  return res.json()
}

async function sendNotification(data: Partial<Notification>): Promise<Notification> {
  const res = await fetch(`${BASE}/notifications`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error('Failed to send notification')
  return res.json()
}

export function useNotifications(refetchInterval?: number) {
  return useQuery({
    queryKey: ['notifications'],
    queryFn: fetchNotifications,
    refetchInterval,
  })
}

export function useSendNotification() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: sendNotification,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['notifications'] }),
  })
}
