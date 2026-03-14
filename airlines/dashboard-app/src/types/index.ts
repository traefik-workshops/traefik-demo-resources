// ── Flights ────────────────────────────────────────────────────────────────
export interface Flight {
  flight_id: string
  flight_number: string
  origin: string
  destination: string
  departure_time: string
  arrival_time: string
  status: string
  gate?: string
  terminal?: string
  aircraft?: string
}

// ── Crew ───────────────────────────────────────────────────────────────────
export interface CrewMember {
  crew_id: string
  employee_id: string
  role: string
  flight_id: string
}

// ── Pricing ────────────────────────────────────────────────────────────────
export interface FareRule {
  pricing_id: string
  flight_id: string
  base_price: number
  currency: string
  cabin: string
}

// ── Checkin ────────────────────────────────────────────────────────────────
export interface Checkin {
  checkin_id: string
  booking_id: string
  passenger_name: string
  flight_id: string
  seat: string
  status: string
}

export interface BoardingPass {
  booking_id: string
  passenger_name: string
  flight_id: string
  seat: string
  gate: string
  boarding_time: string
}

// ── Baggage ────────────────────────────────────────────────────────────────
export interface BaggageItem {
  baggage_id: string
  booking_id: string
  weight_kg: number
  bag_type: string
  status: string
  tracking_id: string
}

// ── Gates ──────────────────────────────────────────────────────────────────
export interface Gate {
  gate_id: string
  flight_id: string
  status: string
  passengers: number
}

// ── Bookings ───────────────────────────────────────────────────────────────
export interface Booking {
  booking_id: string
  passenger_id: string
  flight_id: string
  cabin_class: string
  status: string
}

// ── Passengers ─────────────────────────────────────────────────────────────
export interface Passenger {
  passenger_id: string
  name: string
  email: string
  phone?: string
  loyalty_tier?: string
}

// ── Notifications ──────────────────────────────────────────────────────────
export interface Notification {
  notification_id: string
  passenger_id: string
  type: string
  title: string
  message: string
  channel: string
  read: boolean
  created_at: string
}

// ── AI Gateway ─────────────────────────────────────────────────────────────
export interface AiModel {
  id: string
  name?: string
  object?: string
}

export interface McpServer {
  id: string
  label: string
  url: string
  tools: string[]
}

// ── App config (injected by Helm via window globals) ───────────────────────
declare global {
  interface Window {
    AI_GATEWAY_ENABLED: boolean
    AI_GATEWAY_URL: string
    AI_GATEWAY_TOKEN?: string
    MCP_SERVERS: McpServer[]
  }
}
