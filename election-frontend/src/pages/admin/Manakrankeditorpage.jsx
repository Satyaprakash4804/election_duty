import { useState, useEffect, useCallback } from "react";
import {
  Shield, ShieldOff, Users, Gavel, ShieldCheck,
  Lock, ChevronLeft, Check, AlertTriangle, Minus, Plus,
  Hash, UserCheck, Layers
} from "lucide-react";

// ─── Theme tokens (mirroring Flutter consts) ──────────────────────────────────
const T = {
  bg:      "#FDF6E3",
  surface: "#F5E6C8",
  primary: "#8B6914",
  accent:  "#B8860B",
  dark:    "#4A3000",
  subtle:  "#AA8844",
  border:  "#D4A843",
  error:   "#C0392B",
  success: "#2D6A1E",
  armed:   "#6A1B9A",
  unarmed: "#1A5276",
  pac:     "#00695C",
  aux:     "#E65100",
};

// ─── Rank definitions (mirrors _kRanks) ───────────────────────────────────────
const RANKS = [
  { key: "si",    label: "SI",         hindi: "उप निरीक्षक",    icon: Shield,      hasArmedSplit: true,  isDecimal: false },
  { key: "hc",    label: "HC",         hindi: "मुख्य आरक्षी",    icon: UserCheck,   hasArmedSplit: true,  isDecimal: false },
  { key: "const", label: "Constable",  hindi: "आरक्षी",          icon: ShieldOff,   hasArmedSplit: true,  isDecimal: false },
  { key: "aux",   label: "Aux Force",  hindi: "सहायक बल",        icon: Users,       hasArmedSplit: true,  isDecimal: false },
  { key: "pac",   label: "PAC",        hindi: "पीएसी (सेक्शन)", icon: Layers,      hasArmedSplit: false, isDecimal: true  },
];

// ─── Field key map ────────────────────────────────────────────────────────────
const FIELD_KEYS = {
  si_armed:      "siArmedCount",
  si_unarmed:    "siUnarmedCount",
  hc_armed:      "hcArmedCount",
  hc_unarmed:    "hcUnarmedCount",
  const_armed:   "constArmedCount",
  const_unarmed: "constUnarmedCount",
  aux_armed:     "auxArmedCount",
  aux_unarmed:   "auxUnarmedCount",
  pac:           "pacCount",
  sankhya:       "sankhya",
};

// ─── Helpers ─────────────────────────────────────────────────────────────────
function initVal(v, decimal = false) {
  if (v == null) return "";
  const n = typeof v === "number" ? v : (parseFloat(v) || 0);
  if (n === 0) return "";
  if (decimal) return n === Math.floor(n) ? String(Math.floor(n)) : String(n);
  return String(Math.floor(n));
}

