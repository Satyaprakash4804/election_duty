import { useState, useEffect, useRef, useCallback } from 'react';
import { adminApi } from '../../api/endpoints';
import apiClient from '../../api/client';

// ─── Palette (mirrors Flutter constants) ──────────────────────────────────────
const C = {
  bg:      '#FDF6E3',
  surface: '#F5E6C8',
  primary: '#8B6914',
  accent:  '#B8860B',
  dark:    '#4A3000',
  subtle:  '#AA8844',
  border:  '#D4A843',
  error:   '#C0392B',
  success: '#2D6A1E',
  info:    '#1A5276',
  armed:   '#C0392B',
  unarmed: '#27AE60',
};

const CT_LABEL = {
  'A++': 'अत्यति संवेदनशील',
  'A':   'अति संवेदनशील',
  'B':   'संवेदनशील',
  'C':   'सामान्य',
};

const PAGE_LIMIT   = 50;
const STAFF_LIMIT  = 30;
const DUTIES_LIMIT = 30;

// ─── Helpers ──────────────────────────────────────────────────────────────────
function typeColor(type) {
  switch (type) {
    case 'A++': return '#6C3483';
    case 'A':   return C.error;
    case 'B':   return C.accent;
    default:    return C.info;
  }
}
function typeAbbr(type) {
  switch (type) {
    case 'A++': return 'विशेष';
    case 'A':   return 'अति';
    case 'B':   return 'संवे';
    default:    return 'सामा';
  }
}
function isArmedVal(d) {
  return d?.isArmed === true || d?.is_armed === true || d?.is_armed === 1;
}
function hex(color, alpha) {
  // Returns rgba string from hex + alpha for inline styles
  const r = parseInt(color.slice(1,3),16);
  const g = parseInt(color.slice(3,5),16);
  const b = parseInt(color.slice(5,7),16);
  return `rgba(${r},${g},${b},${alpha})`;
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function Pill({ label, color }) {
  return (
    <span style={{
      display:'inline-flex', alignItems:'center',
      padding:'3px 10px', borderRadius:20,
      fontSize:11, fontWeight:700,
      color, background:hex(color,0.1),
      border:`1px solid ${hex(color,0.3)}`,
    }}>{label}</span>
  );
}

function TypeBadge({ type }) {
  const color = typeColor(type);
  return (
    <span style={{
      padding:'2px 8px', borderRadius:6, fontSize:12, fontWeight:900,
      color, background:hex(color,0.12), border:`1px solid ${hex(color,0.4)}`,
    }}>{type}</span>
  );
}

function ArmedChip({ isArmed }) {
  const color = isArmed ? C.armed : C.unarmed;
  const label = isArmed ? 'सशस्त्र' : 'निःशस्त्र';
  return (
    <span style={{
      display:'inline-flex', alignItems:'center', gap:3,
      padding:'2px 7px', borderRadius:6, fontSize:9, fontWeight:700,
      color, background:hex(color,0.1), border:`1px solid ${hex(color,0.35)}`,
      whiteSpace:'nowrap',
    }}>
      {isArmed ? '🛡' : '○'} {label}
    </span>
  );
}

function ArmedFilterBar({ current, totalCount, armedCount, unarmedCount, onChange }) {
  const chips = [
    { key:'all',    label:`सभी (${totalCount})`,         color:C.primary },
    { key:'armed',  label:`सशस्त्र (${armedCount})`,    color:C.armed   },
    { key:'unarmed',label:`निःशस्त्र (${unarmedCount})`, color:C.unarmed },
  ];
  return (
    <div style={{ display:'flex', alignItems:'center', gap:8, flexWrap:'wrap' }}>
      <span style={{ fontSize:11, color:C.subtle, fontWeight:700 }}>🛡 शस्त्र:</span>
      {chips.map(c => {
        const sel = current === c.key;
        return (
          <button key={c.key} onClick={() => onChange(c.key)} style={{
            padding:'4px 10px', borderRadius:20, fontSize:11, fontWeight:700, cursor:'pointer',
            color:      sel ? '#fff' : c.color,
            background: sel ? c.color : hex(c.color,0.08),
            border:     `1px solid ${sel ? c.color : hex(c.color,0.35)}`,
            transition: 'all .15s',
          }}>{c.label}</button>
        );
      })}
    </div>
  );
}

function Spinner({ size=20, color=C.primary }) {
  return (
    <div style={{
      width:size, height:size, border:`2px solid ${hex(color,0.2)}`,
      borderTop:`2px solid ${color}`, borderRadius:'50%',
      animation:'spin .7s linear infinite', display:'inline-block',
    }} />
  );
}

function InfoChip({ icon, text }) {
  if (!text || text === 'null' || text === 'undefined') return null;
  return (
    <span style={{ display:'inline-flex', alignItems:'center', gap:3, fontSize:11, color:C.subtle }}>
      <span>{icon}</span>{text}
    </span>
  );
}

// ─── Center Card ─────────────────────────────────────────────────────────────
function CenterCard({ center, onClick }) {
  const type  = center.centerType || 'C';
  const count = center.dutyCount  || 0;
  const tColor = typeColor(type);

  const [hov, setHov] = useState(false);

  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display:'flex', alignItems:'stretch', cursor:'pointer',
        background:'#fff', borderRadius:12, marginBottom:8,
        border:`1px solid ${hex(C.border, hov ? 0.8 : 0.4)}`,
        boxShadow: hov
          ? `0 6px 20px ${hex(C.primary,0.12)}`
          : `0 3px 8px ${hex(C.primary,0.05)}`,
        transition:'all .18s', overflow:'hidden',
      }}>

      {/* Type column */}
      <div style={{
        width:52, display:'flex', flexDirection:'column',
        alignItems:'center', justifyContent:'center', padding:'14px 0',
        background: hex(tColor,0.1),
        borderRight: `1px solid ${hex(tColor,0.3)}`,
      }}>
        <span style={{
          color:tColor, fontWeight:900,
          fontSize: type === 'A++' ? 12 : 20,
          lineHeight:1,
        }}>{type}</span>
        <span style={{ color:hex(tColor,0.7), fontSize:7, fontWeight:600, marginTop:2, textAlign:'center' }}>
          {typeAbbr(type)}
        </span>
      </div>

      {/* Info */}
      <div style={{ flex:1, padding:'10px 12px' }}>
        <div style={{ color:C.dark, fontWeight:700, fontSize:14, marginBottom:4 }}>
          {center.name}
        </div>
        <div style={{ display:'flex', gap:10, flexWrap:'wrap', marginBottom:2 }}>
          <InfoChip icon="🚔" text={center.thana} />
          <InfoChip icon="🏛" text={center.gpName} />
        </div>
        <InfoChip icon="📍" text={`${center.sectorName} › ${center.zoneName} › ${center.superZoneName}`} />
        {center.blockName && (
          <div style={{ marginTop:2 }}>
            <InfoChip icon="🏙" text={`ब्लॉक: ${center.blockName}`} />
          </div>
        )}
      </div>

      {/* Staff count badge */}
      <div style={{ display:'flex', alignItems:'center', padding:'0 12px' }}>
        <div style={{
          padding:'8px 10px', borderRadius:10, textAlign:'center',
          background: count > 0 ? hex(C.success,0.1) : C.surface,
          border: `1px solid ${count > 0 ? hex(C.success,0.4) : hex(C.border,0.4)}`,
        }}>
          <div style={{
            color: count > 0 ? C.success : C.subtle,
            fontSize:18, fontWeight:900, lineHeight:1,
          }}>{count}</div>
          <div style={{ color: count > 0 ? C.success : C.subtle, fontSize:10 }}>स्टाफ</div>
        </div>
      </div>
    </div>
  );
}

