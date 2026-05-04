import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
import { ProtectedRoute, PublicRoute } from './components/common/ProtectedRoute';
import LoginPage from './pages/LoginPage';
import AdminDashboard from './pages/admin/index';
import SuperDashboard from './pages/super/index';
import MasterDashboard from './pages/master/index';
import StaffDashboard from './pages/staff/index';
import MapViewPage from './pages/Mapviewpage';
import HierarchyReportPage from './pages/Hierarchyreportpage';
import DutyHistoryPage from './pages/staff/HistoryPage';
import GoswaraPage from './pages/admin/GoswaraPage';
import ManakBoothPage from './pages/admin/Manakboothpage';
import ManakDistrictPage from './pages/admin/Manakdistrictpage';

export default function App() {
  return (
    <BrowserRouter>
      <Toaster
        position="top-right"
        toastOptions={{
          style: {
            background: '#4A3000',
            color: '#FDF6E3',
            border: '1px solid rgba(212,168,67,0.4)',
            fontSize: '13px',
          },
          success: { iconTheme: { primary: '#D4A843', secondary: '#4A3000' } },
          error: { iconTheme: { primary: '#C0392B', secondary: '#fff' } },
          duration: 3000,
        }}
      />
      <Routes>
        <Route path="/login" element={<PublicRoute><LoginPage /></PublicRoute>} />
        <Route path="/admin/*" element={<ProtectedRoute allowedRoles={['ADMIN']}><AdminDashboard /></ProtectedRoute>} />
        <Route path="/super/*" element={<ProtectedRoute allowedRoles={['SUPER_ADMIN']}><SuperDashboard /></ProtectedRoute>} />
        <Route path="/master/*" element={<ProtectedRoute allowedRoles={['MASTER']}><MasterDashboard /></ProtectedRoute>} />
        <Route path="/staff/*" element={<ProtectedRoute allowedRoles={['STAFF']}><StaffDashboard /></ProtectedRoute>} />
        <Route path="/map-view" element={<ProtectedRoute allowedRoles={['STAFF', 'MASTER', 'SUPER_ADMIN', 'ADMIN']}>  <MapViewPage /></ProtectedRoute>} />
        <Route path="/staff/history" element={<ProtectedRoute allowedRoles={['STAFF']}>  <DutyHistoryPage /></ProtectedRoute>} />
        <Route path="/goswara-page" element={<ProtectedRoute allowedRoles={['ADMIN', 'SUPER_ADMIN']}>  <GoswaraPage /></ProtectedRoute>} />
        <Route path="/manak-booth" element={<ProtectedRoute allowedRoles={['ADMIN']}>  <ManakBoothPage /></ProtectedRoute>} />
        <Route path="/manak-district" element={<ProtectedRoute allowedRoles={['ADMIN']}>  <ManakDistrictPage /></ProtectedRoute>} />
        <Route path="/heirarchy-report" element={<ProtectedRoute allowedRoles={['STAFF', 'MASTER', 'SUPER_ADMIN', 'ADMIN']}>  <HierarchyReportPage role="admin" onBack={() => navigate(-1)} /></ProtectedRoute>} />
        <Route path="/" element={<Navigate to="/login" replace />} />
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