function parseVal(txt, decimal = false) {
  const t = txt.trim();
  if (!t) return 0;
  const n = decimal ? parseFloat(t) : parseInt(t, 10);
  return isNaN(n) ? 0 : n;
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function StepBtn({ icon: Icon, enabled, onClick, color, size = 38 }) {
  return (
    <button
      type="button"
      onClick={enabled ? onClick : undefined}
      disabled={!enabled}
      style={{
        width: size, height: size,
        borderRadius: 8,
        border: `1.2px solid ${enabled ? color + "66" : "#bbb3"}`,
        background: enabled ? color + "1e" : "#8882",
        display: "flex", alignItems: "center", justifyContent: "center",
        cursor: enabled ? "pointer" : "not-allowed",
        transition: "all .12s",
        flexShrink: 0,
      }}
    >
      <Icon size={size * 0.45} color={enabled ? color : "#bbb"} />
    </button>
  );
}

function CountField({ fieldKey, label, sublabel, icon: Icon, color, decimal, value, onChange }) {
  const active = value > 0;

  const handleChange = (e) => {
    const raw = e.target.value;
    if (decimal) {
      if (/^[0-9]*\.?[0-9]*$/.test(raw)) onChange(raw);
    } else {
      if (/^\d{0,3}$/.test(raw)) onChange(raw);
    }
  };

  const step = (delta) => {
    const cur = parseVal(String(value), decimal);
    const next = Math.max(0, Math.min(999, cur + delta));
    if (next === 0) onChange("");
    else if (decimal) onChange(next === Math.floor(next) ? String(Math.floor(next)) : String(next));
    else onChange(String(Math.floor(next)));
  };

  return (
    <div style={{
      borderRadius: 10,
      border: `${active ? 1.3 : 1}px solid ${active ? color + "72" : T.border + "66"}`,
      background: active ? color + "0f" : "white",
      padding: "8px 10px 10px",
      transition: "all .18s",
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 4, marginBottom: 6 }}>
        <Icon size={12} color={color} />
        <span style={{ color, fontSize: 11.5, fontWeight: 800, flex: 1 }}>{label}</span>
        <span style={{ color: color + "99", fontSize: 9.5, fontWeight: 600 }}>{sublabel}</span>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
        <StepBtn icon={Minus} enabled={value > 0} onClick={() => step(decimal ? -0.5 : -1)} color={T.error} size={32} />
        <input
          value={String(value === 0 ? "" : value)}
          onChange={handleChange}
          placeholder="0"
          style={{
            flex: 1, height: 38, textAlign: "center",
            borderRadius: 7,
            border: `${active ? 1.3 : 1}px solid ${active ? color : T.border + "80"}`,
            outline: "none", fontSize: 16, fontWeight: 900,
            color: active ? color : T.dark,
            fontFamily: "'Playfair Display', Georgia, serif",
            background: "white",
          }}
        />
        <StepBtn icon={Plus} enabled color={color} onClick={() => step(decimal ? 0.5 : 1)} size={32} />
      </div>
    </div>
  );
}

function SplitRankCard({ rank, values, onChange, accentColor }) {
  const armedKey   = `${rank.key}_armed`;
  const unarmedKey = `${rank.key}_unarmed`;
  const armed   = parseVal(String(values[armedKey]   ?? ""), false);
  const unarmed = parseVal(String(values[unarmedKey] ?? ""), false);
  const total   = armed + unarmed;
  const active  = total > 0;
  const color   = rank.key === "aux" ? T.aux : accentColor;
  const Icon    = rank.icon;

  return (
    <div style={{
      borderRadius: 12,
      border: `${active ? 1.4 : 1}px solid ${active ? color + "66" : T.border + "66"}`,
      background: active ? color + "08" : "white",
      padding: 16,
      marginBottom: 12,
      transition: "all .18s",
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 14 }}>
        <div style={{
          width: 38, height: 38, borderRadius: 8,
          background: color + "1a",
          display: "flex", alignItems: "center", justifyContent: "center",
        }}>
          <Icon size={18} color={color} />
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ color: T.dark, fontSize: 14, fontWeight: 800 }}>{rank.label}</div>
          <div style={{ color: T.subtle, fontSize: 11 }}>{rank.hindi}</div>
        </div>
        {active && (
          <span style={{
            background: color + "1f", color, fontSize: 11, fontWeight: 800,
            padding: "3px 10px", borderRadius: 20,
          }}>
            कुल: {total}
          </span>
        )}
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
        <CountField
          fieldKey={armedKey} label="सशस्त्र" sublabel="Armed"
          icon={Gavel} color={T.armed} decimal={false}
          value={values[armedKey] ?? ""}
          onChange={(v) => onChange(armedKey, v)}
        />
        <CountField
          fieldKey={unarmedKey} label="निःशस्त्र" sublabel="Unarmed"
          icon={Shield} color={T.unarmed} decimal={false}
          value={values[unarmedKey] ?? ""}
          onChange={(v) => onChange(unarmedKey, v)}
        />
      </div>
    </div>
  );
}