// ─── Duty Card ────────────────────────────────────────────────────────────────
function DutyCard({ duty, onRemove }) {
  const name    = duty.name || '';
  const rank    = duty.rank || duty.user_rank || '';
  const thana   = duty.staffThana || duty.thana || '';
  const armed   = isArmedVal(duty);

  return (
    <div style={{
      display:'flex', alignItems:'center', gap:10,
      padding:'10px 12px', borderRadius:10, marginBottom:8,
      background:'#fff',
      border:`1px solid ${armed ? hex(C.armed,0.25) : hex(C.border,0.4)}`,
    }}>
      {/* Avatar */}
      <div style={{
        width:38, height:38, borderRadius:'50%', flexShrink:0,
        display:'flex', alignItems:'center', justifyContent:'center',
        background: armed ? hex(C.armed,0.1) : C.surface,
        border: `1px solid ${armed ? hex(C.armed,0.4) : C.border}`,
        color: armed ? C.armed : C.primary,
        fontSize:15, fontWeight:800,
      }}>
        {name ? name[0].toUpperCase() : '?'}
      </div>

      {/* Details */}
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ display:'flex', alignItems:'center', gap:6, marginBottom:2 }}>
          <span style={{ color:C.dark, fontWeight:700, fontSize:13, flex:1, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>
            {name || '—'}
          </span>
          <ArmedChip isArmed={armed} />
        </div>
        <div style={{ color:C.subtle, fontSize:11 }}>
          PNO: {duty.pno || ''}  •  {duty.mobile || ''}
        </div>
        {(rank || thana) && (
          <div style={{ color:C.accent, fontSize:10, fontWeight:600 }}>
            {[rank, thana].filter(Boolean).join('  •  ')}
          </div>
        )}
      </div>

      {/* Remove */}
      <button
        onClick={onRemove}
        title="ड्यूटी हटाएं"
        style={{
          background:'none', border:'none', cursor:'pointer',
          color:C.error, fontSize:18, padding:'4px', lineHeight:1,
          borderRadius:6, flexShrink:0,
        }}>✕</button>
    </div>
  );
}

