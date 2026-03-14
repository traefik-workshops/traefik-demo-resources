import { useState, useMemo } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import DashboardHeader from '../../components/layout/DashboardHeader'
import StatCard from '../../components/ui/StatCard'
import StatusBadge from '../../components/ui/StatusBadge'
import TabBar from '../../components/ui/TabBar'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import FormField from '../../components/ui/FormField'
import SkeletonRow from '../../components/ui/SkeletonRow'
import Toast from '../../components/ui/Toast'
import AiChatPanel from '../../components/chat/AiChatPanel'
import { useCheckins, useSubmitCheckin } from '../../hooks/useCheckins'
import { useBaggage, useSubmitBaggage } from '../../hooks/useBaggage'
import { useGates, useUpdateGate } from '../../hooks/useGates'
import { useToast } from '../../hooks/useToast'

const TABS = [
  { id: 'checkin', label: 'Check-ins' },
  { id: 'baggage', label: 'Baggage' },
  { id: 'gates',   label: 'Gates' },
]

export default function AirportOpsPage() {
  const [activeTab, setActiveTab] = useState('checkin')
  const [showCheckinModal, setShowCheckinModal] = useState(false)
  const [showBaggageModal, setShowBaggageModal] = useState(false)
  const [showGateModal, setShowGateModal] = useState(false)
  const [checkinForm, setCheckinForm] = useState({ booking_id: '', passenger_name: '', flight_id: '', seat_preference: '' })
  const [baggageForm, setBaggageForm] = useState({ booking_id: '', weight_kg: '', bag_type: '' })
  const [gateForm, setGateForm] = useState({ gate_id: '', flight_id: '', status: '' })

  const { data: checkins = [], isLoading: checkinsLoading } = useCheckins(30_000)
  const { data: baggage = [], isLoading: baggageLoading } = useBaggage(30_000)
  const { data: gates = [], isLoading: gatesLoading } = useGates(30_000)
  const submitCheckin = useSubmitCheckin()
  const submitBaggage = useSubmitBaggage()
  const updateGate = useUpdateGate()
  const { toasts, addToast, removeToast } = useToast()

  const stats = useMemo(() => ({
    totalCheckins: checkins.length,
    confirmed: checkins.filter((c) => c.status === 'confirmed').length,
    pending: checkins.filter((c) => c.status === 'pending').length,
    cancelled: checkins.filter((c) => c.status === 'cancelled').length,
    baggage: baggage.length,
    gates: gates.length,
  }), [checkins, baggage, gates])

  async function handleCheckin() {
    try {
      await submitCheckin.mutateAsync(checkinForm as any)
      addToast('Check-in submitted', 'success')
      setShowCheckinModal(false)
      setCheckinForm({ booking_id: '', passenger_name: '', flight_id: '', seat_preference: '' })
    } catch { addToast('Check-in failed', 'error') }
  }

  async function handleBaggage() {
    try {
      await submitBaggage.mutateAsync({ ...baggageForm, weight_kg: Number(baggageForm.weight_kg) } as any)
      addToast('Baggage submitted', 'success')
      setShowBaggageModal(false)
      setBaggageForm({ booking_id: '', weight_kg: '', bag_type: '' })
    } catch { addToast('Baggage submission failed', 'error') }
  }

  async function handleGate() {
    try {
      await updateGate.mutateAsync(gateForm as any)
      addToast('Gate updated', 'success')
      setShowGateModal(false)
      setGateForm({ gate_id: '', flight_id: '', status: '' })
    } catch { addToast('Gate update failed', 'error') }
  }

  const isLoading = checkinsLoading || baggageLoading || gatesLoading

  return (
    <div className="min-h-screen flex flex-col" style={{ background: 'var(--color-bg-primary)' }}>
      <DashboardHeader title="Airport Operations" subtitle="Traefik Airlines — Ground Control" online={!isLoading} />

      <main className="flex-1 p-6 flex flex-col gap-6">
        <div className="grid grid-cols-3 md:grid-cols-6 gap-4">
          <StatCard label="Check-ins"  value={stats.totalCheckins} color="var(--color-text-primary)" />
          <StatCard label="Confirmed"  value={stats.confirmed}     color="var(--color-accent-green)" />
          <StatCard label="Pending"    value={stats.pending}       color="var(--color-accent-amber)" />
          <StatCard label="Cancelled"  value={stats.cancelled}     color="var(--color-accent-red)" />
          <StatCard label="Baggage"    value={stats.baggage}       color="var(--color-accent-cyan)" />
          <StatCard label="Gates"      value={stats.gates}         color="var(--color-accent-blue)" />
        </div>

        <div className="rounded-xl border overflow-hidden" style={{ borderColor: 'var(--color-border)', background: 'var(--color-bg-secondary)' }}>
          <div className="flex items-center justify-between px-4 pt-4">
            <TabBar tabs={TABS} active={activeTab} onChange={setActiveTab} />
            <div className="pb-2">
              {activeTab === 'checkin' && <Button variant="primary" size="sm" onClick={() => setShowCheckinModal(true)}>+ Check-in</Button>}
              {activeTab === 'baggage' && <Button variant="primary" size="sm" onClick={() => setShowBaggageModal(true)}>+ Baggage</Button>}
              {activeTab === 'gates'   && <Button variant="primary" size="sm" onClick={() => setShowGateModal(true)}>+ Gate</Button>}
            </div>
          </div>

          <AnimatePresence mode="wait">
            <motion.div key={activeTab} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.15 }}>
              {activeTab === 'checkin' && (
                <table className="w-full text-xs">
                  <thead><tr style={{ borderBottom: '1px solid var(--color-border)' }}>
                    {['Booking ID','Passenger','Flight','Seat','Status'].map((h) => (
                      <th key={h} className="px-4 py-3 text-left font-medium uppercase tracking-wider" style={{ color: 'var(--color-text-muted)' }}>{h}</th>
                    ))}
                  </tr></thead>
                  <tbody>
                    {checkinsLoading ? <SkeletonRow cols={5} /> : checkins.map((c) => (
                      <tr key={c.checkin_id} style={{ borderBottom: '1px solid var(--color-border)' }}>
                        <td className="px-4 py-3 font-medium" style={{ color: 'var(--color-accent-amber)' }}>{c.booking_id}</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{c.passenger_name}</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{c.flight_id}</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{c.seat}</td>
                        <td className="px-4 py-3"><StatusBadge status={c.status} /></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}

              {activeTab === 'baggage' && (
                <table className="w-full text-xs">
                  <thead><tr style={{ borderBottom: '1px solid var(--color-border)' }}>
                    {['Booking ID','Weight','Type','Status','Tracking'].map((h) => (
                      <th key={h} className="px-4 py-3 text-left font-medium uppercase tracking-wider" style={{ color: 'var(--color-text-muted)' }}>{h}</th>
                    ))}
                  </tr></thead>
                  <tbody>
                    {baggageLoading ? <SkeletonRow cols={5} /> : baggage.map((b) => (
                      <tr key={b.baggage_id} style={{ borderBottom: '1px solid var(--color-border)' }}>
                        <td className="px-4 py-3 font-medium" style={{ color: 'var(--color-accent-amber)' }}>{b.booking_id}</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{b.weight_kg} kg</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{b.bag_type}</td>
                        <td className="px-4 py-3"><StatusBadge status={b.status} /></td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-muted)' }}>{b.tracking_id}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}

              {activeTab === 'gates' && (
                <table className="w-full text-xs">
                  <thead><tr style={{ borderBottom: '1px solid var(--color-border)' }}>
                    {['Gate','Flight','Status','Passengers'].map((h) => (
                      <th key={h} className="px-4 py-3 text-left font-medium uppercase tracking-wider" style={{ color: 'var(--color-text-muted)' }}>{h}</th>
                    ))}
                  </tr></thead>
                  <tbody>
                    {gatesLoading ? <SkeletonRow cols={4} /> : gates.map((g) => (
                      <tr key={g.gate_id} style={{ borderBottom: '1px solid var(--color-border)' }}>
                        <td className="px-4 py-3 font-medium" style={{ color: 'var(--color-accent-amber)' }}>{g.gate_id}</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{g.flight_id}</td>
                        <td className="px-4 py-3"><StatusBadge status={g.status} /></td>
                        <td className="px-4 py-3 tabular-nums" style={{ color: 'var(--color-text-secondary)' }}>{g.passengers}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </motion.div>
          </AnimatePresence>
        </div>
      </main>

      <Modal open={showCheckinModal} onClose={() => setShowCheckinModal(false)} title="New Check-in">
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-4">
            <FormField label="Booking ID"  value={checkinForm.booking_id}   onChange={(e) => setCheckinForm({ ...checkinForm, booking_id: e.target.value })} />
            <FormField label="Passenger"   value={checkinForm.passenger_name} onChange={(e) => setCheckinForm({ ...checkinForm, passenger_name: e.target.value })} />
            <FormField label="Flight ID"   value={checkinForm.flight_id}    onChange={(e) => setCheckinForm({ ...checkinForm, flight_id: e.target.value })} />
            <FormField label="Seat Pref"   value={checkinForm.seat_preference} onChange={(e) => setCheckinForm({ ...checkinForm, seat_preference: e.target.value })} placeholder="window/aisle" />
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={() => setShowCheckinModal(false)}>Cancel</Button>
            <Button variant="primary" onClick={handleCheckin} disabled={submitCheckin.isPending}>Submit</Button>
          </div>
        </div>
      </Modal>

      <Modal open={showBaggageModal} onClose={() => setShowBaggageModal(false)} title="Add Baggage">
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-4">
            <FormField label="Booking ID" value={baggageForm.booking_id} onChange={(e) => setBaggageForm({ ...baggageForm, booking_id: e.target.value })} />
            <FormField label="Weight (kg)" type="number" value={baggageForm.weight_kg} onChange={(e) => setBaggageForm({ ...baggageForm, weight_kg: e.target.value })} />
            <FormField as="select" label="Bag Type" value={baggageForm.bag_type} onChange={(e) => setBaggageForm({ ...baggageForm, bag_type: e.target.value })}>
              <option value="">Select type</option>
              {['carry-on','checked','oversized'].map((t) => <option key={t}>{t}</option>)}
            </FormField>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={() => setShowBaggageModal(false)}>Cancel</Button>
            <Button variant="primary" onClick={handleBaggage} disabled={submitBaggage.isPending}>Submit</Button>
          </div>
        </div>
      </Modal>

      <Modal open={showGateModal} onClose={() => setShowGateModal(false)} title="Update Gate">
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-4">
            <FormField label="Gate ID"   value={gateForm.gate_id}   onChange={(e) => setGateForm({ ...gateForm, gate_id: e.target.value })} />
            <FormField label="Flight ID" value={gateForm.flight_id} onChange={(e) => setGateForm({ ...gateForm, flight_id: e.target.value })} />
            <FormField as="select" label="Status" value={gateForm.status} onChange={(e) => setGateForm({ ...gateForm, status: e.target.value })}>
              <option value="">Select status</option>
              {['open','boarding','closed'].map((s) => <option key={s}>{s}</option>)}
            </FormField>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={() => setShowGateModal(false)}>Cancel</Button>
            <Button variant="primary" onClick={handleGate} disabled={updateGate.isPending}>Update</Button>
          </div>
        </div>
      </Modal>

      <Toast toasts={toasts} onRemove={removeToast} />
      <AiChatPanel />
    </div>
  )
}
