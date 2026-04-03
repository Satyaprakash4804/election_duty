import { Navigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { Spinner } from './ui'

const ROLE_ROUTES = {
  MASTER:      '/master',
  SUPER_ADMIN: '/super',
  ADMIN:       '/admin',
  STAFF:       '/staff',
}

export function ProtectedRoute({ children, allowedRoles }) {
  const { user, loading } = useAuth()

  if (loading) return <div className="min-h-screen flex items-center justify-center"><Spinner /></div>
  if (!user) return <Navigate to="/login" replace />

  const role = user.role?.toUpperCase()
  if (allowedRoles && !allowedRoles.includes(role)) {
    const redirect = ROLE_ROUTES[role] || '/login'
    return <Navigate to={redirect} replace />
  }

  return children
}

export function PublicRoute({ children }) {
  const { user, loading } = useAuth()
  if (loading) return <div className="min-h-screen flex items-center justify-center"><Spinner /></div>
  if (user) {
    const role = user.role?.toUpperCase()
    const redirect = ROLE_ROUTES[role] || '/login'
    return <Navigate to={redirect} replace />
  }
  return children
}