// ─── Staff Picker Row ─────────────────────────────────────────────────────────
function StaffPickerRow({ staff, selected, onToggle }) {
  const armed = isArmedVal(staff);
  const [hov, setHov] = useState(false);

  return (
    <div
      onClick={onToggle}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        display:'flex', alignItems:'center', gap:10, cursor:'pointer',
        padding:'9px 12px',
        background: selected ? hex(C.primary,0.07) : hov ? hex(C.primary,0.03) : 'transparent',
        borderBottom:`1px solid ${hex(C.border,0.25)}`,
        transition:'background .12s',
      }}>
      {/* Checkbox */}
      <div style={{
        width:24, height:24, borderRadius:'50%', flexShrink:0,
        display:'flex', alignItems:'center', justifyContent:'center',
        background: selected ? C.primary : C.surface,
        border:`1px solid ${selected ? C.primary : C.border}`,
        transition:'all .15s',
        color:'#fff', fontSize:13, fontWeight:700,
      }}>
        {selected ? '✓' : ''}
      </div>

      {/* Details */}
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ display:'flex', alignItems:'center', gap:6, marginBottom:2 }}>
          <span style={{
            color: selected ? C.primary : C.dark,
            fontSize:13, fontWeight:600, flex:1,
            overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap',
          }}>
            {staff.name}
          </span>
          <ArmedChip isArmed={armed} />
        </div>
        <div style={{ color:C.subtle, fontSize:10, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>
          PNO: {staff.pno}  •  {staff.thana || ''}  •  {staff.rank || staff.user_rank || ''}
        </div>
      </div>
    </div>
  );
}

