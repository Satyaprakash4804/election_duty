import { Navigate } from 'react-router-dom';
import { useAuthStore } from '../../store/authStore';

const ROLE_ROUTES = {
  MASTER: '/master',
  SUPER_ADMIN: '/super',
  ADMIN: '/admin',
  STAFF: '/staff',
};

export function ProtectedRoute({ children, allowedRoles }) {
  const { isAuthenticated, role } = useAuthStore();

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  if (allowedRoles && !allowedRoles.includes(role)) {
    const redirect = ROLE_ROUTES[role] || '/login';
    return <Navigate to={redirect} replace />;
  }

  return children;
}

export function PublicRoute({ children }) {
  const { isAuthenticated, role } = useAuthStore();

  if (isAuthenticated && role) {
    const redirect = ROLE_ROUTES[role] || '/login';
    return <Navigate to={redirect} replace />;
  }

  return children;
}
