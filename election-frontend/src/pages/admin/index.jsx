import { useState } from 'react';
import AppShell from '../../components/layout/AppShell';
import AdminDashboardPage from './DashboardPage';
import StaffPage from './StaffPage';
import DutyCardPage from './DutiesPage';
import BoothPage from './BoothsPage';
import DynamicTablesPage from '../Dynamictablespage';
import FormPage from '../admin/StructurePage'

const PAGES = {
  dashboard: AdminDashboardPage,
  staff: StaffPage,
  structure: FormPage,
  duties: DutyCardPage,
  booths: BoothPage,
  manual_page: DynamicTablesPage,
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