// ─── Duties Dialog ────────────────────────────────────────────────────────────
function DutiesDialog({ center, onClose, onOpenAssign, onDutyRemoved }) {
  const [duties, setDuties]         = useState([]);
  const [page, setPage]             = useState(1);
  const [total, setTotal]           = useState(0);
  const [loading, setLoading]       = useState(false);
  const [hasMore, setHasMore]       = useState(true);
  const [armedFilter, setArmedFilter] = useState('all');
  const [toast, setToast]           = useState(null);
  const scrollRef = useRef(null);
  const loadingRef = useRef(false);
  const pageRef    = useRef(1);

  const showToast = (msg, error=false) => {
    setToast({ msg, error });
    setTimeout(() => setToast(null), 2500);
  };

  const load = useCallback(async (reset=false) => {
    if (loadingRef.current) return;
    const currentPage = reset ? 1 : pageRef.current;
    if (!reset && !hasMore) return;
    loadingRef.current = true;
    setLoading(true);
    try {
      const res = await adminApi.getDuties({
        center_id: center.id, page: currentPage, limit: DUTIES_LIMIT,
      });
      const wrapper = res?.data || {};
      const items   = wrapper.data || [];
      const tot     = wrapper.total || 0;
      const pages   = wrapper.totalPages || 1;
      setDuties(prev => reset ? items : [...prev, ...items]);
      setTotal(tot);
      setHasMore(currentPage < pages);
      pageRef.current = currentPage + 1;
      if (reset) pageRef.current = 2;
    } catch(e) { /* silent */ }
    finally { loadingRef.current = false; setLoading(false); }
  }, [center.id, hasMore]);

  useEffect(() => { load(true); }, [center.id]);

  const onScroll = (e) => {
    const el = e.target;
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 150 && !loading && hasMore) {
      load();
    }
  };

  const removeDuty = async (d) => {
    try {
      await adminApi.removeAssignment(d.id);
      onDutyRemoved();
      load(true);
      showToast('ड्यूटी हटा दी गई');
    } catch(e) {
      showToast(`त्रुटि: ${e.message}`, true);
    }
  };

  const filtered = duties.filter(d => {
    if (armedFilter === 'all') return true;
    const ia = isArmedVal(d);
    return armedFilter === 'armed' ? ia : !ia;
  });
  const armedCount   = duties.filter(d => isArmedVal(d)).length;
  const unarmedCount = duties.length - armedCount;
  const type = center.centerType || 'C';

  return (
    <Overlay onClose={onClose}>
      <div style={{
        background:C.bg, borderRadius:16,
        border:`1.2px solid ${C.border}`,
        boxShadow:`0 8px 32px ${hex(C.primary,0.18)}`,
        width:'100%', maxWidth:500, display:'flex', flexDirection:'column',
        maxHeight:'88vh', overflow:'hidden',
      }}>
        {/* Header */}
        <DialogHeader title={center.name} icon="📍" onClose={onClose} />

        {/* Meta */}
        <div style={{ padding:'10px 16px 0' }}>
          <div style={{ display:'flex', alignItems:'center', gap:8, marginBottom:8 }}>
            <TypeBadge type={type} />
            <span style={{ color:C.subtle, fontSize:12, fontWeight:600, flex:1 }}>
              {CT_LABEL[type] || type}
            </span>
            <Pill label={`${total} स्टाफ`} color={total>0 ? C.success : C.subtle} />
          </div>
          <div style={{ display:'flex', flexWrap:'wrap', gap:'4px 10px', marginBottom:8 }}>
            <InfoChip icon="🚔" text={center.thana} />
            <InfoChip icon="🏛" text={center.gpName} />
            <InfoChip icon="🗺" text={`सेक्टर: ${center.sectorName}`} />
            <InfoChip icon="🔲" text={`जोन: ${center.zoneName}`} />
            <InfoChip icon="🌐" text={`सुपर जोन: ${center.superZoneName}`} />
            {center.blockName && <InfoChip icon="🏙" text={`ब्लॉक: ${center.blockName}`} />}
            {center.busNo     && <InfoChip icon="🚌" text={`बस: ${center.busNo}`} />}
          </div>
          <ArmedFilterBar
            current={armedFilter} totalCount={duties.length}
            armedCount={armedCount} unarmedCount={unarmedCount}
            onChange={setArmedFilter}
          />
          <div style={{ height:10 }} />
        </div>

        <div style={{ height:1, background:C.border }} />

        {/* List */}
        <div style={{ flex:1, overflowY:'auto', padding:'10px 14px' }} onScroll={onScroll} ref={scrollRef}>
          {loading && duties.length === 0 ? (
            <div style={{ display:'flex', justifyContent:'center', padding:40 }}><Spinner /></div>
          ) : filtered.length === 0 ? (
            <div style={{ textAlign:'center', padding:40, color:C.subtle }}>
              <div style={{ fontSize:36, marginBottom:8 }}>👥</div>
              <div style={{ fontSize:13 }}>
                {duties.length === 0 ? 'इस बूथ पर कोई स्टाफ नहीं'
                  : armedFilter === 'armed' ? 'कोई सशस्त्र स्टाफ नहीं'
                  : 'कोई निःशस्त्र स्टाफ नहीं'}
              </div>
            </div>
          ) : (
            <>
              {filtered.map(d => (
                <DutyCard key={d.id} duty={d} onRemove={() => removeDuty(d)} />
              ))}
              {hasMore && (
                <div style={{ display:'flex', justifyContent:'center', padding:12 }}>
                  <Spinner size={18} />
                </div>
              )}
            </>
          )}
        </div>

        {/* Footer */}
        <div style={{
          padding:14, borderTop:`1px solid ${C.border}`,
          display:'flex', gap:12,
        }}>
          <button onClick={onClose} style={outlineBtn}>बंद करें</button>
          <button onClick={() => { onClose(); onOpenAssign(); }} style={primaryBtn}>
            ➕ स्टाफ जोड़ें
          </button>
        </div>

        {/* Toast */}
        {toast && <Toast msg={toast.msg} error={toast.error} />}
      </div>
    </Overlay>
  );
}

