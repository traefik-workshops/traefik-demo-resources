import { Routes, Route, Navigate } from 'react-router-dom'
import FlightOpsPage from './pages/flight-ops/FlightOpsPage'
import AirportOpsPage from './pages/airport-ops/AirportOpsPage'
import PassengerSvcPage from './pages/passenger-svc/PassengerSvcPage'
import FlightBoardPage from './pages/flight-board/FlightBoardPage'

export default function App() {
  return (
    <Routes>
      <Route path="/flight-ops"    element={<FlightOpsPage />} />
      <Route path="/airport-ops"   element={<AirportOpsPage />} />
      <Route path="/passenger-svc" element={<PassengerSvcPage />} />
      <Route path="/flight-board"  element={<FlightBoardPage />} />
      <Route path="*"              element={<Navigate to={window.__DASHBOARD_ROUTE__} replace />} />
    </Routes>
  )
}
