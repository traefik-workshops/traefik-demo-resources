import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import type { BaggageItem } from '../types'

const BASE = '/api/baggage'

async function fetchBaggage(): Promise<BaggageItem[]> {
  const res = await fetch(`${BASE}/baggage`)
  if (!res.ok) throw new Error('Failed to fetch baggage')
  return res.json()
}

async function submitBaggage(data: Partial<BaggageItem>): Promise<BaggageItem> {
  const res = await fetch(`${BASE}/baggage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error('Failed to submit baggage')
  return res.json()
}

export function useBaggage(refetchInterval?: number) {
  return useQuery({
    queryKey: ['baggage'],
    queryFn: fetchBaggage,
    refetchInterval,
  })
}

export function useSubmitBaggage() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: submitBaggage,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['baggage'] }),
  })
}

/** Returns a function that opens an SSE stream for a baggage item and calls onUpdate with each event. */
export function trackBaggageSSE(
  trackingId: string,
  onUpdate: (data: unknown) => void,
  onError?: () => void,
): () => void {
  const es = new EventSource(`${BASE}/track/${trackingId}`)
  es.onmessage = (e) => onUpdate(JSON.parse(e.data))
  es.onerror = () => { onError?.(); es.close() }
  return () => es.close()
}