// ─── Assign Dialog ─────────────────────────────────────────────────────────────
function AssignDialog({ center, onClose, onAssigned }) {
  const [staff, setStaff]           = useState([]);
  const [staffPage, setStaffPage]   = useState(1);
  const [staffTotal, setStaffTotal] = useState(0);
  const [staffLoading, setStaffLoading] = useState(false);
  const [staffHasMore, setStaffHasMore] = useState(true);
  const [staffQ, setStaffQ]         = useState('');
  const [selected, setSelected]     = useState(new Set());
  const [busNo, setBusNo]           = useState(center.busNo || '');
  const [saving, setSaving]         = useState(false);
  const [armedFilter, setArmedFilter] = useState('all');
  const [toast, setToast]           = useState(null);

  const searchRef  = useRef('');
  const loadingRef = useRef(false);
  const pageRef    = useRef(1);
  const debounce   = useRef(null);

  const showToast = (msg, error=false) => {
    setToast({ msg, error });
    setTimeout(() => setToast(null), 2500);
  };

  const loadStaff = useCallback(async (reset=false, q=searchRef.current) => {
    if (loadingRef.current) return;
    const currentPage = reset ? 1 : pageRef.current;
    loadingRef.current = true;
    setStaffLoading(true);
    try {
      const res = await adminApi.getStaff({
        assigned:'no', page:currentPage, limit:STAFF_LIMIT, q,
      });
      const wrapper = res?.data || {};
      const items   = wrapper.data || [];
      const tot     = wrapper.total || 0;
      const pages   = wrapper.totalPages || 1;
      setStaff(prev => reset ? items : [...prev, ...items]);
      setStaffTotal(tot);
      setStaffHasMore(currentPage < pages);
      pageRef.current = reset ? 2 : currentPage + 1;
    } catch(e) { /* silent */ }
    finally { loadingRef.current = false; setStaffLoading(false); }
  }, []);

  useEffect(() => { loadStaff(true, ''); }, []);

  const onSearchChange = (val) => {
    setStaffQ(val);
    searchRef.current = val;
    clearTimeout(debounce.current);
    debounce.current = setTimeout(() => loadStaff(true, val), 300);
  };

  const onScroll = (e) => {
    const el = e.target;
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 150 && !staffLoading && staffHasMore) {
      loadStaff(false, searchRef.current);
    }
  };

  const toggleSelect = (id) => {
    setSelected(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const assign = async () => {
    if (!selected.size || saving) return;
    setSaving(true);
    try {
      const ids = [...selected];
      if (ids.length === 1) {
        await adminApi.assignDuty({ staffId: ids[0], centerId: center.id, busNo });
      } else {
        // bulk assign — use the staffApi bulk endpoint
        await apiClient.post('/admin/staff/bulk-assign', { staffIds: ids, centerId: center.id, busNo });
      }
      onAssigned();
      onClose();
    } catch(e) {
      showToast(`त्रुटि: ${e.message}`, true);
      setSaving(false);
    }
  };

  const filteredStaff = staff.filter(s => {
    if (armedFilter === 'all') return true;
    const ia = isArmedVal(s);
    return armedFilter === 'armed' ? ia : !ia;
  });
  const armedCount   = staff.filter(s => isArmedVal(s)).length;
  const unarmedCount = staff.length - armedCount;

  return (
    <Overlay onClose={onClose}>
      <div style={{
        background:C.bg, borderRadius:16,
        border:`1.2px solid ${C.border}`,
        boxShadow:`0 8px 32px ${hex(C.primary,0.18)}`,
        width:'100%', maxWidth:520, display:'flex', flexDirection:'column',
        maxHeight:'90vh', overflow:'hidden',
      }}>
        <DialogHeader title="स्टाफ असाइन करें" icon="➕" onClose={onClose} />

        {/* Center strip */}
        <div style={{ padding:'10px 16px', background:hex(C.surface,0.5) }}>
          <div style={{ display:'flex', alignItems:'center', gap:8 }}>
            <TypeBadge type={center.centerType || 'C'} />
            <div style={{ flex:1, minWidth:0 }}>
              <div style={{ color:C.dark, fontWeight:700, fontSize:13, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>
                {center.name}
              </div>
              <div style={{ color:C.subtle, fontSize:11, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>
                {center.thana}  •  {center.gpName}  •  {center.sectorName}
              </div>
            </div>
            {selected.size > 0 && (
              <Pill label={`${selected.size} चुने`} color={C.primary} />
            )}
          </div>
        </div>

        <div style={{ height:1, background:C.border }} />

        {/* Search + filter */}
        <div style={{ padding:'10px 14px 0' }}>
          <SearchInput
            value={staffQ}
            onChange={onSearchChange}
            placeholder={`नाम, PNO, थाना से खोजें... (${staffTotal} उपलब्ध)`}
          />
          <div style={{ height:10 }} />
          <ArmedFilterBar
            current={armedFilter} totalCount={staff.length}
            armedCount={armedCount} unarmedCount={unarmedCount}
            onChange={setArmedFilter}
          />
          <div style={{ height:8 }} />
        </div>

        {/* Staff list */}
        <div style={{ flex:1, overflowY:'auto' }} onScroll={onScroll}>
          {staffLoading && staff.length === 0 ? (
            <div style={{ display:'flex', justifyContent:'center', padding:40 }}><Spinner /></div>
          ) : filteredStaff.length === 0 ? (
            <div style={{ textAlign:'center', padding:40, color:C.subtle, fontSize:13 }}>
              <div style={{ fontSize:36, marginBottom:8 }}>👥</div>
              {staff.length === 0 ? 'सभी स्टाफ पहले से असाइन हैं'
                : staffQ ? `"${staffQ}" नहीं मिला`
                : armedFilter === 'armed' ? 'कोई सशस्त्र स्टाफ उपलब्ध नहीं'
                : 'कोई निःशस्त्र स्टाफ उपलब्ध नहीं'}
            </div>
          ) : (
            <>
              {filteredStaff.map(s => (
                <StaffPickerRow
                  key={s.id} staff={s}
                  selected={selected.has(s.id)}
                  onToggle={() => toggleSelect(s.id)}
                />
              ))}
              {staffHasMore && (
                <div style={{ display:'flex', justifyContent:'center', padding:10 }}>
                  <Spinner size={16} />
                </div>
              )}
            </>
          )}
        </div>

        {/* Footer */}
        <div style={{ padding:'10px 14px 14px', borderTop:`1px solid ${C.border}` }}>
          {/* Bus number */}
          <div style={{ position:'relative', marginBottom:10 }}>
            <span style={{
              position:'absolute', left:12, top:'50%', transform:'translateY(-50%)',
              fontSize:16, pointerEvents:'none',
            }}>🚌</span>
            <input
              value={busNo}
              onChange={e => setBusNo(e.target.value)}
              placeholder="बस संख्या (वैकल्पिक)"
              style={{ ...fieldStyle, paddingLeft:36 }}
            />
          </div>
          <div style={{ display:'flex', gap:12 }}>
            <button onClick={onClose} style={outlineBtn}>रद्द</button>
            {selected.size > 0 && (
              <button onClick={assign} disabled={saving} style={{ ...primaryBtn, flex:1 }}>
                {saving
                  ? <Spinner size={16} color="#fff" />
                  : selected.size === 1 ? 'असाइन करें' : `${selected.size} असाइन करें`}
              </button>
            )}
          </div>
        </div>

        {toast && <Toast msg={toast.msg} error={toast.error} />}
      </div>
    </Overlay>
  );
}

// ─── Overlay ──────────────────────────────────────────────────────────────────
function Overlay({ children, onClose }) {
  useEffect(() => {
    const esc = (e) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', esc);
    return () => document.removeEventListener('keydown', esc);
  }, [onClose]);

  return (
    <div
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{
        position:'fixed', inset:0, zIndex:1000,
        background:'rgba(74,48,0,0.45)', backdropFilter:'blur(3px)',
        display:'flex', alignItems:'center', justifyContent:'center',
        padding:16,
      }}>
      {children}
    </div>
  );
}

// ─── Dialog Header ────────────────────────────────────────────────────────────
function DialogHeader({ title, icon, onClose }) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:10,
      padding:'14px 16px 14px 16px',
      background: C.dark,
      borderRadius:'16px 16px 0 0',
    }}>
      <div style={{
        padding:6, borderRadius:7,
        background: hex(C.primary,0.25),
        fontSize:16,
      }}>{icon}</div>
      <span style={{
        color:'#fff', fontWeight:700, fontSize:15, flex:1,
        overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap',
      }}>{title}</span>
      {onClose && (
        <button onClick={onClose} style={{
          background:'none', border:'none', cursor:'pointer',
          color:'rgba(255,255,255,0.6)', fontSize:20, lineHeight:1, padding:4,
        }}>✕</button>
      )}
    </div>
  );
}

