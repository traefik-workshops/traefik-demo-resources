import { useState, useEffect, useCallback } from 'react'
import type { Flight } from '../types'

interface BoardState {
  flights: Flight[]
  connected: boolean
  loading: boolean
}

export function useFlightBoard(): BoardState {
  const [flights, setFlights] = useState<Flight[]>([])
  const [connected, setConnected] = useState(false)
  const [loading, setLoading] = useState(true)

  const fetchInitial = useCallback(async () => {
    try {
      const res = await fetch('/api/flights/flights')
      if (res.ok) setFlights(await res.json())
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchInitial()

    const es = new EventSource('/api/board/events')

    es.onopen = () => setConnected(true)
    es.onerror = () => setConnected(false)

    es.addEventListener('init', (e) => {
      setFlights(JSON.parse((e as MessageEvent).data))
      setLoading(false)
    })

    es.addEventListener('add', (e) => {
      const flight: Flight = JSON.parse((e as MessageEvent).data)
      setFlights((prev) => {
        if (prev.find((f) => f.flight_id === flight.flight_id)) return prev
        return [...prev, flight]
      })
    })

    es.addEventListener('modify', (e) => {
      const updated: Flight = JSON.parse((e as MessageEvent).data)
      setFlights((prev) => prev.map((f) => (f.flight_id === updated.flight_id ? updated : f)))
    })

    es.addEventListener('delete', (e) => {
      const { flight_id } = JSON.parse((e as MessageEvent).data)
      setFlights((prev) => prev.filter((f) => f.flight_id !== flight_id))
    })

    es.addEventListener('reset', () => {
      fetchInitial()
    })

    return () => es.close()
  }, [fetchInitial])

  return { flights, connected, loading }
}
