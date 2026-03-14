import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { Gate } from '../types'

const BASE = '/api/gates'

async function fetchGates(): Promise<Gate[]> {
  const res = await fetch(`${BASE}/gates`)
  if (!res.ok) throw new Error('Failed to fetch gates')
  return res.json()
}

async function updateGate(data: Partial<Gate>): Promise<Gate> {
  const res = await fetch(`${BASE}/gates`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error('Failed to update gate')
  return res.json()
}

export function useGates(refetchInterval?: number) {
  return useQuery({
    queryKey: ['gates'],
    queryFn: fetchGates,
    refetchInterval,
  })
}

export function useUpdateGate() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: updateGate,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['gates'] }),
  })
}
