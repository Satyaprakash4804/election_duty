import { useEffect, useState } from 'react';

export default function LoginSplash() {
    const [exiting, setExiting] = useState(false);
    const [visible, setVisible] = useState(true);

    useEffect(() => {
        const exitTimer = setTimeout(() => setExiting(true), 3000); // start fade at 3s
        const removeTimer = setTimeout(() => setVisible(false), 4000); // remove at 4s

        return () => {
            clearTimeout(exitTimer);
            clearTimeout(removeTimer);
        };
    }, []);

    if (!visible) return null;

    return (
        <div
            className={`fixed inset-0 z-50 flex items-center justify-center transition-all duration-700 ease-in-out ${exiting
                    ? 'opacity-0 scale-105 pointer-events-none'
                    : 'opacity-100 scale-100'
                }`}
            style={{ background: 'var(--dark)' }}
        >
            {/* Animated grid background */}
            <div className="absolute inset-0 opacity-10 grid-bg pointer-events-none" />

            {/* Radial glow */}
            <div
                className="absolute inset-0 pointer-events-none"
                style={{
                    background: 'radial-gradient(ellipse 600px 400px at 50% 50%, rgba(212,168,67,0.08) 0%, transparent 70%)',
                }}
            />

            {/* Card */}
            <div
                className="relative w-80 sm:w-96 rounded-2xl overflow-hidden fade-in"
                style={{
                    border: '1.5px solid rgba(212,168,67,0.35)',
                    background: '#3a2500',
                    boxShadow: '0 0 80px rgba(212,168,67,0.12), 0 32px 64px rgba(0,0,0,0.6)',
                    animationDuration: '0.55s',
                }}
            >
                {/* Top strip */}
                <div
                    className="w-full px-5 py-3 text-center"
                    style={{
                        background: 'rgba(212,168,67,0.08)',
                        borderBottom: '1px solid rgba(212,168,67,0.2)',
                    }}
                >
                    <p
                        className="font-black tracking-widest uppercase"
                        style={{ fontSize: '8px', letterSpacing: '2px', color: 'var(--border)' }}
                    >
                        Uttar Pradesh Election Cell — Authenticated
                    </p>
                </div>

                {/* Photo */}
                <div
                    className="relative overflow-hidden"
                    style={{ height: '240px', background: 'linear-gradient(180deg, #2a1a00 0%, #1a1000 100%)' }}
                >
                    <img
                        src="/IPS.jpeg"
                        alt="Suraj Kumar Rai"
                        className="w-full h-full object-cover object-top"
                        style={{ animation: 'imgFadeIn 0.5s 0.45s ease forwards', opacity: 0 }}
                    />

                    {/* Stars badge — top right */}
                    <div
                        className="absolute top-3 right-3 flex gap-1"
                        style={{ animation: 'fadeUpIn 0.4s 0.75s ease forwards', opacity: 0 }}
                    >
                        {[0, 1, 2].map(i => (
                            <span key={i} style={{ color: 'var(--border)', fontSize: '13px' }}>★</span>
                        ))}
                    </div>

                    {/* Verified badge — top left */}
                    <div
                        className="absolute top-3 left-3"
                        style={{ animation: 'fadeUpIn 0.4s 0.85s ease forwards', opacity: 0 }}
                    >
                        <span
                            className="text-xs font-black tracking-widest px-2 py-1 rounded-full"
                            style={{
                                background: 'rgba(76,175,80,0.2)',
                                border: '1px solid rgba(76,175,80,0.4)',
                                color: '#81c784',
                                fontSize: '9px',
                                letterSpacing: '1.5px',
                            }}
                        >
                            ✓ VERIFIED
                        </span>
                    </div>

                    {/* Bottom gradient fade */}
                    <div
                        className="absolute bottom-0 left-0 right-0"
                        style={{
                            height: '90px',
                            background: 'linear-gradient(to top, #3a2500 0%, transparent 100%)',
                        }}
                    />
                </div>

                {/* Info body */}
                <div
                    className="px-6 pb-6 pt-4 text-center"
                    style={{ animation: 'fadeUpIn 0.4s 0.6s ease forwards', opacity: 0 }}
                >
                    <h2
                        className="font-black mb-1"
                        style={{
                            fontSize: '20px',
                            color: 'var(--border)',
                            fontFamily: "'Tiro Devanagari Hindi', serif",
                            letterSpacing: '0.5px',
                        }}
                    >
                        Suraj Kumar Rai
                    </h2>

                    <div className="flex items-center justify-center gap-2 mb-4">
                        <div
                            className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full"
                            style={{
                                background: 'rgba(212,168,67,0.12)',
                                border: '1px solid rgba(212,168,67,0.3)',
                            }}
                        >
                            <span
                                className="font-black tracking-widest uppercase"
                                style={{ fontSize: '11px', color: 'var(--border)', letterSpacing: '2.5px' }}
                            >
                                IPS
                            </span>
                        </div>
                    </div>

                    {/* Ornament divider */}
                    <div className="flex items-center gap-2 mb-4">
                        <div className="flex-1 h-px" style={{ background: 'rgba(212,168,67,0.2)' }} />
                        <div className="flex gap-1">
                            {[0, 1, 2].map(i => (
                                <div key={i} className="w-1 h-1 rounded-full" style={{ background: 'rgba(212,168,67,0.5)' }} />
                            ))}
                        </div>
                        <div className="flex-1 h-px" style={{ background: 'rgba(212,168,67,0.2)' }} />
                    </div>

                    <p
                        className="uppercase tracking-widest mb-4"
                        style={{ fontSize: '10px', color: 'rgba(212,168,67,0.5)', letterSpacing: '2px' }}
                    >
                        UP Police Election Cell
                    </p>

                    {/* Progress bar */}
                    <div
                        className="w-full rounded-full overflow-hidden mb-2"
                        style={{ height: '2px', background: 'rgba(212,168,67,0.12)' }}
                    >
                        <div
                            className="h-full rounded-full"
                            style={{
                                background: 'var(--border)',
                                animation: 'progressFill 1.8s 0.3s ease forwards',
                                width: '0%',
                            }}
                        />
                    </div>

                    <p style={{ fontSize: '10px', color: 'rgba(212,168,67,0.35)', letterSpacing: '1.5px' }}>
                        LOADING DASHBOARD...
                    </p>

                    {/* Pulsing dots */}
                    <div className="flex justify-center gap-1 mt-3">
                        {[0, 0.2, 0.4].map((delay, i) => (
                            <div
                                key={i}
                                className="w-1 h-1 rounded-full"
                                style={{
                                    background: 'rgba(212,168,67,0.5)',
                                    animation: `dotPulse 1.2s ${delay}s ease infinite`,
                                }}
                            />
                        ))}
                    </div>
                </div>
            </div>

            <style>{`
        @keyframes imgFadeIn { to { opacity: 1; } }
        @keyframes fadeUpIn {
          from { opacity: 0; transform: translateY(8px); }
          to   { opacity: 1; transform: translateY(0); }
        }
        @keyframes progressFill { to { width: 100%; } }
        @keyframes dotPulse {
          0%, 100% { opacity: 0.3; transform: scale(0.8); }
          50% { opacity: 1; transform: scale(1.3); }
        }
      `}</style>
        </div>
    );
}