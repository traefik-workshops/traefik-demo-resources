import { useQuery } from '@tanstack/react-query'
import type { Passenger } from '../types'

async function fetchPassengers(): Promise<Passenger[]> {
  const res = await fetch('/api/passengers/passengers')
  if (!res.ok) throw new Error('Failed to fetch passengers')
  return res.json()
}

export function usePassengers(refetchInterval?: number) {
  return useQuery({
    queryKey: ['passengers'],
    queryFn: fetchPassengers,
    refetchInterval,
  })
}
