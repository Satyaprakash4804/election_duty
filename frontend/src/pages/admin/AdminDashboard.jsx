import { Routes, Route, Navigate } from 'react-router-dom'
import { LayoutDashboard, Users, MapPin, ClipboardList, Building2 } from 'lucide-react'
import { Sidebar } from '../../components/Sidebar'
import AdminOverview from './AdminOverview'
import AdminStructure from './AdminStructure'
import AdminStaff from './AdminStaff'
import AdminDuties from './AdminDuties'
import AdminCenters from './AdminCenters'
import AdminHierarchy from './AdminHierarchy'

const navItems = [
  { to: '/admin',           icon: LayoutDashboard, label: 'डैशबोर्ड'   },
  { to: '/admin/structure', icon: Building2,        label: 'संरचना'     },
  { to: '/admin/centers',   icon: MapPin,           label: 'सभी केंद्र' },
  { to: '/admin/staff',     icon: Users,            label: 'कर्मचारी'   },
  { to: '/admin/duties',    icon: ClipboardList,    label: 'कर्तव्य'    },
  { to: '/admin/hierarchy', icon: Building2,        label: 'पदानुक्रम'  },
]

export default function AdminDashboard() {
  return (
    <div className="flex min-h-screen bg-[#f5f0e8]">
      <Sidebar navItems={navItems} />
      <main className="flex-1 lg:ml-64 p-6 pt-16 lg:pt-6">
        <Routes>
          <Route path="hierarchy" element={<AdminHierarchy />} />
          <Route index element={<AdminOverview />} />
          <Route path="structure" element={<AdminStructure />} />
          <Route path="centers"   element={<AdminCenters />} />
          <Route path="staff"     element={<AdminStaff />} />
          <Route path="duties"    element={<AdminDuties />} />
          <Route path="*" element={<Navigate to="/admin" replace />} />
        </Routes>
      </main>
    </div>
  )
}