function PacCard({ rank, values, onChange }) {
  const value  = parseVal(String(values[rank.key] ?? ""), true);
  const active = value > 0;
  const Icon   = rank.icon;

  const step = (delta) => {
    const next = Math.max(0, Math.min(999, value + delta));
    if (next === 0) onChange(rank.key, "");
    else onChange(rank.key, next === Math.floor(next) ? String(Math.floor(next)) : String(next));
  };

  const handleChange = (e) => {
    const raw = e.target.value;
    if (/^[0-9]*\.?[0-9]*$/.test(raw)) onChange(rank.key, raw);
  };

  return (
    <div style={{
      borderRadius: 12,
      border: `${active ? 1.4 : 1}px solid ${active ? T.pac + "66" : T.border + "66"}`,
      background: active ? T.pac + "08" : "white",
      padding: "12px 16px",
      marginBottom: 12,
      display: "flex", alignItems: "center", gap: 12,
      transition: "all .18s",
    }}>
      <div style={{
        width: 38, height: 38, borderRadius: 8,
        background: T.pac + "1a",
        display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
      }}>
        <Icon size={18} color={T.pac} />
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ color: T.dark, fontSize: 14, fontWeight: 800 }}>{rank.label}</div>
        <div style={{ color: T.subtle, fontSize: 11 }}>{rank.hindi}</div>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
        <StepBtn icon={Minus} enabled={value > 0} onClick={() => step(-0.5)} color={T.error} />
        <input
          value={String(value === 0 ? "" : value)}
          onChange={handleChange}
          placeholder="0"
          style={{
            width: 60, height: 38, textAlign: "center",
            borderRadius: 8,
            border: `${active ? 1.4 : 1}px solid ${active ? T.pac : T.border + "99"}`,
            outline: "none", fontSize: 17, fontWeight: 900,
            color: active ? T.pac : T.dark,
            fontFamily: "'Playfair Display', Georgia, serif",
            background: "white",
          }}
        />
        <StepBtn icon={Plus} enabled onClick={() => step(0.5)} color={T.pac} />
      </div>
    </div>
  );
}

function MiniStat({ icon: Icon, label, value, color }) {
  if (!value || value === 0) return null;
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 3 }}>
      <Icon size={11} color={color} />
      <span style={{ color: color + "bb", fontSize: 10.5, fontWeight: 600 }}>{label}: </span>
      <span style={{ color, fontSize: 11.5, fontWeight: 900 }}>{value}</span>
    </span>
  );
}

