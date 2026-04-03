import { Routes, Route, Navigate } from 'react-router-dom'
import { LayoutDashboard, Users, FileBarChart2 } from 'lucide-react'
import { Sidebar } from '../../components/Sidebar'
import SuperOverview from './SuperOverview'
import SuperAdmins from './SuperAdmins'
import SuperFormData from './SuperFormData'

const navItems = [
  { to: '/super',           icon: LayoutDashboard, label: 'Dashboard' },
  { to: '/super/admins',    icon: Users,            label: 'Admins'    },
  { to: '/super/form-data', icon: FileBarChart2,    label: 'Form Data' },
]

export default function SuperDashboard() {
  return (
    <div className="flex min-h-screen bg-[#f5f0e8]">
      <Sidebar navItems={navItems} />
      <main className="flex-1 lg:ml-64 p-6 pt-16 lg:pt-6">
        <Routes>
          <Route index element={<SuperOverview />} />
          <Route path="admins"    element={<SuperAdmins />} />
          <Route path="form-data" element={<SuperFormData />} />
          <Route path="*" element={<Navigate to="/super" replace />} />
        </Routes>
      </main>
    </div>
  )
}