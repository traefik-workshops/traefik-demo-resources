import { useState, useMemo } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import DashboardHeader from '../../components/layout/DashboardHeader'
import StatCard from '../../components/ui/StatCard'
import StatusBadge from '../../components/ui/StatusBadge'
import SearchInput from '../../components/ui/SearchInput'
import TabBar from '../../components/ui/TabBar'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import FormField from '../../components/ui/FormField'
import SkeletonRow from '../../components/ui/SkeletonRow'
import Toast from '../../components/ui/Toast'
import AiChatPanel from '../../components/chat/AiChatPanel'
import { useBookings, useCreateBooking, useCancelBooking } from '../../hooks/useBookings'
import { usePassengers } from '../../hooks/usePassengers'
import { useNotifications, useSendNotification } from '../../hooks/useNotifications'
import { useToast } from '../../hooks/useToast'

const TABS = [
  { id: 'bookings',       label: 'Bookings' },
  { id: 'passengers',     label: 'Passengers' },
  { id: 'notifications',  label: 'Notifications' },
]

export default function PassengerSvcPage() {
  const [activeTab, setActiveTab] = useState('bookings')
  const [bookingSearch, setBookingSearch] = useState('')
  const [passengerSearch, setPassengerSearch] = useState('')
  const [expandedPax, setExpandedPax] = useState<string | null>(null)
  const [showBookingModal, setShowBookingModal] = useState(false)
  const [showNotifModal, setShowNotifModal] = useState(false)
  const [bookingForm, setBookingForm] = useState({ passenger_id: '', flight_id: '', cabin_class: '' })
  const [notifForm, setNotifForm] = useState({ passenger_id: '', type: '', title: '', message: '', channel: '' })

  const { data: bookings = [], isLoading: bookingsLoading } = useBookings(60_000)
  const { data: passengers = [], isLoading: passengersLoading } = usePassengers(60_000)
  const { data: notifications = [], isLoading: notifsLoading } = useNotifications(30_000)
  const createBooking = useCreateBooking()
  const cancelBooking = useCancelBooking()
  const sendNotification = useSendNotification()
  const { toasts, addToast, removeToast } = useToast()

  const unread = useMemo(() => notifications.filter((n) => !n.read).length, [notifications])

  const stats = useMemo(() => ({
    total:     bookings.length,
    confirmed: bookings.filter((b) => b.status === 'confirmed').length,
    pending:   bookings.filter((b) => b.status === 'pending').length,
    cancelled: bookings.filter((b) => b.status === 'cancelled').length,
  }), [bookings])

  const filteredBookings = useMemo(() => {
    if (!bookingSearch) return bookings
    const q = bookingSearch.toLowerCase()
    return bookings.filter((b) =>
      b.booking_id?.toLowerCase().includes(q) ||
      b.passenger_id?.toLowerCase().includes(q) ||
      b.flight_id?.toLowerCase().includes(q),
    )
  }, [bookings, bookingSearch])

  const filteredPassengers = useMemo(() => {
    if (!passengerSearch) return passengers
    const q = passengerSearch.toLowerCase()
    return passengers.filter((p) =>
      p.name?.toLowerCase().includes(q) || p.passenger_id?.toLowerCase().includes(q),
    )
  }, [passengers, passengerSearch])

  async function handleCreateBooking() {
    try {
      await createBooking.mutateAsync(bookingForm as any)
      addToast('Booking created', 'success')
      setShowBookingModal(false)
      setBookingForm({ passenger_id: '', flight_id: '', cabin_class: '' })
    } catch { addToast('Booking failed', 'error') }
  }

  async function handleCancelBooking(id: string) {
    try {
      await cancelBooking.mutateAsync(id)
      addToast('Booking cancelled', 'success')
    } catch { addToast('Cancel failed', 'error') }
  }

  async function handleSendNotif() {
    try {
      await sendNotification.mutateAsync(notifForm as any)
      addToast('Notification sent', 'success')
      setShowNotifModal(false)
      setNotifForm({ passenger_id: '', type: '', title: '', message: '', channel: '' })
    } catch { addToast('Send failed', 'error') }
  }

  const tabs = TABS.map((t) => t.id === 'notifications' && unread > 0 ? { ...t, count: unread } : t)

  return (
    <div className="min-h-screen flex flex-col" style={{ background: 'var(--color-bg-primary)' }}>
      <DashboardHeader title="Passenger Services" subtitle="Traefik Airlines — Guest Relations" online={!bookingsLoading} />

      <main className="flex-1 p-6 flex flex-col gap-6">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatCard label="Total Bookings" value={stats.total}     color="var(--color-text-primary)" />
          <StatCard label="Confirmed"      value={stats.confirmed} color="var(--color-accent-green)" />
          <StatCard label="Pending"        value={stats.pending}   color="var(--color-accent-amber)" />
          <StatCard label="Cancelled"      value={stats.cancelled} color="var(--color-accent-red)" />
        </div>

        <div className="rounded-xl border overflow-hidden" style={{ borderColor: 'var(--color-border)', background: 'var(--color-bg-secondary)' }}>
          <div className="flex items-center justify-between px-4 pt-4">
            <TabBar tabs={tabs} active={activeTab} onChange={setActiveTab} />
            <div className="pb-2 flex gap-2">
              {activeTab === 'bookings'      && <SearchInput value={bookingSearch}  onChange={setBookingSearch}  placeholder="Search bookings…" />}
              {activeTab === 'passengers'    && <SearchInput value={passengerSearch} onChange={setPassengerSearch} placeholder="Search passengers…" />}
              {activeTab === 'bookings'      && <Button variant="primary" size="sm" onClick={() => setShowBookingModal(true)}>+ Booking</Button>}
              {activeTab === 'notifications' && <Button variant="primary" size="sm" onClick={() => setShowNotifModal(true)}>+ Notification</Button>}
            </div>
          </div>

          <AnimatePresence mode="wait">
            <motion.div key={activeTab} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.15 }}>
              {activeTab === 'bookings' && (
                <table className="w-full text-xs">
                  <thead><tr style={{ borderBottom: '1px solid var(--color-border)' }}>
                    {['Booking ID','Passenger','Flight','Class','Status',''].map((h) => (
                      <th key={h} className="px-4 py-3 text-left font-medium uppercase tracking-wider" style={{ color: 'var(--color-text-muted)' }}>{h}</th>
                    ))}
                  </tr></thead>
                  <tbody>
                    {bookingsLoading ? <SkeletonRow cols={6} /> : filteredBookings.map((b) => (
                      <tr key={b.booking_id} style={{ borderBottom: '1px solid var(--color-border)' }}>
                        <td className="px-4 py-3 font-medium" style={{ color: 'var(--color-accent-amber)' }}>{b.booking_id}</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{b.passenger_id}</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{b.flight_id}</td>
                        <td className="px-4 py-3" style={{ color: 'var(--color-text-secondary)' }}>{b.cabin_class}</td>
                        <td className="px-4 py-3"><StatusBadge status={b.status} /></td>
                        <td className="px-4 py-3">
                          <button onClick={() => handleCancelBooking(b.booking_id)} style={{ color: 'var(--color-accent-red)', background: 'none', border: 'none', cursor: 'pointer', fontSize: '0.75rem' }}>Cancel</button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}

              {activeTab === 'passengers' && (
                <div className="divide-y" style={{ borderColor: 'var(--color-border)' }}>
                  {passengersLoading ? (
                    <table className="w-full"><tbody><SkeletonRow cols={3} /></tbody></table>
                  ) : filteredPassengers.map((p) => (
                    <div key={p.passenger_id}>
                      <button
                        onClick={() => setExpandedPax(expandedPax === p.passenger_id ? null : p.passenger_id)}
                        className="w-full flex items-center justify-between px-4 py-3 text-xs hover:opacity-80 transition-opacity"
                        style={{ background: 'transparent', border: 'none', cursor: 'pointer' }}
                      >
                        <div className="flex items-center gap-3">
                          <div className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold" style={{ background: 'var(--color-accent-amber)', color: '#0f172a' }}>
                            {p.name?.[0] ?? '?'}
                          </div>
                          <span style={{ color: 'var(--color-text-primary)' }}>{p.name}</span>
                          <span style={{ color: 'var(--color-text-muted)' }}>{p.passenger_id}</span>
                        </div>
                        <span style={{ color: 'var(--color-text-muted)' }}>{expandedPax === p.passenger_id ? '▲' : '▼'}</span>
                      </button>
                      <AnimatePresence>
                        {expandedPax === p.passenger_id && (
                          <motion.div initial={{ height: 0 }} animate={{ height: 'auto' }} exit={{ height: 0 }} className="overflow-hidden">
                            <div className="px-6 pb-4 grid grid-cols-2 gap-3 text-xs" style={{ color: 'var(--color-text-secondary)' }}>
                              <div><span style={{ color: 'var(--color-text-muted)' }}>Email: </span>{p.email}</div>
                              {p.phone && <div><span style={{ color: 'var(--color-text-muted)' }}>Phone: </span>{p.phone}</div>}
                              {p.loyalty_tier && <div><span style={{ color: 'var(--color-text-muted)' }}>Tier: </span><span style={{ color: 'var(--color-accent-amber)' }}>{p.loyalty_tier}</span></div>}
                            </div>
                          </motion.div>
                        )}
                      </AnimatePresence>
                    </div>
                  ))}
                </div>
              )}

              {activeTab === 'notifications' && (
                <div className="divide-y p-4 flex flex-col gap-3">
                  {notifsLoading ? (
                    <table className="w-full"><tbody><SkeletonRow cols={3} /></tbody></table>
                  ) : notifications.map((n) => (
                    <div key={n.notification_id} className="rounded-lg p-3" style={{ background: n.read ? 'transparent' : 'rgba(245,158,11,0.06)', border: '1px solid var(--color-border)' }}>
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-xs font-medium" style={{ color: 'var(--color-text-primary)' }}>{n.title}</span>
                        {!n.read && <span className="w-1.5 h-1.5 rounded-full" style={{ background: 'var(--color-accent-amber)' }} />}
                      </div>
                      <p className="text-xs" style={{ color: 'var(--color-text-secondary)' }}>{n.message}</p>
                      <div className="flex gap-3 mt-2 text-xs" style={{ color: 'var(--color-text-muted)' }}>
                        <span>{n.type}</span><span>{n.channel}</span><span>{n.passenger_id}</span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </motion.div>
          </AnimatePresence>
        </div>
      </main>

      <Modal open={showBookingModal} onClose={() => setShowBookingModal(false)} title="Create Booking">
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-4">
            <FormField label="Passenger ID" value={bookingForm.passenger_id} onChange={(e) => setBookingForm({ ...bookingForm, passenger_id: e.target.value })} />
            <FormField label="Flight ID"    value={bookingForm.flight_id}    onChange={(e) => setBookingForm({ ...bookingForm, flight_id: e.target.value })} />
            <FormField as="select" label="Cabin Class" value={bookingForm.cabin_class} onChange={(e) => setBookingForm({ ...bookingForm, cabin_class: e.target.value })}>
              <option value="">Select class</option>
              {['economy','business','first'].map((c) => <option key={c}>{c}</option>)}
            </FormField>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={() => setShowBookingModal(false)}>Cancel</Button>
            <Button variant="primary" onClick={handleCreateBooking} disabled={createBooking.isPending}>Create</Button>
          </div>
        </div>
      </Modal>

      <Modal open={showNotifModal} onClose={() => setShowNotifModal(false)} title="Send Notification">
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-4">
            <FormField label="Passenger ID" value={notifForm.passenger_id} onChange={(e) => setNotifForm({ ...notifForm, passenger_id: e.target.value })} />
            <FormField label="Type"         value={notifForm.type}         onChange={(e) => setNotifForm({ ...notifForm, type: e.target.value })} placeholder="gate-change, delay…" />
            <FormField label="Title"        value={notifForm.title}        onChange={(e) => setNotifForm({ ...notifForm, title: e.target.value })} className="col-span-2" />
            <FormField label="Message"      value={notifForm.message}      onChange={(e) => setNotifForm({ ...notifForm, message: e.target.value })} className="col-span-2" />
            <FormField as="select" label="Channel" value={notifForm.channel} onChange={(e) => setNotifForm({ ...notifForm, channel: e.target.value })}>
              <option value="">Select channel</option>
              {['push','sms','email'].map((c) => <option key={c}>{c}</option>)}
            </FormField>
          </div>
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={() => setShowNotifModal(false)}>Cancel</Button>
            <Button variant="primary" onClick={handleSendNotif} disabled={sendNotification.isPending}>Send</Button>
          </div>
        </div>
      </Modal>

      <Toast toasts={toasts} onRemove={removeToast} />
      <AiChatPanel />
    </div>
  )
}
