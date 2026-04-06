import { Routes, Route, Navigate } from 'react-router-dom'
import { LayoutDashboard, Users, Activity, Building2 } from 'lucide-react'
import { Sidebar } from '../../components/Sidebar'
import MasterOverview from './MasterOverview'
import MasterSuperAdmins from './MasterSuperAdmins'
import MasterLogs from './MasterLogs'
import AdminHierarchy from './MasterHierarchy'

const navItems = [
  { to: '/master',        icon: LayoutDashboard, label: 'Dashboard'    },
  { to: '/master/supers', icon: Users,            label: 'Super Admins' },
  { to: '/master/logs',   icon: Activity,         label: 'System Logs'  },
  { to:  '/master/hierarchy', icon: Building2,    label: 'Form Data'},
]

export default function MasterDashboard() {
  return (
    <div className="flex min-h-screen bg-khaki-bg">
      <Sidebar navItems={navItems} />
      <main className="flex-1 lg:ml-64 p-6 pt-16 lg:pt-6">
        <Routes>
          <Route index element={<MasterOverview />} />
          <Route path="supers" element={<MasterSuperAdmins />} />
          <Route path="hierarchy" element={<AdminHierarchy />} />
          <Route path="logs"   element={<MasterLogs />} />
          <Route path="*" element={<Navigate to="/master" replace />} />
        </Routes>
      </main>
    </div>
  )
}