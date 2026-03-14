import { useState, useMemo } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import DashboardHeader from '../../components/layout/DashboardHeader'
import StatCard from '../../components/ui/StatCard'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import FormField from '../../components/ui/FormField'
import SkeletonRow from '../../components/ui/SkeletonRow'
import Toast from '../../components/ui/Toast'
import AiChatPanel from '../../components/chat/AiChatPanel'
import { useFlights, useCreateFlight, useDeleteFlight } from '../../hooks/useFlights'
import { useToast } from '../../hooks/useToast'
import { formatTime, isUrgentStatus } from '../../lib/utils'
import type { Flight } from '../../types'

const EMPTY_FLIGHT: Partial<Flight> = {
  flight_id: '', flight_number: '', origin: '', destination: '',
  departure_time: '', arrival_time: '', status: 'scheduled', gate: '', terminal: '',
}

export default function FlightOpsPage() {
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [showModal, setShowModal] = useState(false)
  const [form, setForm] = useState<Partial<Flight>>(EMPTY_FLIGHT)
  const [countdown, setCountdown] = useState(60)

  const { data: flights = [], isLoading, refetch } = useFlights(60_000)
  const createFlight = useCreateFlight()
  const deleteFlight = useDeleteFlight()
  const { toasts, addToast, removeToast } = useToast()

  useState(() => {
    const t = setInterval(() => setCountdown((c) => (c <= 1 ? 60 : c - 1)), 1000)
    return () => clearInterval(t)
  })

  const filtered = useMemo(() => {
    let list = flights
    if (search) list = list.filter((f) =>
      f.flight_number?.toLowerCase().includes(search.toLowerCase()) ||
      f.origin?.toLowerCase().includes(search.toLowerCase()) ||
      f.destination?.toLowerCase().includes(search.toLowerCase()),
    )
    if (statusFilter) list = list.filter((f) => f.status === statusFilter)
    return list
  }, [flights, search, statusFilter])

  const stats = useMemo(() => ({
    total:     flights.length,
    scheduled: flights.filter((f) => f.status === 'scheduled').length,
    inFlight:  flights.filter((f) => f.status === 'in-flight').length,
    delayed:   flights.filter((f) => f.status === 'delayed').length,
  }), [flights])

  async function handleCreate() {
    try {
      await createFlight.mutateAsync(form)
      addToast('Flight created', 'success')
      setShowModal(false)
      setForm(EMPTY_FLIGHT)
    } catch {
      addToast('Failed to create flight', 'error')
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteFlight.mutateAsync(id)
      addToast('Flight cancelled', 'success')
    } catch {
      addToast('Failed to cancel flight', 'error')
    }
  }

  function handleRefresh() { refetch(); setCountdown(60) }

  return (
    <div className="min-h-screen flex flex-col" style={{ background: 'var(--color-bg-primary)' }}>
      <DashboardHeader
        title="Flight Operations"
        subtitle="Traefik Airlines — Dispatch Center"
        online={!isLoading}
        countdown={countdown}
        onRefresh={handleRefresh}
      />

      <main className="flex-1 p-6 flex flex-col gap-6">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatCard label="Total Flights"  value={stats.total}     color="var(--color-text-primary)" />
          <StatCard label="Scheduled"      value={stats.scheduled} color="var(--color-accent-green)" />
          <StatCard label="In Flight"      value={stats.inFlight}  color="var(--color-accent-blue)" />
          <StatCard label="Delayed"        value={stats.delayed}   color="var(--color-accent-amber)" />
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <SearchInput value={search} onChange={setSearch} placeholder="Search flights…" />
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-2 rounded-lg text-sm border outline-none"
            style={{ background: 'var(--color-bg-tertiary)', borderColor: 'var(--color-border)', color: 'var(--color-text-primary)' }}
          >
            <option value="">All statuses</option>
            {['scheduled','boarding','in-flight','delayed','landed','cancelled'].map((s) => (
              <option key={s} value={s}>{s}</option>
            ))}
          </select>
          <Button variant="primary" onClick={() => setShowModal(true)}>+ Add Flight</Button>
        </div>

        <div className="rounded-xl border overflow-hidden" style={{ borderColor: 'var(--color-border)', background: 'var(--color-bg-secondary)' }}>
          <table className="w-full text-xs">
            <thead>
              <tr style={{ borderBottom: '1px solid var(--color-border)' }}>
                {['Flight','Origin','Destination','Departure','Arrival','Gate','Terminal','Status',''].map((h) => (
                  <th key={h} className="px-4 py-3 text-left font-medium uppercase tracking-wider" style={{ color: 'var(--color-text-muted)' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {isLoading ? (
                <SkeletonRow cols={9} />
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={9} className="px-4 py-10 text-center" style={{ color: 'var(--color-text-muted)' }}>No flights found</td>
                </tr>
              ) : (
                <AnimatePresence>
                  {filtered.map((f) => (
                    <motion.tr
                      key={f.flight_id}
                      initial={{ opacity: 0, y: 6 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0 }}
                      style={{
                        borderBottom: '1px solid var(--color-border)',
                        background: isUrgentStatus(f.status) ? 'rgba(245,158,11,0.04)' : 'transparent',
                      }}
                    >
                      <td className="px-4 py-3 font-medium" style={{ color: 'var(--color-accent-amber)' }}>{f.flight_number}</td>
                      <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{f.origin}</td>
                      <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{f.destination}</td>
                      <td className="px-4 py-3 tabular-nums" style={{ color: 'var(--color-text-primary)' }}>{formatTime(f.departure_time)}</td>
                      <td className="px-4 py-3 tabular-nums" style={{ color: 'var(--color-text-primary)' }}>{formatTime(f.arrival_time)}</td>
                      <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{f.gate ?? '—'}</td>
                      <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{f.terminal ?? '—'}</td>
                      <td className="px-4 py-3"><StatusBadge status={f.status} pulse={isUrgentStatus(f.status)} /></td>
                      <td className="px-4 py-3">
                        <button onClick={() => handleDelete(f.flight_id)} style={{ color: 'var(--color-accent-red)', background: 'none', border: 'none', cursor: 'pointer', fontSize: '0.75rem' }}>
                          Cancel
                        </button>
                      </td>
                    </motion.tr>
                  ))}
                </AnimatePresence>
              )}
            </tbody>
          </table>
        </div>
      </main>

      <Modal open={showModal} onClose={() => setShowModal(false)} title="Add New Flight">
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-4">
            <FormField label="Flight Number" value={form.flight_number ?? ''} onChange={(e) => setForm({ ...form, flight_number: e.target.value, flight_id: e.target.value })} />
            <FormField as="select" label="Status" value={form.status ?? 'scheduled'} onChange={(e) => setForm({ ...form, status: e.target.value })}>
              {['scheduled','boarding','delayed','cancelled'].map((s) => <option key={s}>{s}</option>)}
            </FormField>
            <FormField label="Origin" value={form.origin ?? ''} onChange={(e) => setForm({ ...form, origin: e.target.value })} placeholder="IATA code" />
            <FormField label="Destination" value={form.destination ?? ''} onChange={(e) => setForm({ ...form, destination: e.target.value })} placeholder="IATA code" />
            <FormField label="Departure" type="datetime-local" value={form.departure_time ?? ''} onChange={(e) => setForm({ ...form, departure_time: e.target.value })} />
            <FormField label="Arrival" type="datetime-local" value={form.arrival_time ?? ''} onChange={(e) => setForm({ ...form, arrival_time: e.target.value })} />
            <FormField label="Gate" value={form.gate ?? ''} onChange={(e) => setForm({ ...form, gate: e.target.value })} />
            <FormField label="Terminal" value={form.terminal ?? ''} onChange={(e) => setForm({ ...form, terminal: e.target.value })} />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={() => setShowModal(false)}>Cancel</Button>
            <Button variant="primary" onClick={handleCreate} disabled={createFlight.isPending}>
              {createFlight.isPending ? 'Creating…' : 'Create Flight'}
            </Button>
          </div>
        </div>
      </Modal>

      <Toast toasts={toasts} onRemove={removeToast} />
      <AiChatPanel />
    </div>
  )
}
