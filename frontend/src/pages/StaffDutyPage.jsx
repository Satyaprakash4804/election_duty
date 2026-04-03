import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { MapPin, Bus, User, Users, Phone, Building2, Map, LogOut, Vote } from 'lucide-react'
import { staffAPI } from '../services/api'
import { Spinner } from '../components/ui'
import { useAuth } from '../context/AuthContext'
import { useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'

function InfoRow({ icon: Icon, label, value }) {
  if (!value) return null
  return (
    <div className="flex items-start gap-3 py-3 border-b border-border last:border-0">
      <Icon size={16} className="text-primary flex-shrink-0 mt-0.5" />
      <div>
        <p className="text-xs text-subtle font-medium uppercase tracking-wider">{label}</p>
        <p className="text-dark font-semibold text-sm mt-0.5">{value}</p>
      </div>
    </div>
  )
}

export default function StaffDutyPage() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()
  const [duty, setDuty] = useState(null)
  const [loading, setLoading] = useState(true)
  const [noDuty, setNoDuty] = useState(false)

  useEffect(() => {
    staffAPI.myDuty()
      .then((data) => {
        if (!data) { setNoDuty(true); return }
        setDuty(data)
      })
      .catch(() => toast.error('Failed to load duty'))
      .finally(() => setLoading(false))
  }, [])

  const handleLogout = () => {
    logout()
    toast.success('Logged out')
    navigate('/login')
  }

  return (
    <div className="min-h-screen bg-bg">
      {/* Header */}
      <div className="bg-dark px-5 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Vote size={22} className="text-border" />
          <div>
            <p className="text-border font-bold text-sm">UP Election Cell</p>
            <p className="text-subtle text-xs">Polling Duty</p>
          </div>
        </div>
        <button
          onClick={handleLogout}
          className="text-subtle hover:text-border flex items-center gap-1 text-sm transition-colors"
        >
          <LogOut size={15} /> Logout
        </button>
      </div>

      <div className="max-w-lg mx-auto px-4 py-6">
        {/* Welcome */}
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          className="card p-5 mb-5"
        >
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
              <User size={22} className="text-primary" />
            </div>
            <div>
              <p className="text-subtle text-xs">Welcome,</p>
              <p className="text-dark font-bold text-lg">{user?.name}</p>
              <p className="text-subtle text-xs font-mono">{user?.pno}</p>
            </div>
          </div>
        </motion.div>

        {loading ? (
          <Spinner />
        ) : noDuty ? (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="card p-8 text-center"
          >
            <MapPin size={40} className="mx-auto mb-3 text-subtle opacity-40" />
            <p className="text-dark font-bold text-lg mb-1">No Duty Assigned Yet</p>
            <p className="text-subtle text-sm">Your duty assignment will appear here once set by your admin.</p>
          </motion.div>
        ) : (
          <>
            {/* Duty Card */}
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.1 }}
              className="card p-5 mb-4"
            >
              <div className="flex items-center gap-2 mb-4 pb-3 border-b border-border">
                <div className="w-2 h-2 rounded-full bg-green-500" />
                <h2 className="font-bold text-dark">Your Duty Assignment</h2>
              </div>

              <InfoRow icon={MapPin}    label="Polling Center"     value={duty.centerName} />
              <InfoRow icon={MapPin}    label="Address"            value={duty.centerAddress} />
              <InfoRow icon={Building2} label="Gram Panchayat"    value={duty.gpName} />
              <InfoRow icon={Map}       label="Sector"             value={duty.sectorName} />
              <InfoRow icon={Map}       label="Zone"               value={duty.zoneName} />
              <InfoRow icon={Map}       label="Zone HQ"            value={duty.zoneHq} />
              <InfoRow icon={Building2} label="Super Zone"         value={duty.superZoneName} />
              <InfoRow icon={Bus}       label="Bus No"             value={duty.busNo} />
              <InfoRow icon={User}      label="Assigned By"        value={duty.assignedBy} />

              {duty.latitude && duty.longitude && (
                <div className="mt-3 pt-3 border-t border-border">
                  <a
                    href={`https://www.google.com/maps?q=${duty.latitude},${duty.longitude}`}
                    target="_blank"
                    rel="noreferrer"
                    className="flex items-center justify-center gap-2 w-full py-2.5 rounded-xl bg-primary text-white text-sm font-bold hover:bg-accent transition-colors"
                  >
                    <MapPin size={15} /> Open in Google Maps
                  </a>
                </div>
              )}
            </motion.div>

            {/* Co-staff at same center */}
            {duty.allStaff?.length > 0 && (
              <motion.div
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.2 }}
                className="card p-5"
              >
                <h3 className="font-bold text-dark mb-3 flex items-center gap-2">
                  <Users size={16} className="text-primary" />
                  Staff at this Center ({duty.allStaff.length})
                </h3>
                <div className="space-y-2">
                  {duty.allStaff.map((s, i) => (
                    <div key={i} className="flex items-center justify-between py-2 border-b border-border last:border-0">
                      <div>
                        <p className="text-dark text-sm font-medium">{s.name}</p>
                        <p className="text-subtle text-xs">{s.pno} · {s.thana}</p>
                      </div>
                      {s.mobile && (
                        <a href={`tel:${s.mobile}`} className="text-primary hover:text-accent">
                          <Phone size={15} />
                        </a>
                      )}
                    </div>
                  ))}
                </div>
              </motion.div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