function UnsavedDialog({ onDiscard, onCancel }) {
  return (
    <div style={{
      position: "fixed", inset: 0, background: "#00000055",
      display: "flex", alignItems: "center", justifyContent: "center",
      zIndex: 1000,
    }}>
      <div style={{
        background: T.bg, borderRadius: 14, padding: 28, width: 380, maxWidth: "90vw",
        border: `1px solid ${T.border}`,
        boxShadow: "0 20px 60px rgba(0,0,0,0.18)",
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 12 }}>
          <AlertTriangle size={20} color={T.error} />
          <span style={{ color: T.dark, fontSize: 16, fontWeight: 800 }}>बदलाव सहेजे नहीं गए</span>
        </div>
        <p style={{ color: T.dark, fontSize: 13.5, lineHeight: 1.6, marginBottom: 20 }}>
          आपने कुछ बदलाव किए हैं। क्या आप बिना सेव के बाहर निकलना चाहते हैं?
        </p>
        <div style={{ display: "flex", justifyContent: "flex-end", gap: 10 }}>
          <button onClick={onCancel} style={{
            padding: "8px 18px", borderRadius: 8, border: `1px solid ${T.border}`,
            background: "transparent", color: T.subtle, fontWeight: 600, cursor: "pointer", fontSize: 13,
          }}>रद्द करें</button>
          <button onClick={onDiscard} style={{
            padding: "8px 18px", borderRadius: 8, border: "none",
            background: T.error, color: "white", fontWeight: 700, cursor: "pointer", fontSize: 13,
          }}>बाहर निकलें</button>
        </div>
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────
/**
 * Props:
 *  title       string
 *  subtitle    string
 *  color       string   hex, defaults to T.primary
 *  initial     object   { siArmedCount, siUnarmedCount, ... }
 *  showSankhya bool
 *  onSave      fn(data) => void
 *  onBack      fn()     => void
 */
export default function ManakRankEditorPage({
  title       = "मानक संपादन",
  subtitle    = "Manak Rank Editor",
  color       = T.primary,
  initial     = {},
  showSankhya = false,
  onSave,
  onBack,
}) {
  // ── State ──────────────────────────────────────────────────────────────────
  const buildInitial = useCallback(() => {
    const v = {};
    RANKS.forEach((r) => {
      if (r.hasArmedSplit) {
        v[`${r.key}_armed`]   = initVal(initial[FIELD_KEYS[`${r.key}_armed`]],   false);
        v[`${r.key}_unarmed`] = initVal(initial[FIELD_KEYS[`${r.key}_unarmed`]], false);
      } else {
        v[r.key] = initVal(initial[FIELD_KEYS[r.key]], r.isDecimal);
      }
    });
    v.sankhya = initVal(initial.sankhya, false);
    return v;
  }, [initial]);

  const [values,  setValues]  = useState(buildInitial);
  const [changed, setChanged] = useState(false);
  const [showDialog, setShowDialog] = useState(false);
  const [saving, setSaving]   = useState(false);

  const handleChange = (key, raw) => {
    setValues((prev) => ({ ...prev, [key]: raw }));
    setChanged(true);
  };

  // ── Computed totals ────────────────────────────────────────────────────────
  const armed   = ["si","hc","const","aux"].reduce((a, k) => a + parseVal(String(values[`${k}_armed`]  ?? ""), false), 0);
  const unarmed = ["si","hc","const","aux"].reduce((a, k) => a + parseVal(String(values[`${k}_unarmed`] ?? ""), false), 0);
  const total   = armed + unarmed;
  const auxTotal = parseVal(String(values.aux_armed ?? ""), false) + parseVal(String(values.aux_unarmed ?? ""), false);
  const pacVal  = parseVal(String(values.pac ?? ""), true);

  // ── Save ──────────────────────────────────────────────────────────────────
  const handleSave = async () => {
    setSaving(true);
    const out = {
      siArmedCount:      parseVal(String(values.si_armed    ?? ""), false),
      siUnarmedCount:    parseVal(String(values.si_unarmed  ?? ""), false),
      hcArmedCount:      parseVal(String(values.hc_armed    ?? ""), false),
      hcUnarmedCount:    parseVal(String(values.hc_unarmed  ?? ""), false),
      constArmedCount:   parseVal(String(values.const_armed   ?? ""), false),
      constUnarmedCount: parseVal(String(values.const_unarmed ?? ""), false),
      auxArmedCount:     parseVal(String(values.aux_armed   ?? ""), false),
      auxUnarmedCount:   parseVal(String(values.aux_unarmed ?? ""), false),
      pacCount:          parseVal(String(values.pac         ?? ""), true),
    };
    if (showSankhya) out.sankhya = parseVal(String(values.sankhya ?? ""), false);
    try {
      await onSave?.(out);
      setChanged(false);
    } finally {
      setSaving(false);
    }
  };

  const handleBack = () => {
    if (changed) { setShowDialog(true); return; }
    onBack?.();
  };

  return (
    <>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Tiro+Devanagari+Hindi&family=Playfair+Display:wght@700;800;900&display=swap');
        * { box-sizing: border-box; }
        .mre-scroll::-webkit-scrollbar { width: 5px; }
        .mre-scroll::-webkit-scrollbar-track { background: ${T.surface}; }
        .mre-scroll::-webkit-scrollbar-thumb { background: ${T.border}; border-radius: 4px; }
        .mre-step-input:focus { outline: none; }
        .mre-save-btn:hover:not(:disabled) { filter: brightness(1.08); transform: translateY(-1px); }
        .mre-save-btn:disabled { opacity: .55; cursor: not-allowed; }
        .mre-back-btn:hover { background: rgba(255,255,255,0.12) !important; }
      `}</style>

      <div style={{
  height: "100%",
  background: T.bg,
  fontFamily: "'Tiro Devanagari Hindi', Georgia, serif",
  display: "flex", flexDirection: "column",
  overflow: "hidden",
}}>

        {/* ── AppBar ────────────────────────────────────────────────────── */}
        <header style={{
          background: color,
          padding: "0 24px",
          height: 60,
          display: "flex", alignItems: "center", gap: 14,
          boxShadow: "0 2px 12px rgba(0,0,0,0.18)",
          flexShrink: 0,
        }}>
          <button
            className="mre-back-btn"
            onClick={handleBack}
            style={{
              background: "transparent", border: "none", cursor: "pointer",
              color: "white", borderRadius: 8,
              width: 36, height: 36,
              display: "flex", alignItems: "center", justifyContent: "center",
              transition: "background .15s",
            }}
          >
            <ChevronLeft size={22} />
          </button>
          <div>
            <div style={{ color: "white", fontSize: 15, fontWeight: 800, lineHeight: 1.2 }}>{title}</div>
            <div style={{ color: "rgba(255,255,255,.7)", fontSize: 11.5 }}>{subtitle}</div>
          </div>
        </header>

        {/* ── Body ──────────────────────────────────────────────────────── */}
        <div style={{ flex: 1, overflowY: "auto", overflowX: "hidden", minHeight: 0 }} className="mre-scroll">
          <div style={{
            maxWidth: 860, margin: "0 auto", padding: "24px 20px 100px",
            display: "grid", gridTemplateColumns: "1fr 340px", gap: 20,
            alignItems: "start",
          }}>

            {/* LEFT COLUMN */}
            <div>
              <div style={{
                color: T.dark, fontSize: 13, fontWeight: 800,
                marginBottom: 14, paddingLeft: 2,
              }}>
                मानक के अनुसार व्यवस्थित पुलिस बल का विवरण
              </div>
              {RANKS.map((rank) =>
                rank.hasArmedSplit ? (
                  <SplitRankCard
                    key={rank.key}
                    rank={rank}
                    values={values}
                    onChange={handleChange}
                    accentColor={color}
                  />
                ) : (
                  <PacCard
                    key={rank.key}
                    rank={rank}
                    values={values}
                    onChange={handleChange}
                  />
                )
              )}
            </div>

            {/* RIGHT COLUMN — sticky summary + sankhya + save */}
            <div style={{ position: "sticky", top: 24 }}>

              {/* Summary card */}
              <div style={{
                borderRadius: 14,
                border: `1.5px solid ${color}4d`,
                background: color + "0d",
                padding: 18,
                marginBottom: 16,
              }}>
                <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 10 }}>
                  <Users size={22} color={color} />
                  <span style={{ color, fontSize: 20, fontWeight: 900 }}>
                    कुल कर्मचारी: {total}
                  </span>
                </div>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
                  <MiniStat icon={Gavel}       label="सशस्त्र"  value={armed}   color={T.armed}   />
                  <MiniStat icon={Shield}      label="निःशस्त्र" value={unarmed} color={T.unarmed} />
                  {auxTotal > 0 && <MiniStat icon={Users}  label="सहायक"   value={auxTotal} color={T.aux}     />}
                  {pacVal   > 0 && <MiniStat icon={ShieldCheck} label="PAC" value={pacVal}   color={T.pac}     />}
                </div>
              </div>

              {/* Sankhya field (optional) */}
              {showSankhya && (
                <div style={{ marginBottom: 16 }}>
                  <label style={{
                    display: "block", color: T.dark,
                    fontSize: 13, fontWeight: 800, marginBottom: 6,
                  }}>संख्या</label>
                  <div style={{
                    background: "white",
                    borderRadius: 10,
                    border: `1.2px solid ${T.border}80`,
                    padding: "8px 14px",
                    display: "flex", alignItems: "center", gap: 10,
                  }}>
                    <Hash size={18} color={T.primary} />
                    <input
                      type="number"
                      value={values.sankhya}
                      onChange={(e) => handleChange("sankhya", e.target.value.replace(/\D/g,"").slice(0,4))}
                      placeholder="0"
                      style={{
                        flex: 1, border: "none", outline: "none",
                        fontSize: 16, fontWeight: 800,
                        color: T.dark, background: "transparent",
                        fontFamily: "'Playfair Display', Georgia, serif",
                      }}
                    />
                  </div>
                </div>
              )}

              {/* Save button */}
              <button
                className="mre-save-btn"
                onClick={handleSave}
                disabled={saving}
                style={{
                  width: "100%", height: 50, borderRadius: 12,
                  background: color, border: "none",
                  color: "white", fontSize: 15, fontWeight: 800,
                  cursor: "pointer", display: "flex",
                  alignItems: "center", justifyContent: "center", gap: 8,
                  boxShadow: `0 4px 16px ${color}44`,
                  transition: "all .2s",
                }}
              >
                <Check size={20} />
                {saving ? "सहेज रहे हैं..." : "लागू करें"}
              </button>

              {/* Unsaved indicator */}
              {changed && (
                <div style={{
                  marginTop: 10, textAlign: "center",
                  color: T.subtle, fontSize: 11.5, fontWeight: 600,
                }}>
                  ● बिना सहेजे बदलाव हैं
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* ── Unsaved changes dialog ─────────────────────────────────────── */}
      {showDialog && (
        <UnsavedDialog
          onDiscard={() => { setShowDialog(false); onBack?.(); }}
          onCancel={() => setShowDialog(false)}
        />
      )}
    </>
  );
}