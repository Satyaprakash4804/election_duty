import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Eye, EyeOff, LogIn, BadgeCheck, Lock, CircleDot } from 'lucide-react';
import { useAuthStore } from '../store/authStore';
import { ErrorBanner } from '../components/common';
import toast from 'react-hot-toast';
import LoginSplash from '../components/LoginSplash';

const ROLE_ROUTES = {
  MASTER: '/master',
  SUPER_ADMIN: '/super',
  ADMIN: '/admin',
  STAFF: '/staff',
};

export default function LoginPage() {
  const navigate = useNavigate();
  const { login } = useAuthStore();

  const [pno, setPno] = useState('');
  const [password, setPassword] = useState('');
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Add state inside component (alongside existing state)
  const [showSplash, setShowSplash] = useState(false);

  useEffect(() => {
    setShowSplash(true);

    const timer = setTimeout(() => {
      setShowSplash(false);
    }, 4000); // 4 seconds

    return () => clearTimeout(timer);
  }, []);

  const handleLogin = async (e) => {
    e?.preventDefault();
    if (!pno.trim() || !password) {
      setError('Please enter your User ID / PNO and password.');
      return;
    }
    setLoading(true);
    setError('');
    try {
      const role = await login(pno.trim(), password);
      const route = ROLE_ROUTES[role];
      if (!route) {
        setError(`Access denied. Unrecognised role: "${role}". Contact your administrator.`);
        return;
      }
      toast.success('Login successful');
      navigate(route);
    } catch (err) {
      const msg = err.message || '';
      if (msg.includes('401') || msg.includes('Invalid') || msg.includes('credentials')) {
        setError('Invalid User ID or Password. Please try again.');
      } else if (msg.includes('Network') || msg.includes('ECONNREFUSED')) {
        setError('Cannot reach server. Check your network connection.');
      } else if (msg.includes('timeout')) {
        setError('Server is not responding. Please try again.');
      } else {
        setError('Login failed. Please try again or contact support.');
      }
    } finally {
      setLoading(false);
    }
  };

  if (showSplash) {
    return <LoginSplash />;
  }

  return (
    <>
      <div className="min-h-screen grid-bg flex items-center justify-center p-5 relative overflow-hidden">
        {/* Decorative orbs */}
        <div className="absolute -top-20 -right-16 w-64 h-64 rounded-full pointer-events-none"
          style={{ background: 'rgba(184,134,11,0.07)' }} />
        <div className="absolute -bottom-24 -left-20 w-72 h-72 rounded-full pointer-events-none"
          style={{ background: 'rgba(139,105,20,0.05)' }} />

        <div className="w-full max-w-md fade-in relative z-10">
          {/* Top banner strip */}
          <div className="px-4 py-2.5 text-center rounded-t-2xl"
            style={{ background: 'var(--dark)' }}>
            <p className="text-xs font-black tracking-widest uppercase"
              style={{ color: 'var(--border)', letterSpacing: '1.6px' }}>
              ELECTION DUTY MANAGEMENT SYSTEM
            </p>
          </div>

          {/* Card */}
          <div className="rounded-b-2xl border px-7 py-7"
            style={{
              background: 'var(--bg)',
              borderColor: 'var(--border)',
              boxShadow: '0 8px 32px rgba(139,105,20,0.18)',
            }}>

            {/* Emblem */}
            <div className="flex flex-col items-center mb-7">
              <div className="w-20 h-20 rounded-full flex items-center justify-center mb-3.5 relative"
                style={{
                  background: 'var(--dark)',
                  border: '2.5px solid var(--border)',
                  boxShadow: '0 0 18px rgba(139,105,20,0.35)',
                }}>
                {/* Ashoka chakra style */}
                <img src='/logo.jpeg' className="w-20 h-20 rounded-full flex items-center justify-center"
                  style={{ background: 'var(--primary)' }}>
                </img>
              </div>

              <h1 className="font-black text-center text-sm leading-snug"
                style={{ color: 'var(--dark)', fontFamily: "'Tiro Devanagari Hindi', serif" }}>
                उत्तर प्रदेश निर्वाचन कक्ष
              </h1>
              <p className="text-xs font-semibold tracking-widest mt-1"
                style={{ color: 'var(--subtle)', letterSpacing: '1.2px' }}>
                Uttar Pradesh Election Cell
              </p>

              {/* Divider ornament */}
              <div className="flex items-center gap-2 mt-3">
                <div className="h-px w-10" style={{ background: 'var(--border)' }} />
                <div className="w-1.5 h-1.5 rounded-full" style={{ background: 'var(--border)' }} />
                <div className="h-px w-10" style={{ background: 'var(--border)' }} />
              </div>
            </div>

            {/* Form */}
            <form onSubmit={handleLogin} className="space-y-3.5">
              {/* User ID */}
              <div>
                <div className="relative">
                  <BadgeCheck size={16}
                    className="absolute left-3 top-1/2 -translate-y-1/2"
                    style={{ color: 'var(--primary)' }} />
                  <input
                    type="text"
                    value={pno}
                    onChange={(e) => setPno(e.target.value)}
                    placeholder="User ID / PNO"
                    autoComplete="username"
                    className="field !pl-9"
                  />
                </div>
              </div>

              {/* Password */}
              <div>
                <div className="relative">
                  <Lock size={16}
                    className="absolute left-3 top-1/2 -translate-y-1/2"
                    style={{ color: 'var(--primary)' }} />
                  <input
                    type={showPass ? 'text' : 'password'}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Password"
                    autoComplete="current-password"
                    className="field !pl-9 pr-10"
                  />
                  <button type="button"
                    className="absolute right-3 top-1/2 -translate-y-1/2"
                    style={{ color: 'var(--subtle)' }}
                    onClick={() => setShowPass(!showPass)}>
                    {showPass ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>

              {/* Error */}
              {error && (
                <div className="transition-all">
                  <ErrorBanner message={error} />
                </div>
              )}

              {/* Submit */}
              <button type="submit" disabled={loading}
                className="btn-primary w-full h-12 mt-2">
                {loading ? (
                  <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                ) : (
                  <>
                    <LogIn size={18} />
                    <span className="tracking-widest text-sm">LOGIN</span>
                  </>
                )}
              </button>
            </form>

            {/* Server indicator */}
            <div className="flex items-center justify-center gap-1.5 mt-4">
              <CircleDot size={8} style={{ color: '#4CAF50' }} />
              <span className="font-mono text-[10px]" style={{ color: 'var(--subtle)' }}>
                {import.meta.env.VITE_API_URL || 'http://localhost:5000/api'}
              </span>
            </div>

            {/* Footer */}
            <div className="mt-4 pt-4 border-t text-center" style={{ borderColor: 'var(--border)' }}>
              <p className="text-[11px] leading-relaxed" style={{ color: 'var(--subtle)' }}>
                Secure System — Authorised Personnel Only<br />
                UP Police Election Cell © 2026
              </p>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
