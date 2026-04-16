import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  LayoutDashboard, Users, GitBranch, Vote, MapPin, LogOut,
  ChevronRight, Menu, X, Key, FileText, Group, Shield,
  Activity, Settings
} from 'lucide-react';
import { useAuthStore } from '../../store/authStore';
import toast from 'react-hot-toast';

const NAV_BY_ROLE = {
  ADMIN: [
    { label: 'Dashboard', icon: LayoutDashboard, path: 'dashboard' },
    { label: 'Staff',     icon: Users,           path: 'staff' },
    { label: 'Structure', icon: GitBranch,        path: 'structure' },
    { label: 'Duties',    icon: Vote,             path: 'duties' },
    { label: 'Booths',    icon: MapPin,           path: 'booths' },
  ],
  SUPER_ADMIN: [
    { label: 'Overview',  icon: LayoutDashboard, path: 'overview' },
    { label: 'Admins',    icon: Shield,          path: 'admins' },
    { label: 'Form Data', icon: FileText,        path: 'formdata' },
  ],
  MASTER: [
    { label: 'Overview',     icon: LayoutDashboard, path: 'overview' },
    { label: 'Super Admins', icon: Shield,          path: 'superadmins' },
    { label: 'Admins',       icon: Users,           path: 'admins' },
    { label: 'System Logs',  icon: Activity,        path: 'logs' },
  ],
  STAFF: [
    { label: 'Dashboard', icon: LayoutDashboard, path: 'dashboard' },
    { label: 'My Duty',   icon: MapPin,          path: 'duty' },
    { label: 'Co-Staff',  icon: Group,           path: 'costaff' },
    { label: 'Duty Card', icon: FileText,        path: 'dutycard' },
    { label: 'Password',  icon: Key,             path: 'password' },
  ],
};

