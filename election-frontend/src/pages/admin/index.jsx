import { useState } from 'react';
import AppShell from '../../components/layout/AppShell';
import AdminDashboardPage from './DashboardPage';
import StaffPage from './StaffPage';
import StructurePage from './StructurePage';
import BoothsPage from './BoothsPage';
import DutyCardPage from './DutiesPage';

const PAGES = {
  dashboard: AdminDashboardPage,
  staff: StaffPage,
  structure: StructurePage,
  duties: DutyCardPage,
  booths: BoothsPage,
};

export default function AdminDashboard() {
  const [page, setPage] = useState('dashboard');
  const Page = PAGES[page] || AdminDashboardPage;
  return (
    <AppShell activePage={page} onNavigate={setPage}>
      <Page />
    </AppShell>
  );
}
