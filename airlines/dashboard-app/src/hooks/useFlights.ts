import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { Flight } from '../types'

const BASE = '/api/flights'

async function fetchFlights(): Promise<Flight[]> {
  const res = await fetch(`${BASE}/flights`)
  if (!res.ok) throw new Error('Failed to fetch flights')
  return res.json()
}

async function createFlight(flight: Partial<Flight>): Promise<Flight> {
  const res = await fetch(`${BASE}/flights`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(flight),
  })
  if (!res.ok) throw new Error('Failed to create flight')
  return res.json()
}

async function deleteFlight(id: string): Promise<void> {
  const res = await fetch(`${BASE}/flights/${id}`, { method: 'DELETE' })
  if (!res.ok) throw new Error('Failed to delete flight')
}

export function useFlights(refetchInterval?: number) {
  return useQuery({
    queryKey: ['flights'],
    queryFn: fetchFlights,
    refetchInterval,
  })
}

export function useCreateFlight() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: createFlight,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['flights'] }),
  })
}

export function useDeleteFlight() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: deleteFlight,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['flights'] }),
  })
}
