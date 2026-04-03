import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import { Vote, Eye, EyeOff, LogIn, BadgeCheck, ShieldCheck, Fingerprint, Star } from 'lucide-react'
import toast from 'react-hot-toast'
import { useAuth } from '../context/AuthContext'

// ── UP Police Khaki Palette ──────────────────────────────
const C = {
  bg:       '#f5f0e8',
  bgDeep:   '#ede5d4',
  sand:     '#e8dcc8',
  sandD:    '#ddd0b4',
  khaki:    '#c8ad7f',
  khakiD:   '#a8904f',
  olive:    '#4a5240',
  oliveD:   '#323825',
  brown:    '#3d2e1a',
  accent:   '#7a6640',
  text:     '#2a2015',
  textMid:  '#5a4a30',
  textSoft: '#8a7a5a',
  white:    '#fffef9',
  green:    '#4ade80',
}

const ROLE_ROUTES = {
  MASTER:      '/master',
  SUPER_ADMIN: '/super',
  ADMIN:       '/admin',
  STAFF:       '/staff',
}

function CornerStar({ style }) {
  return (
    <svg width="28" height="28" viewBox="0 0 32 32" style={style}>
      <polygon
        points="16,2 19,12 30,12 21,18 24,29 16,23 8,29 11,18 2,12 13,12"
        fill="none" stroke={C.khaki} strokeWidth="1.2" opacity="0.5"
      />
    </svg>
  )
}