// ─── SearchInput ──────────────────────────────────────────────────────────────
function SearchInput({ value, onChange, placeholder }) {
  return (
    <div style={{ position:'relative' }}>
      <span style={{
        position:'absolute', left:12, top:'50%', transform:'translateY(-50%)',
        color:C.subtle, fontSize:16, pointerEvents:'none',
      }}>🔍</span>
      <input
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        style={{ ...fieldStyle, paddingLeft:36, paddingRight: value ? 36 : 12 }}
      />
      {value && (
        <button
          onClick={() => onChange('')}
          style={{
            position:'absolute', right:10, top:'50%', transform:'translateY(-50%)',
            background:'none', border:'none', cursor:'pointer',
            color:C.subtle, fontSize:14, lineHeight:1, padding:2,
          }}>✕</button>
      )}
    </div>
  );
}

// ─── Toast ────────────────────────────────────────────────────────────────────
function Toast({ msg, error }) {
  return (
    <div style={{
      position:'absolute', bottom:80, left:'50%', transform:'translateX(-50%)',
      background: error ? C.error : C.success,
      color:'#fff', borderRadius:10, padding:'8px 16px', fontSize:13,
      fontWeight:600, whiteSpace:'nowrap', zIndex:10,
      boxShadow:`0 4px 12px ${hex(error ? C.error : C.success, 0.35)}`,
    }}>{msg}</div>
  );
}

