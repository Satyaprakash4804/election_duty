import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import { AuthProvider } from './context/AuthContext'
import { ProtectedRoute, PublicRoute } from './components/ProtectedRoute'

import LoginPage from './pages/LoginPage'
import AdminDashboard from './pages/admin/AdminDashboard'
import SuperDashboard from './pages/super/SuperDashboard'
import MasterDashboard from './pages/master/MasterDashboard'
import StaffDutyPage from './pages/StaffDutyPage'
import AdminHierarchy from './pages/admin/AdminHierarchy'

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Toaster
          position="top-right"
          toastOptions={{
            style: {
              background: '#FDF6E3',
              color: '#4A3000',
              border: '1px solid #D4A843',
              fontFamily: 'Inter, sans-serif',
              fontSize: '14px',
            },
            success: {
              iconTheme: { primary: '#8B6914', secondary: '#FDF6E3' },
            },
            error: {
              iconTheme: { primary: '#C0392B', secondary: '#FDF6E3' },
            },
          }}
        />

        <Routes>
          {/* Public */}
          <Route
            path="/login"
            element={
              <PublicRoute>
                <LoginPage />
              </PublicRoute>
            }
          />

        

          {/* Admin */}
          <Route
            path="/admin/*"
            element={
              <ProtectedRoute allowedRoles={['ADMIN']}>
                <AdminDashboard />
              </ProtectedRoute>
            }
          />

          {/* Super Admin */}
          <Route
            path="/super/*"
            element={
              <ProtectedRoute allowedRoles={['SUPER_ADMIN']}>
                <SuperDashboard />
              </ProtectedRoute>
            }
          />

          {/* Master */}
          <Route
            path="/master/*"
            element={
              <ProtectedRoute allowedRoles={['MASTER']}>
                <MasterDashboard />
              </ProtectedRoute>
            }
          />

          {/* Staff */}
          <Route
            path="/staff"
            element={
              <ProtectedRoute allowedRoles={['STAFF']}>
                <StaffDutyPage />
              </ProtectedRoute>
            }
          />

          {/* Default */}
          <Route path="/" element={<Navigate to="/login" replace />} />
          <Route path="*" element={<Navigate to="/login" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}