export default function AppShell({ children, activePage, onNavigate }) {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const { user, role, logout } = useAuthStore();
  const navigate = useNavigate();
  const navItems = NAV_BY_ROLE[role] || [];

  const handleLogout = async () => {
    if (!window.confirm('Are you sure you want to logout?')) return;
    await logout();
    toast.success('Logged out successfully');
    navigate('/login');
  };

  const roleBadge = {
    MASTER: { label: 'Master', color: '#00695C', bg: '#e0f2f1' },
    SUPER_ADMIN: { label: 'Super Admin', color: '#1A5276', bg: '#e3f0fb' },
    ADMIN: { label: 'Admin', color: '#8B6914', bg: '#fdf0d5' },
    STAFF: { label: 'Staff', color: '#2D6A1E', bg: '#e6f4ea' },
  }[role] || { label: role, color: '#666', bg: '#eee' };

  // ── Sidebar (desktop) ──────────────────────────────────────────────────────
  const Sidebar = () => (
    <aside className="hidden lg:flex flex-col w-52 shrink-0 h-screen sticky top-0"
      style={{ background: 'var(--dark)' }}>
      {/* Logo */}
      <div className="px-4 py-4 border-b" style={{ borderColor: 'rgba(212,168,67,0.2)' }}>
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-full flex items-center justify-center font-bold text-sm"
            style={{ background: 'var(--primary)', color: 'var(--border)' }}>
            UP
          </div>
          <div>
            <p className="text-xs font-bold leading-tight" style={{ color: 'var(--border)' }}>
              Election Cell
            </p>
            <p className="text-[10px]" style={{ color: 'rgba(212,168,67,0.6)' }}>
              उ.प्र. निर्वाचन कक्ष
            </p>
          </div>
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 py-2 overflow-y-auto">
        {navItems.map((item) => {
          const active = activePage === item.path;
          return (
            <div key={item.path}
              className={`nav-item ${active ? 'active' : ''}`}
              onClick={() => onNavigate(item.path)}>
              <item.icon size={18} className="nav-icon shrink-0" />
              <span className="nav-label">{item.label}</span>
              {active && <ChevronRight size={14} className="ml-auto" style={{ color: 'var(--border)' }} />}
            </div>
          );
        })}
      </nav>

      {/* User + Logout */}
      <div className="border-t px-3 py-3" style={{ borderColor: 'rgba(212,168,67,0.2)' }}>
        <div className="mb-2 px-1">
          <p className="text-white text-xs font-semibold truncate">{user?.name || 'User'}</p>
          <span className="badge text-[10px] px-1.5 py-0.5 mt-0.5"
            style={{ background: roleBadge.bg, color: roleBadge.color }}>
            {roleBadge.label}
          </span>
        </div>
        <button onClick={handleLogout}
          className="nav-item w-full text-left mt-1">
          <LogOut size={16} style={{ color: '#ff6b6b' }} />
          <span className="text-xs" style={{ color: '#ff6b6b' }}>Logout</span>
        </button>
      </div>
    </aside>
  );

  // ── Mobile top bar ─────────────────────────────────────────────────────────
  const MobileBar = () => (
    <div className="lg:hidden flex items-center justify-between px-4 py-3 sticky top-0 z-30"
      style={{ background: 'var(--dark)', borderBottom: '1px solid rgba(212,168,67,0.2)' }}>
      <div className="flex items-center gap-2">
        <div className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold"
          style={{ background: 'var(--primary)', color: 'var(--border)' }}>UP</div>
        <span className="text-xs font-bold" style={{ color: 'var(--border)' }}>
          {navItems.find(n => n.path === activePage)?.label || 'Election Cell'}
        </span>
      </div>
      <button onClick={() => setMobileMenuOpen(true)}>
        <Menu size={22} className="text-white/70" />
      </button>
    </div>
  );

  // ── Mobile drawer ──────────────────────────────────────────────────────────
  const MobileDrawer = () => (
    mobileMenuOpen ? (
      <div className="fixed inset-0 z-50 lg:hidden">
        <div className="absolute inset-0 bg-black/50" onClick={() => setMobileMenuOpen(false)} />
        <div className="absolute left-0 top-0 bottom-0 w-64 flex flex-col"
          style={{ background: 'var(--dark)' }}>
          <div className="flex items-center justify-between px-4 py-4 border-b"
            style={{ borderColor: 'rgba(212,168,67,0.2)' }}>
            <div>
              <p className="text-sm font-bold" style={{ color: 'var(--border)' }}>UP Election Cell</p>
              <p className="text-[11px]" style={{ color: 'rgba(212,168,67,0.6)' }}>उ.प्र. निर्वाचन कक्ष</p>
            </div>
            <button onClick={() => setMobileMenuOpen(false)}>
              <X size={20} className="text-white/60" />
            </button>
          </div>
          <nav className="flex-1 py-2 overflow-y-auto">
            {navItems.map((item) => {
              const active = activePage === item.path;
              return (
                <div key={item.path}
                  className={`nav-item ${active ? 'active' : ''}`}
                  onClick={() => { onNavigate(item.path); setMobileMenuOpen(false); }}>
                  <item.icon size={18} className="nav-icon shrink-0" />
                  <span className="nav-label">{item.label}</span>
                </div>
              );
            })}
          </nav>
          <div className="border-t px-3 py-3" style={{ borderColor: 'rgba(212,168,67,0.2)' }}>
            <p className="text-white text-xs font-semibold px-1 mb-1">{user?.name}</p>
            <button onClick={handleLogout} className="nav-item w-full text-left">
              <LogOut size={16} style={{ color: '#ff6b6b' }} />
              <span className="text-xs" style={{ color: '#ff6b6b' }}>Logout</span>
            </button>
          </div>
        </div>
      </div>
    ) : null
  );

  // ── Bottom nav (mobile) ────────────────────────────────────────────────────
  const BottomNav = () => (
    <nav className="lg:hidden fixed bottom-0 left-0 right-0 z-30 flex"
      style={{ background: 'var(--dark)', borderTop: '1px solid rgba(212,168,67,0.2)' }}>
      {navItems.slice(0, 5).map((item) => {
        const active = activePage === item.path;
        return (
          <button key={item.path}
            className="flex-1 flex flex-col items-center py-2 gap-0.5 transition-colors"
            onClick={() => onNavigate(item.path)}>
            <item.icon size={20}
              style={{ color: active ? 'var(--border)' : 'rgba(255,255,255,0.45)' }} />
            <span className="text-[9px]"
              style={{ color: active ? 'var(--border)' : 'rgba(255,255,255,0.45)' }}>
              {item.label}
            </span>
          </button>
        );
      })}
    </nav>
  );

  return (
    <div className="flex min-h-screen" style={{ background: 'var(--bg)' }}>
      <Sidebar />
      <MobileDrawer />
      <div className="flex-1 flex flex-col min-w-0">
        <MobileBar />
        <main className="flex-1 pb-16 lg:pb-0 overflow-auto">
          {children}
        </main>
      </div>
      <BottomNav />
    </div>
  );
}
