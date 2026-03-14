import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { Booking } from '../types'

const BASE = '/api/bookings'

async function fetchBookings(): Promise<Booking[]> {
  const res = await fetch(`${BASE}/bookings`)
  if (!res.ok) throw new Error('Failed to fetch bookings')
  return res.json()
}

async function createBooking(data: Partial<Booking>): Promise<Booking> {
  const res = await fetch(`${BASE}/bookings`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error('Failed to create booking')
  return res.json()
}

async function cancelBooking(id: string): Promise<void> {
  const res = await fetch(`${BASE}/bookings/${id}`, { method: 'DELETE' })
  if (!res.ok) throw new Error('Failed to cancel booking')
}

export function useBookings(refetchInterval?: number) {
  return useQuery({
    queryKey: ['bookings'],
    queryFn: fetchBookings,
    refetchInterval,
  })
}

export function useCreateBooking() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: createBooking,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bookings'] }),
  })
}

export function useCancelBooking() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: cancelBooking,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bookings'] }),
  })
}