// ─── Shared styles ────────────────────────────────────────────────────────────
const fieldStyle = {
  width:'100%', background:'#fff',
  border:`1.2px solid ${C.border}`, borderRadius:10,
  padding:'10px 12px', color:C.dark, fontSize:13,
  outline:'none', fontFamily:'inherit', boxSizing:'border-box',
};

const primaryBtn = {
  display:'inline-flex', alignItems:'center', justifyContent:'center', gap:6,
  padding:'11px 18px', borderRadius:10, fontWeight:700, fontSize:13,
  color:'#fff', background:C.primary, border:'none', cursor:'pointer',
  flex:1, transition:'opacity .15s',
};

const outlineBtn = {
  display:'inline-flex', alignItems:'center', justifyContent:'center',
  padding:'11px 18px', borderRadius:10, fontWeight:600, fontSize:13,
  color:C.subtle, background:'transparent',
  border:`1px solid ${C.border}`, cursor:'pointer', flex:1,
};

// ══════════════════════════════════════════════════════════════════════════════
//  BoothPage — Main Export
// ══════════════════════════════════════════════════════════════════════════════
export default function BoothPage() {
  const [centers, setCenters]     = useState([]);
  const [page, setPage]           = useState(1);
  const [total, setTotal]         = useState(0);
  const [loading, setLoading]     = useState(false);
  const [hasMore, setHasMore]     = useState(true);
  const [q, setQ]                 = useState('');
  const [dutiesCenter, setDutiesCenter] = useState(null); // dialog state
  const [assignCenter, setAssignCenter] = useState(null); // assign dialog
  const [toast, setToast]         = useState(null);

  const loadingRef = useRef(false);
  const pageRef    = useRef(1);
  const qRef       = useRef('');
  const debounce   = useRef(null);
  const scrollRef  = useRef(null);

  const showToast = (msg, error=false) => {
    setToast({ msg, error });
    setTimeout(() => setToast(null), 2500);
  };

  const loadCenters = useCallback(async (reset=false) => {
    if (loadingRef.current) return;
    const currentPage = reset ? 1 : pageRef.current;
    if (!reset && !hasMore && !reset) return;
    loadingRef.current = true;
    setLoading(true);
    try {
      const res = await adminApi.getCenters({
        page: currentPage, limit: PAGE_LIMIT, q: qRef.current,
      });
      const wrapper = res?.data || {};
      const items   = wrapper.data || [];
      const tot     = wrapper.total || 0;
      const pages   = wrapper.totalPages || 1;
      setCenters(prev => reset ? items : [...prev, ...items]);
      setTotal(tot);
      setHasMore(currentPage < pages);
      pageRef.current = reset ? 2 : currentPage + 1;
    } catch(e) {
      showToast(`लोड विफल: ${e.message}`, true);
    } finally {
      loadingRef.current = false;
      setLoading(false);
    }
  }, [hasMore]);

  useEffect(() => { loadCenters(true); }, []);

  const onSearchChange = (val) => {
    setQ(val);
    qRef.current = val;
    clearTimeout(debounce.current);
    debounce.current = setTimeout(() => {
      pageRef.current = 1;
      setCenters([]);
      setHasMore(true);
      loadCenters(true);
    }, 350);
  };

  const onScroll = (e) => {
    const el = e.target;
    if (el.scrollHeight - el.scrollTop - el.clientHeight < 300 && !loading && hasMore) {
      loadCenters(false);
    }
  };

  return (
    <>
      {/* Inject keyframes */}
      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>

      <div style={{
        display:'flex', flexDirection:'column',
        height:'100%', background:C.bg, fontFamily:"'Tiro Devanagari Hindi', Georgia, serif",
      }}>
        {/* Search bar */}
        <div style={{ background:C.surface, padding:12 }}>
          <SearchInput value={q} onChange={onSearchChange}
            placeholder="नाम, थाना, GP, सेक्टर, जोन से खोजें..." />
        </div>

        {/* Stats row */}
        <div style={{
          background:C.bg, padding:'8px 16px',
          display:'flex', alignItems:'center', gap:8,
          borderBottom:`1px solid ${hex(C.border,0.3)}`,
        }}>
          <Pill label={`${total} बूथ`} color={C.primary} />
          <div style={{ flex:1 }} />
          {loading && centers.length > 0 && <Spinner size={14} />}
          <button
            onClick={() => { pageRef.current=1; setCenters([]); setHasMore(true); loadCenters(true); }}
            title="Refresh"
            style={{
              background:'none', border:'none', cursor:'pointer',
              fontSize:16, color:C.subtle, padding:4, lineHeight:1,
            }}>↻</button>
        </div>

        {/* List */}
        <div
          ref={scrollRef}
          onScroll={onScroll}
          style={{ flex:1, overflowY:'auto', padding:'10px 12px 80px' }}>
          {centers.length === 0 && loading ? (
            <div style={{ display:'flex', justifyContent:'center', padding:60 }}>
              <Spinner size={32} />
            </div>
          ) : centers.length === 0 ? (
            <div style={{ textAlign:'center', padding:60, color:C.subtle }}>
              <div style={{ fontSize:48, marginBottom:12, opacity:.4 }}>📍</div>
              <div style={{ fontSize:14 }}>
                {q ? `"${q}" के लिए कोई बूथ नहीं` : 'कोई बूथ नहीं मिला'}
              </div>
            </div>
          ) : (
            <>
              {centers.map(c => (
                <CenterCard
                  key={c.id}
                  center={c}
                  onClick={() => setDutiesCenter(c)}
                />
              ))}
              {hasMore && loading && (
                <div style={{ display:'flex', justifyContent:'center', padding:16 }}>
                  <Spinner size={22} />
                </div>
              )}
            </>
          )}
        </div>

        {/* Global toast */}
        {toast && (
          <div style={{
            position:'fixed', bottom:24, left:'50%', transform:'translateX(-50%)',
            background: toast.error ? C.error : C.success,
            color:'#fff', borderRadius:10, padding:'8px 18px',
            fontSize:13, fontWeight:600, zIndex:2000,
            boxShadow:`0 4px 16px ${hex(toast.error ? C.error : C.success, 0.4)}`,
          }}>{toast.msg}</div>
        )}
      </div>

      {/* Duties Dialog */}
      {dutiesCenter && (
        <DutiesDialog
          center={dutiesCenter}
          onClose={() => setDutiesCenter(null)}
          onOpenAssign={() => setAssignCenter(dutiesCenter)}
          onDutyRemoved={() => loadCenters(true)}
        />
      )}

      {/* Assign Dialog */}
      {assignCenter && (
        <AssignDialog
          center={assignCenter}
          onClose={() => setAssignCenter(null)}
          onAssigned={() => {
            setAssignCenter(null);
            loadCenters(true);
          }}
        />
      )}
    </>
  );
}