import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { Checkin, BoardingPass } from '../types'

const BASE = '/api/checkin'

async function fetchCheckins(): Promise<Checkin[]> {
  const res = await fetch(`${BASE}/checkin`)
  if (!res.ok) throw new Error('Failed to fetch checkins')
  return res.json()
}

async function submitCheckin(data: Partial<Checkin>): Promise<Checkin> {
  const res = await fetch(`${BASE}/checkin`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error('Failed to submit checkin')
  return res.json()
}

async function fetchBoardingPass(bookingId: string): Promise<BoardingPass> {
  const res = await fetch(`${BASE}/board/${bookingId}`)
  if (!res.ok) throw new Error('Failed to fetch boarding pass')
  return res.json()
}

export function useCheckins(refetchInterval?: number) {
  return useQuery({
    queryKey: ['checkins'],
    queryFn: fetchCheckins,
    refetchInterval,
  })
}

export function useSubmitCheckin() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: submitCheckin,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['checkins'] }),
  })
}

export function useBoardingPass(bookingId: string | null) {
  return useQuery({
    queryKey: ['boarding-pass', bookingId],
    queryFn: () => fetchBoardingPass(bookingId!),
    enabled: !!bookingId,
  })
}