function BadgeRing() {
  return (
    <div style={{ position: 'relative', width: 90, height: 90 }}>
      <motion.div
        animate={{ rotate: 360 }}
        transition={{ duration: 22, repeat: Infinity, ease: 'linear' }}
        style={{
          position: 'absolute', inset: 0, borderRadius: '50%',
          border: `1.5px dashed ${C.khaki}`, opacity: 0.5,
        }}
      />
      <motion.div
        animate={{ rotate: -360 }}
        transition={{ duration: 15, repeat: Infinity, ease: 'linear' }}
        style={{
          position: 'absolute', inset: 9, borderRadius: '50%',
          border: `1px dashed ${C.olive}`, opacity: 0.35,
        }}
      />
      <div style={{
        position: 'absolute', inset: 16, borderRadius: '50%',
        background: `linear-gradient(145deg, ${C.olive} 0%, ${C.oliveD} 100%)`,
        border: `2px solid ${C.khaki}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: `0 4px 16px rgba(74,82,64,0.4), inset 0 1px 0 rgba(255,255,255,0.1)`,
      }}>
        <Vote size={22} color={C.khaki} />
      </div>
      {[0,90,180,270].map(deg => (
        <div key={deg} style={{
          position: 'absolute', top: '50%', left: '50%',
          width: 5, height: 5, marginTop: -2.5, marginLeft: -2.5,
          borderRadius: '50%', background: C.khaki,
          transform: `rotate(${deg}deg) translateY(-45px)`,
          opacity: 0.65,
        }} />
      ))}
    </div>
  )
}

export default function LoginPage() {
  const { login }   = useAuth()
  const navigate    = useNavigate()
  const [form, setForm]         = useState({ username: '', password: '' })
  const [showPass, setShowPass] = useState(false)
  const [loading, setLoading]   = useState(false)
  const [focused, setFocused]   = useState(null)

  const inputStyle = (name) => ({
    width: '100%', boxSizing: 'border-box',
    background: focused === name ? C.white : C.sand,
    border: `1.5px solid ${focused === name ? C.olive : C.sandD}`,
    borderRadius: 8,
    padding: name === 'username' ? '11px 14px 11px 38px' : '11px 42px 11px 14px',
    color: C.text, fontSize: 14, outline: 'none',
    transition: 'all 0.22s',
    boxShadow: focused === name
      ? `0 0 0 3px rgba(74,82,64,0.1), 0 2px 8px rgba(74,82,64,0.07)`
      : `0 1px 2px rgba(61,46,26,0.05)`,
    fontFamily: '"IBM Plex Mono", monospace',
    letterSpacing: name === 'password' && !showPass ? '3px' : 'normal',
  })

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!form.username.trim() || !form.password) {
      toast.error('Enter your User ID / PNO and password')
      return
    }
    setLoading(true)
    try {
      const user  = await login(form.username.trim(), form.password)
      const route = ROLE_ROUTES[user.role?.toUpperCase()]
      if (!route) { toast.error(`Unknown role: ${user.role}`); return }
      toast.success(`Welcome, ${user.name}!`)
      navigate(route, { replace: true })
    } catch (err) {
      const msg = err?.response?.data?.message || err.message || ''
      if (msg.includes('Invalid') || msg.includes('credentials') || err?.response?.status === 401)
        toast.error('Invalid User ID or Password')
      else
        toast.error('Cannot reach server. Check your network.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{
      minHeight: '100vh',
      background: `linear-gradient(155deg, #f2ece0 0%, ${C.bgDeep} 50%, #e8dfc8 100%)`,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 16, position: 'relative', overflow: 'hidden',
    }}>

      {/* woven texture */}
      <div style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        backgroundImage: `
          repeating-linear-gradient(45deg, rgba(168,144,80,0.035) 0px, rgba(168,144,80,0.035) 1px, transparent 1px, transparent 9px),
          repeating-linear-gradient(-45deg, rgba(168,144,80,0.035) 0px, rgba(168,144,80,0.035) 1px, transparent 1px, transparent 9px)
        `,
      }} />

      {/* big "UP" watermark */}
      <div style={{
        position: 'absolute', top: '50%', left: '50%',
        transform: 'translate(-50%, -50%)',
        fontSize: 340, fontWeight: 900,
        color: 'rgba(168,144,80,0.045)',
        fontFamily: 'Georgia, serif',
        userSelect: 'none', pointerEvents: 'none',
        lineHeight: 1,
      }}>UP</div>

      {/* corner stars */}
      <CornerStar style={{ position: 'absolute', top: 20, left: 20 }} />
      <CornerStar style={{ position: 'absolute', top: 20, right: 20, transform: 'rotate(45deg)' }} />
      <CornerStar style={{ position: 'absolute', bottom: 20, left: 20, transform: 'rotate(-45deg)' }} />
      <CornerStar style={{ position: 'absolute', bottom: 20, right: 20, transform: 'rotate(90deg)' }} />

      {/* top rule */}
      <div style={{
        position: 'absolute', top: 14, left: 56, right: 56, height: 1,
        background: `linear-gradient(90deg, transparent, ${C.khaki}55, transparent)`,
      }} />
      <div style={{
        position: 'absolute', bottom: 14, left: 56, right: 56, height: 1,
        background: `linear-gradient(90deg, transparent, ${C.khaki}55, transparent)`,
      }} />

      {/* ════ CARD ════ */}
      <motion.div
        initial={{ opacity: 0, y: 30, scale: 0.97 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.55, ease: [0.22, 1, 0.36, 1] }}
        style={{ width: '100%', maxWidth: 430, position: 'relative' }}
      >
        <div style={{
          borderRadius: 18, overflow: 'hidden',
          border: `1px solid ${C.khaki}77`,
          background: C.white,
          boxShadow: `0 24px 60px rgba(61,46,26,0.2), 0 4px 14px rgba(61,46,26,0.09)`,
        }}>

          {/* olive top bar */}
          <div style={{
            background: `linear-gradient(90deg, ${C.oliveD} 0%, ${C.olive} 55%, ${C.oliveD} 100%)`,
            padding: '9px 20px',
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
              <ShieldCheck size={13} color={C.khaki} />
              <span style={{
                color: C.khaki, fontSize: 10, fontWeight: 700,
                letterSpacing: '2px', textTransform: 'uppercase',
                fontFamily: '"IBM Plex Mono", monospace',
              }}>SECURE SYSTEM</span>
            </div>
            <div style={{ display: 'flex', gap: 5 }}>
              {[0, 0.4, 0.8].map((d, i) => (
                <motion.div key={i}
                  style={{ width: 5, height: 5, borderRadius: '50%', background: C.khaki }}
                  animate={{ opacity: [0.25, 1, 0.25] }}
                  transition={{ duration: 1.6, delay: d, repeat: Infinity }}
                />
              ))}
            </div>
          </div>

          {/* khaki accent stripe */}
          <div style={{
            height: 4,
            background: `linear-gradient(90deg, ${C.khakiD}, ${C.khaki}, #e8d08a, ${C.khaki}, ${C.khakiD})`,
          }} />

          {/* body */}
          <div style={{ padding: '28px 32px 32px' }}>

            {/* emblem + titles */}
            <motion.div
              initial={{ opacity: 0, y: -8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.18, duration: 0.5 }}
              style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', marginBottom: 26 }}
            >
              <BadgeRing />
              <div style={{ marginTop: 14, textAlign: 'center' }}>
                <p style={{
                  fontFamily: '"Playfair Display", Georgia, serif',
                  fontSize: 18, fontWeight: 700,
                  color: C.brown, letterSpacing: '0.2px', marginBottom: 3,
                }}>
                  उत्तर प्रदेश निर्वाचन कक्ष
                </p>
                <p style={{
                  fontFamily: '"IBM Plex Mono", monospace',
                  fontSize: 9, fontWeight: 600,
                  color: C.olive, letterSpacing: '3.5px', textTransform: 'uppercase',
                }}>
                  Uttar Pradesh Election Cell
                </p>
              </div>

              {/* ornamental rule */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 14, width: 230 }}>
                <div style={{ flex: 1, height: 1, background: `linear-gradient(90deg, transparent, ${C.khaki})` }} />
                <Star size={8} fill={C.khaki} color={C.khaki} />
                <div style={{ height: 1, width: 6, background: C.khaki }} />
                <Star size={8} fill={C.khaki} color={C.khaki} />
                <div style={{ flex: 1, height: 1, background: `linear-gradient(90deg, ${C.khaki}, transparent)` }} />
              </div>
            </motion.div>

            {/* sub-heading */}
            <motion.div
              initial={{ opacity: 0 }} animate={{ opacity: 1 }}
              transition={{ delay: 0.3 }}
              style={{ marginBottom: 22 }}
            >
              <p style={{
                fontSize: 10, fontWeight: 700, letterSpacing: '3px',
                textTransform: 'uppercase', color: C.textSoft,
                fontFamily: '"IBM Plex Mono", monospace', marginBottom: 4,
              }}>
                Election Duty Management System
              </p>
              <h2 style={{
                fontFamily: '"Playfair Display", Georgia, serif',
                fontSize: 22, fontWeight: 700, color: C.brown, margin: 0,
              }}>
                Officer Sign In
              </h2>
            </motion.div>

            {/* form */}
            <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>

              {/* username */}
              <motion.div initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.37 }}>
                <label style={{
                  display: 'block', marginBottom: 7, fontSize: 10, fontWeight: 800,
                  letterSpacing: '2.5px', textTransform: 'uppercase', color: C.olive,
                  fontFamily: '"IBM Plex Mono", monospace',
                }}>User ID / PNO</label>
                <div style={{ position: 'relative' }}>
                  <BadgeCheck size={14} style={{
                    position: 'absolute', left: 12, top: '50%',
                    transform: 'translateY(-50%)',
                    color: focused === 'username' ? C.olive : C.textSoft,
                    transition: 'color 0.2s',
                  }} />
                  <input
                    style={inputStyle('username')}
                    placeholder="Enter your ID or PNO"
                    value={form.username}
                    onChange={e => setForm({ ...form, username: e.target.value })}
                    onFocus={() => setFocused('username')}
                    onBlur={() => setFocused(null)}
                    autoComplete="username"
                  />
                </div>
              </motion.div>

              {/* password */}
              <motion.div initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.44 }}>
                <label style={{
                  display: 'block', marginBottom: 7, fontSize: 10, fontWeight: 800,
                  letterSpacing: '2.5px', textTransform: 'uppercase', color: C.olive,
                  fontFamily: '"IBM Plex Mono", monospace',
                }}>Password</label>
                <div style={{ position: 'relative' }}>
                  <input
                    style={inputStyle('password')}
                    type={showPass ? 'text' : 'password'}
                    placeholder="Enter your password"
                    value={form.password}
                    onChange={e => setForm({ ...form, password: e.target.value })}
                    onFocus={() => setFocused('password')}
                    onBlur={() => setFocused(null)}
                    autoComplete="current-password"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPass(v => !v)}
                    style={{
                      position: 'absolute', right: 11, top: '50%',
                      transform: 'translateY(-50%)',
                      background: 'none', border: 'none', cursor: 'pointer',
                      display: 'flex', color: C.textSoft, padding: 4,
                      transition: 'color 0.18s',
                    }}
                    onMouseEnter={e => e.currentTarget.style.color = C.olive}
                    onMouseLeave={e => e.currentTarget.style.color = C.textSoft}
                  >
                    <AnimatePresence mode="wait" initial={false}>
                      <motion.span
                        key={showPass ? 'off' : 'on'}
                        initial={{ opacity: 0, scale: 0.7 }}
                        animate={{ opacity: 1, scale: 1 }}
                        exit={{ opacity: 0, scale: 0.7 }}
                        transition={{ duration: 0.13 }}
                        style={{ display: 'flex' }}
                      >
                        {showPass ? <EyeOff size={15} /> : <Eye size={15} />}
                      </motion.span>
                    </AnimatePresence>
                  </button>
                </div>
              </motion.div>

              {/* submit */}
              <motion.div
                initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.52 }} style={{ marginTop: 4 }}
              >
                <motion.button
                  type="submit"
                  disabled={loading}
                  whileHover={!loading ? { scale: 1.015, y: -1 } : {}}
                  whileTap={!loading ? { scale: 0.985 } : {}}
                  style={{
                    width: '100%', height: 48, borderRadius: 9, border: 'none',
                    cursor: loading ? 'not-allowed' : 'pointer',
                    background: loading
                      ? `${C.olive}77`
                      : `linear-gradient(160deg, ${C.olive} 0%, ${C.oliveD} 100%)`,
                    color: C.khaki,
                    fontSize: 12, fontWeight: 800,
                    letterSpacing: '3.5px', textTransform: 'uppercase',
                    fontFamily: '"IBM Plex Mono", monospace',
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9,
                    boxShadow: loading ? 'none'
                      : `0 4px 18px rgba(74,82,64,0.38), inset 0 1px 0 rgba(200,173,127,0.2)`,
                    transition: 'box-shadow 0.2s, background 0.2s',
                    position: 'relative', overflow: 'hidden',
                  }}
                >
                  {!loading && (
                    <motion.div
                      style={{
                        position: 'absolute', top: 0,
                        width: '40%', height: '100%',
                        background: 'linear-gradient(90deg, transparent, rgba(200,173,127,0.15), transparent)',
                        transform: 'skewX(-15deg)',
                      }}
                      animate={{ left: ['-50%', '160%'] }}
                      transition={{ duration: 2.2, repeat: Infinity, repeatDelay: 2.5, ease: 'easeInOut' }}
                    />
                  )}
                  {loading ? (
                    <motion.div
                      style={{
                        width: 20, height: 20,
                        border: `2px solid rgba(200,173,127,0.25)`,
                        borderTopColor: C.khaki, borderRadius: '50%',
                      }}
                      animate={{ rotate: 360 }}
                      transition={{ duration: 0.75, repeat: Infinity, ease: 'linear' }}
                    />
                  ) : (
                    <><LogIn size={15} /> SIGN IN</>
                  )}
                </motion.button>
              </motion.div>
            </form>

            {/* footer */}
            <motion.div
              initial={{ opacity: 0 }} animate={{ opacity: 1 }}
              transition={{ delay: 0.65 }}
              style={{
                marginTop: 22, paddingTop: 16,
                borderTop: `1px solid ${C.khaki}40`,
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <Fingerprint size={12} color={C.textSoft} />
                <span style={{
                  fontSize: 9, color: C.textSoft,
                  fontFamily: '"IBM Plex Mono", monospace',
                  letterSpacing: '1.5px', textTransform: 'uppercase',
                }}>Authorised Personnel Only</span>
              </div>
              <span style={{ fontSize: 9, color: C.textSoft, fontFamily: '"IBM Plex Mono", monospace' }}>
                UP Police © 2026
              </span>
            </motion.div>
          </div>

          {/* bottom olive stripe */}
          <div style={{
            height: 4,
            background: `linear-gradient(90deg, ${C.oliveD}, ${C.olive}, ${C.oliveD})`,
          }} />
        </div>
      </motion.div>

      {/* systems online */}
      <motion.div
        initial={{ opacity: 0 }} animate={{ opacity: 1 }}
        transition={{ delay: 0.9 }}
        style={{
          position: 'fixed', bottom: 16, right: 20,
          display: 'flex', alignItems: 'center', gap: 6,
        }}
      >
        <motion.div
          style={{ width: 6, height: 6, borderRadius: '50%', background: C.green }}
          animate={{ boxShadow: [`0 0 0px ${C.green}`, `0 0 8px ${C.green}`, `0 0 0px ${C.green}`] }}
          transition={{ duration: 2, repeat: Infinity }}
        />
        <span style={{
          fontSize: 9, fontFamily: '"IBM Plex Mono", monospace',
          color: C.textSoft, letterSpacing: '1.5px', textTransform: 'uppercase',
        }}>Systems Online</span>
      </motion.div>
    </div>
  )
}