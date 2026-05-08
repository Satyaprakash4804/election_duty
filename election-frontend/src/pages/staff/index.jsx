// staff/index.js

import { useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import toast, { Toaster } from 'react-hot-toast';
import {
  LayoutDashboard, MapPin, Users, Badge, Map, Layers, Grid3x3,
  Vote, Building2, Home, Globe, Hash, Briefcase, Phone,
  Shield, User, Lock, Eye, EyeOff, Save, Search, Bus,
  Check, X, RefreshCw, LogOut, History, Printer, FileText,
  AlertCircle, CheckCircle2, Loader2, Info, ClipboardList,
  Navigation, Menu, ChevronRight, Sparkles, Calendar, Clock,
  Sun, Moon, Bell, Star, ShieldCheck, MapPinned, Building,
  TicketCheck, Ticket, Award, Megaphone, Eye as EyeIcon,
} from 'lucide-react';
import apiClient from '../../api/client';
import { printDutyCard, toAdminShape } from '../../components/DutyCardPrint';

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════
const RANK_MAP = {
  constable: 'आरक्षी', 'head constable': 'मुख्य आरक्षी',
  si: 'उप निरीक्षक', 'sub inspector': 'उप निरीक्षक',
  inspector: 'निरीक्षक', asi: 'सहायक उप निरीक्षक',
  'assistant sub inspector': 'सहायक उप निरीक्षक',
  dsp: 'उपाधीक्षक', asp: 'सहा0 पुलिस अधीक्षक',
  sp: 'पुलिस अधीक्षक',
  'circle officer': 'क्षेत्राधिकारी', co: 'क्षेत्राधिकारी',
};

const CENTER_TYPE_MAP = {
  'a++': 'अत्यति संवेदनशील', a: 'अति संवेदनशील',
  b: 'संवेदनशील', c: 'सामान्य',
};

const DISTRICT_DUTY_LABELS = {
  cluster_mobile: 'क्लस्टर मोबाईल',
  thana_mobile: 'थाना मोबाईल',
  thana_reserve: 'थाना रिजर्व',
  thana_extra_mobile: 'थाना अतिरिक्त मोबाईल',
  sector_pol_mag_mobile: 'सैक्टर पुलिस/मजिस्ट्रेट मोबाईल',
  zonal_pol_mag_mobile: 'जोनल पुलिस/मजिस्ट्रेट मोबाईल',
  sdm_co_mobile: 'एसडीएम/सीओ मोबाईल',
  chowki_mobile: 'चौकी मोबाईल',
  barrier_picket: 'बैरियर/पिकैट',
  evm_security: 'ईवीएम सुरक्षा',
  adm_sp_mobile: 'एडीएम/एसपी मोबाईल',
  dm_sp_mobile: 'डीएम/एसपी मोबाईल',
  observer_security: 'पर्यवेक्षक सुरक्षा',
  hq_reserve: 'मुख्यालय रिजर्व',
};


const HINDI_MONTHS = ['', 'जनवरी', 'फरवरी', 'मार्च', 'अप्रैल', 'मई', 'जून',
  'जुलाई', 'अगस्त', 'सितम्बर', 'अक्टूबर', 'नवम्बर', 'दिसम्बर'];

const rh = (val) => RANK_MAP[(val || '').toString().toLowerCase()] || val || '—';
const v = (x) => (!x || x.toString().trim() === '') ? '—' : x.toString();
const ct = (x) => CENTER_TYPE_MAP[(x || '').toString().toLowerCase()] || x || '—';
const dutyLabel = (key) => DISTRICT_DUTY_LABELS[key] || (key ? key.replace(/_/g, ' ') : '—');

const formatHindiDate = (d) => {
  if (!d) return '—';
  try {
    const dt = new Date(d);
    if (isNaN(dt)) return d;
    return `${dt.getDate()} ${HINDI_MONTHS[dt.getMonth() + 1]} ${dt.getFullYear()}`;
  } catch { return d; }
};

const typeColorClass = (t) => {
  switch ((t || '').toUpperCase()) {
    case 'A++': return { bg: 'bg-purple-600', text: 'text-purple-600', light: 'bg-purple-50', border: 'border-purple-200' };
    case 'A': return { bg: 'bg-red-600', text: 'text-red-600', light: 'bg-red-50', border: 'border-red-200' };
    case 'B': return { bg: 'bg-amber-600', text: 'text-amber-600', light: 'bg-amber-50', border: 'border-amber-200' };
    default: return { bg: 'bg-blue-600', text: 'text-blue-600', light: 'bg-blue-50', border: 'border-blue-200' };
  }
};

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════════

function SectionCard({ icon: IconCmp, title, children, accent = 'amber', actions }) {
  const accents = {
    amber: 'from-amber-50 to-yellow-50 border-amber-200',
    purple: 'from-purple-50 to-fuchsia-50 border-purple-200',
    blue: 'from-blue-50 to-sky-50 border-blue-200',
    green: 'from-emerald-50 to-green-50 border-emerald-200',
  };
  return (
    <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden mb-4 hover:shadow-md transition-shadow">
      <div className={`flex items-center justify-between gap-3 px-5 py-3.5 bg-gradient-to-r ${accents[accent]} border-b`}>
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-white shadow-sm flex items-center justify-center">
            <IconCmp className="w-4 h-4 text-amber-700" />
          </div>
          <h3 className="font-bold text-slate-800 text-sm tracking-wide">{title}</h3>
        </div>
        {actions}
      </div>
      <div className="p-5">{children}</div>
    </div>
  );
}

function InfoTile({ icon: IconCmp, label, value }) {
  if (!value || value === '—' || value === '') return null;
  return (
    <div className="flex items-start gap-3 py-2.5 group">
      <div className="w-8 h-8 rounded-lg bg-amber-50 group-hover:bg-amber-100 flex items-center justify-center flex-shrink-0 transition-colors">
        <IconCmp className="w-3.5 h-3.5 text-amber-700" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-[10px] font-semibold uppercase tracking-wider text-slate-500 mb-0.5">{label}</p>
        <p className="text-sm font-semibold text-slate-800 break-words">{value}</p>
      </div>
    </div>
  );
}

function StatCard({ icon: IconCmp, label, value, color = 'amber', trend }) {
  const colors = {
    amber: 'from-amber-500 to-yellow-600 shadow-amber-200',
    blue: 'from-blue-500 to-sky-600 shadow-blue-200',
    green: 'from-emerald-500 to-green-600 shadow-emerald-200',
    red: 'from-red-500 to-rose-600 shadow-red-200',
    purple: 'from-purple-500 to-fuchsia-600 shadow-purple-200',
    orange: 'from-orange-500 to-red-500 shadow-orange-200',
    indigo: 'from-indigo-500 to-blue-600 shadow-indigo-200',
  };
  return (
    <div className="group bg-white rounded-2xl border border-slate-200 p-4 hover:shadow-lg hover:-translate-y-0.5 transition-all duration-200">
      <div className={`w-11 h-11 rounded-xl bg-gradient-to-br ${colors[color]} shadow-md flex items-center justify-center mb-3 group-hover:scale-105 transition-transform`}>
        <IconCmp className="w-5 h-5 text-white" />
      </div>
      <p className="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1">{label}</p>
      <p className="text-base font-extrabold text-slate-800 truncate" title={value}>{value}</p>
    </div>
  );
}

function HeroBadge({ icon: IconCmp, label }) {
  return (
    <div className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 bg-white/10 backdrop-blur-sm border border-white/20">
      <IconCmp className="w-3 h-3 text-white/70" />
      <span className="text-xs text-white/90 font-medium">{label}</span>
    </div>
  );
}

function HeroCard({ user, duty, subtitle, noDuty }) {
  return (
    <div className="relative overflow-hidden rounded-2xl p-6 mb-5 bg-gradient-to-br from-amber-700 via-amber-800 to-yellow-900 shadow-xl shadow-amber-900/20">
      {/* Decorative elements */}
      <div className="absolute -top-12 -right-12 w-48 h-48 rounded-full bg-amber-400/20 blur-2xl" />
      <div className="absolute -bottom-8 -left-8 w-40 h-40 rounded-full bg-yellow-500/10 blur-2xl" />

      <div className="relative z-10">
        <div className="flex items-center gap-4 mb-4">
          <div className="w-14 h-14 rounded-2xl bg-white/15 backdrop-blur-sm border border-white/30 flex items-center justify-center flex-shrink-0">
            <User className="w-7 h-7 text-white" strokeWidth={2} />
          </div>
          <div className="flex-1 min-w-0">
            {subtitle && (
              <p className="text-[10px] font-bold tracking-widest uppercase text-amber-200 mb-0.5">
                {subtitle}
              </p>
            )}
            <p className="text-xl font-extrabold text-white truncate">{user?.name || '—'}</p>
            <p className="text-xs text-amber-100/70 mt-0.5">PNO: {user?.pno || '—'}</p>
          </div>
        </div>

        <div className="h-px bg-white/15 mb-4" />

        <div className="flex flex-wrap gap-2">
          {user?.thana && <HeroBadge icon={Shield} label={user.thana} />}
          {user?.district && <HeroBadge icon={Building2} label={user.district} />}
          <HeroBadge icon={Star} label={rh(user?.rank || user?.user_rank)} />
        </div>

        {!noDuty && duty?.centerName && (
          <>
            <div className="h-px bg-white/15 my-4" />
            <div className="flex items-center gap-2">
              <Vote className="w-3.5 h-3.5 text-amber-200/70" />
              <p className="text-xs text-amber-50/90 truncate">
                ड्यूटी: {duty.centerName || duty.sectorName || duty.zoneName || duty.superZoneName || '—'}
              </p>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function NavButton({ icon: IconCmp, label, color = 'amber', onClick, fullWidth = true }) {
  const colors = {
    amber: 'bg-gradient-to-r from-amber-600 to-amber-700 hover:from-amber-700 hover:to-amber-800 shadow-amber-500/30',
    dark: 'bg-gradient-to-r from-slate-800 to-slate-900 hover:from-slate-900 hover:to-black shadow-slate-700/30',
    purple: 'bg-gradient-to-r from-purple-600 to-fuchsia-700 hover:from-purple-700 hover:to-fuchsia-800 shadow-purple-500/30',
  };
  return (
    <button
      onClick={onClick}
      className={`${fullWidth ? 'w-full' : ''} ${colors[color]} text-white py-3.5 px-6 rounded-xl font-bold text-sm flex items-center justify-center gap-2.5 shadow-lg hover:shadow-xl transition-all duration-200 hover:-translate-y-0.5 active:translate-y-0 mb-3`}
    >
      <IconCmp className="w-4 h-4" />
      {label}
    </button>
  );
}

function OfficerCard({ label, officers = [] }) {
  return (
    <SectionCard icon={ShieldCheck} title={label}>
      <div className="space-y-2">
        {officers.map((o, i) => (
          <div key={i} className="flex items-center gap-3 py-3 px-3 rounded-xl hover:bg-amber-50/50 transition-colors group">
            <div className="w-11 h-11 rounded-full bg-gradient-to-br from-amber-100 to-yellow-100 border border-amber-200 flex items-center justify-center flex-shrink-0">
              <User className="w-5 h-5 text-amber-700" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-bold text-slate-800 text-sm truncate">{v(o.name)}</p>
              <p className="text-[11px] text-slate-500 mt-0.5">
                {rh(o.user_rank || o.rank)} · PNO: {v(o.pno)}
              </p>
            </div>
            {o.mobile && (
              <a
                href={`tel:${o.mobile}`}
                className="w-10 h-10 rounded-xl bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 flex items-center justify-center transition-colors group-hover:scale-105"
                title={o.mobile}
              >
                <Phone className="w-4 h-4 text-emerald-700" />
              </a>
            )}
          </div>
        ))}
      </div>
    </SectionCard>
  );
}

function NoDutyState({ message = 'अभी तक ड्यूटी नहीं सौंपी गई', sub = 'व्यवस्थापक द्वारा ड्यूटी सौंपे जाने पर यहाँ दिखेगी।' }) {
  return (
    <div className="flex items-center justify-center py-16">
      <div className="bg-white rounded-3xl p-10 max-w-md w-full shadow-sm border border-slate-200 text-center">
        <div className="w-20 h-20 mx-auto rounded-full bg-gradient-to-br from-amber-100 to-yellow-100 border border-amber-200 flex items-center justify-center mb-5">
          <MapPinned className="w-9 h-9 text-amber-700" />
        </div>
        <p className="font-extrabold text-lg text-slate-800 mb-2">{message}</p>
        <p className="text-sm text-slate-500">{sub}</p>
      </div>
    </div>
  );
}

function LoadingSpinner() {
  return (
    <div className="flex items-center justify-center py-24">
      <div className="flex flex-col items-center gap-3">
        <Loader2 className="w-10 h-10 text-amber-600 animate-spin" />
        <p className="text-sm text-slate-500 font-medium">लोड हो रहा है...</p>
      </div>
    </div>
  );
}

function ErrorState({ error, onRetry }) {
  return (
    <div className="flex flex-col items-center justify-center py-20 px-6 text-center">
      <div className="w-20 h-20 rounded-full bg-red-50 border border-red-200 flex items-center justify-center mb-5">
        <AlertCircle className="w-10 h-10 text-red-600" />
      </div>
      <p className="font-extrabold text-lg text-slate-800 mb-2">डेटा लोड करने में त्रुटि</p>
      <p className="text-sm text-slate-500 mb-6 max-w-md">{error}</p>
      <button
        onClick={onRetry}
        className="bg-gradient-to-r from-amber-600 to-amber-700 hover:from-amber-700 hover:to-amber-800 text-white px-6 py-3 rounded-xl font-bold text-sm flex items-center gap-2 shadow-lg shadow-amber-500/30 transition-all hover:-translate-y-0.5"
      >
        <RefreshCw className="w-4 h-4" />
        पुनः प्रयास करें
      </button>
    </div>
  );
}

function PreviewRow({ label, value }) {
  const display = (!value || value.toString().trim() === '') ? '—' : value.toString();
  return (
    <div className="flex items-center justify-between py-2.5 border-b border-slate-100 last:border-0">
      <span className="text-xs text-slate-500 font-medium">{label}</span>
      <span className="text-sm font-bold text-slate-800 text-right ml-4 truncate max-w-[60%]" title={display}>
        {display}
      </span>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ELECTION CONFIG BANNER
// ═══════════════════════════════════════════════════════════════════════════════
function ElectionConfigBanner({ electionConfig }) {
  if (!electionConfig) return null;
  const ec = electionConfig;
  const name = ec.election_name || '';
  const type = ec.election_type || '';
  const phase = ec.phase || '';
  const pratah = ec.pratah_samay || '';
  const saya = ec.saya_samay || '';
  const date = formatHindiDate(ec.election_date);

  return (
    <div className="relative overflow-hidden bg-gradient-to-br from-indigo-700 via-indigo-800 to-blue-900 rounded-2xl p-5 mb-5 shadow-lg shadow-indigo-500/20">
      <div className="absolute -top-8 -right-8 w-40 h-40 rounded-full bg-indigo-400/20 blur-2xl" />
      <div className="relative z-10">
        <div className="flex items-start justify-between gap-3 mb-4">
          <div className="flex items-center gap-3 min-w-0 flex-1">
            <div className="w-10 h-10 rounded-xl bg-white/15 backdrop-blur-sm flex items-center justify-center flex-shrink-0">
              <Vote className="w-5 h-5 text-white" />
            </div>
            <div className="min-w-0 flex-1">
              {name && <p className="text-white font-extrabold text-sm truncate">{name}</p>}
              {type && <p className="text-indigo-200 text-[11px]">{type}</p>}
            </div>
          </div>
          {phase && (
            <span className="flex-shrink-0 inline-flex items-center px-2.5 py-1 rounded-full bg-white/15 border border-white/20 text-white text-[10px] font-bold">
              चरण {phase}
            </span>
          )}
        </div>

        <div className="h-px bg-white/15 mb-3" />

        <div className="grid grid-cols-3 gap-2">
          <ElectionInfoChip icon={Calendar} label="मतदान तिथि" value={date} />
          {pratah && <ElectionInfoChip icon={Sun} label="प्रातः" value={pratah} />}
          {saya && <ElectionInfoChip icon={Moon} label="सायं" value={saya} />}
        </div>
      </div>
    </div>
  );
}

function ElectionInfoChip({ icon: IconCmp, label, value }) {
  return (
    <div className="bg-white/10 backdrop-blur-sm rounded-lg px-2.5 py-2 flex items-center gap-2 min-w-0">
      <IconCmp className="w-3.5 h-3.5 text-indigo-200 flex-shrink-0" />
      <div className="min-w-0">
        <p className="text-[9px] text-indigo-200 leading-tight">{label}</p>
        <p className="text-[11px] text-white font-bold truncate">{value}</p>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAFF ROW (shared)
// ═══════════════════════════════════════════════════════════════════════════════
function StaffRow({ index, total, staff, armed }) {
  return (
    <div className={`flex items-center gap-3 py-3 px-2 rounded-lg hover:bg-amber-50/40 transition-colors ${index < total - 1 ? 'border-b border-slate-100' : ''}`}>
      <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 font-extrabold text-xs border ${armed ? 'bg-emerald-50 border-emerald-200 text-emerald-700' : 'bg-slate-50 border-slate-200 text-slate-700'}`}>
        {index + 1}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-bold text-sm text-slate-800 truncate">{v(staff.name)}</p>
        <p className="text-[11px] text-slate-500 mt-0.5">{v(staff.pno)} · {v(staff.thana)}</p>
        <div className="flex items-center gap-2 mt-1">
          <span className="text-[10px] font-semibold text-amber-700">{rh(staff.user_rank || staff.rank)}</span>
          <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded ${armed ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-100 text-slate-600'}`}>
            {armed ? 'सशस्त्र' : 'निःशस्त्र'}
          </span>
        </div>
      </div>
      {staff.mobile && (
        <a
          href={`tel:${staff.mobile}`}
          className="w-10 h-10 rounded-xl bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 flex items-center justify-center transition-all hover:scale-105"
        >
          <Phone className="w-4 h-4 text-emerald-700" />
        </a>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOOTH SECTIONS
// ═══════════════════════════════════════════════════════════════════════════════
function BoothOverview({ duty, user, onGoToDutyCard, onOpenMap }) {
  if (!duty) return <NoDutyState />;
  return (
    <>
      <HeroCard user={user} duty={duty} noDuty={false} />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
        <StatCard icon={MapPin} label="मतदान केंद्र" value={v(duty.centerName)} color="amber" />
        <StatCard icon={Bus} label="बस संख्या" value={duty.busNo ? `बस–${duty.busNo}` : '—'} color="blue" />
        <StatCard icon={Map} label="सेक्टर" value={v(duty.sectorName)} color="green" />
        <StatCard icon={Users} label="सहयोगी कर्मी" value={`${(duty.allStaff || []).length} कर्मी`} color="orange" />
      </div>
      <SectionCard icon={Info} title="संक्षिप्त विवरण">
        <InfoTile icon={Shield} label="थाना" value={v(duty.thana)} />
        <InfoTile icon={Building2} label="ग्राम पंचायत" value={v(duty.gpName)} />
        <InfoTile icon={Layers} label="जोन" value={v(duty.zoneName)} />
        <InfoTile icon={Globe} label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile icon={Hash} label="केंद्र प्रकार" value={ct(duty.centerType)} />
      </SectionCard>
      <div className="grid sm:grid-cols-2 gap-3">
        <NavButton icon={Navigation} label="Google Maps पर नेविगेट करें" color="amber" onClick={onOpenMap} fullWidth />
        <NavButton icon={Printer} label="ड्यूटी कार्ड प्रिंट करें" color="dark" onClick={onGoToDutyCard} fullWidth />
      </div>
    </>
  );
}

function BoothDutyDetail({ duty, onOpenMap }) {
  if (!duty) return <NoDutyState />;
  return (
    <>
      <SectionCard icon={MapPin} title="ड्यूटी स्थान">
        <InfoTile icon={Vote} label="मतदान केंद्र" value={v(duty.centerName)} />
        <InfoTile icon={Home} label="पता" value={v(duty.centerAddress)} />
        <InfoTile icon={Hash} label="केंद्र प्रकार" value={ct(duty.centerType)} />
        <InfoTile icon={Shield} label="थाना" value={v(duty.thana)} />
        <InfoTile icon={Building2} label="ग्राम पंचायत" value={v(duty.gpName)} />
      </SectionCard>
      <SectionCard icon={Map} title="प्रशासनिक विवरण" accent="blue">
        <InfoTile icon={Map} label="सेक्टर" value={v(duty.sectorName)} />
        <InfoTile icon={Layers} label="जोन" value={v(duty.zoneName)} />
        <InfoTile icon={Home} label="जोन मुख्यालय" value={v(duty.zoneHq)} />
        <InfoTile icon={Globe} label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile icon={Bus} label="बस संख्या" value={duty.busNo ? `बस–${duty.busNo}` : null} />
        <InfoTile icon={User} label="नियुक्त किया" value={v(duty.assignedBy)} />
      </SectionCard>
      {(duty.sectorOfficers || []).length > 0 && <OfficerCard label="सेक्टर अधिकारी" officers={duty.sectorOfficers} />}
      {(duty.zonalOfficers || []).length > 0 && <OfficerCard label="जोनल अधिकारी" officers={duty.zonalOfficers} />}
      {(duty.superOfficers || []).length > 0 && <OfficerCard label="क्षेत्र अधिकारी" officers={duty.superOfficers} />}
      <NavButton icon={Navigation} label="Google Maps पर नेविगेट करें" color="amber" onClick={onOpenMap} />
    </>
  );
}

function BoothCoStaff({ duty }) {
  if (!duty) return <NoDutyState />;
  const staff = duty.allStaff || [];
  return (
    <SectionCard icon={Users} title={`सहयोगी कर्मी (${staff.length})`} accent="green">
      {staff.length === 0 ? (
        <div className="py-10 text-center">
          <Users className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <p className="text-sm text-slate-500">कोई सहयोगी नहीं</p>
        </div>
      ) : (
        <div className="space-y-1">
          {staff.map((s, i) => (
            <StaffRow
              key={i}
              index={i}
              total={staff.length}
              staff={s}
              armed={s.is_armed === 1 || s.is_armed === true}
            />
          ))}
        </div>
      )}
    </SectionCard>
  );
}

function BoothDutyCard({ duty, user }) {
  const [printing, setPrinting] = useState(false);
  const [hasMarked, setHasMarked] = useState(false);

  if (!duty) return <NoDutyState />;

  const handlePrint = async () => {
    setPrinting(true);
    const tId = toast.loading('कार्ड प्रिंट हो रहा है...');
    try {
      await printDutyCard(toAdminShape(duty, user));
      try {
        await apiClient.post('/staff/mark-card-downloaded', {});
      } catch (e) { console.error('mark-card-downloaded', e); }
      setHasMarked(true);
      toast.success('ड्यूटी कार्ड डाउनलोड हो गया!', { id: tId });
    } catch (e) {
      toast.error('प्रिंट त्रुटि: ' + (e.message || e), { id: tId });
    } finally {
      setPrinting(false);
    }
  };

  const sahyogi = duty.allStaff || [];

  return (
    <>
      <div className="relative overflow-hidden rounded-2xl p-6 mb-4 bg-gradient-to-br from-slate-800 via-slate-900 to-amber-900 shadow-xl">
        <div className="absolute -top-8 -right-8 w-40 h-40 rounded-full bg-amber-500/20 blur-2xl" />
        <div className="relative z-10 flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl bg-white/15 backdrop-blur-sm flex items-center justify-center flex-shrink-0">
            <Badge className="w-7 h-7 text-white" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="font-extrabold text-white text-lg">ड्यूटी कार्ड</p>
            <p className="text-xs text-amber-100/70">आधिकारिक चुनाव ड्यूटी कार्ड</p>
          </div>
          <button
            onClick={handlePrint}
            disabled={printing}
            className="bg-amber-600 hover:bg-amber-700 disabled:opacity-60 text-white px-5 py-3 rounded-xl font-bold text-sm flex items-center gap-2 shadow-lg transition-all hover:-translate-y-0.5"
          >
            {printing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Printer className="w-4 h-4" />}
            {printing ? 'प्रिंट हो रहा है...' : 'प्रिंट'}
          </button>
        </div>
      </div>

      {hasMarked && (
        <div className="bg-emerald-50 border border-emerald-200 rounded-xl px-4 py-3 mb-4 flex items-center gap-3">
          <CheckCircle2 className="w-5 h-5 text-emerald-600 flex-shrink-0" />
          <span className="text-sm font-bold text-emerald-700">ड्यूटी कार्ड डाउनलोड हो गया ✓</span>
        </div>
      )}

      <SectionCard icon={EyeIcon} title="कार्ड विवरण" accent="amber">
        <PreviewRow label="नाम" value={user?.name} />
        <PreviewRow label="PNO" value={user?.pno} />
        <PreviewRow label="पद" value={rh(user?.rank || user?.user_rank)} />
        <PreviewRow label="केंद्र" value={duty.centerName} />
        <PreviewRow label="केंद्र प्रकार" value={ct(duty.centerType)} />
        {duty.busNo && <PreviewRow label="बस" value={`बस–${duty.busNo}`} />}
        <PreviewRow label="सेक्टर" value={duty.sectorName} />
        <PreviewRow label="जोन" value={duty.zoneName} />
        <PreviewRow label="सहयोगी" value={`${sahyogi.length} कर्मी`} />
      </SectionCard>
    </>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTOR SECTIONS
// ═══════════════════════════════════════════════════════════════════════════════
function SectorOverview({ duty, user }) {
  if (!duty) return <NoDutyState />;
  return (
    <>
      <HeroCard user={user} duty={duty} noDuty={false} subtitle="सेक्टर अधिकारी" />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
        <StatCard icon={Vote} label="कुल बूथ" value={`${duty.totalBooths || 0}`} color="amber" />
        <StatCard icon={Users} label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} color="green" />
        <StatCard icon={Building2} label="ग्राम पंचायत" value={`${(duty.gramPanchayats || []).length}`} color="blue" />
        <StatCard icon={Map} label="जोन" value={v(duty.zoneName)} color="orange" />
      </div>
      <SectionCard icon={Info} title="सेक्टर विवरण">
        <InfoTile icon={Grid3x3} label="सेक्टर" value={v(duty.sectorName)} />
        <InfoTile icon={Home} label="मुख्यालय" value={v(duty.hqAddress)} />
        <InfoTile icon={Layers} label="जोन" value={v(duty.zoneName)} />
        <InfoTile icon={Globe} label="सुपर जोन" value={v(duty.superZoneName)} />
      </SectionCard>
    </>
  );
}

function SectorInfo({ duty }) {
  if (!duty) return <NoDutyState />;
  return (
    <>
      <SectionCard icon={Grid3x3} title="सेक्टर जानकारी">
        <InfoTile icon={Grid3x3} label="सेक्टर" value={v(duty.sectorName)} />
        <InfoTile icon={Home} label="HQ पता" value={v(duty.hqAddress)} />
        <InfoTile icon={Map} label="जोन" value={v(duty.zoneName)} />
        <InfoTile icon={Globe} label="सुपर जोन" value={v(duty.superZoneName)} />
      </SectionCard>
      {(duty.coOfficers || []).length > 0 && <OfficerCard label="सह-सेक्टर अधिकारी" officers={duty.coOfficers} />}
      {(duty.zonalOfficers || []).length > 0 && <OfficerCard label="जोनल अधिकारी (वरिष्ठ)" officers={duty.zonalOfficers} />}
    </>
  );
}

function SectorBoothAttendance({ duty, onRefresh }) {
  const [pendingUpdates, setPendingUpdates] = useState({});
  const [saving, setSaving] = useState(false);
  const [searchQ, setSearchQ] = useState('');

  if (!duty) return <NoDutyState />;
  const centers = duty.centers || [];

  const getAttended = (s) => {
    if (s.duty_id != null && Object.prototype.hasOwnProperty.call(pendingUpdates, s.duty_id)) {
      return pendingUpdates[s.duty_id];
    }
    return s.attended === 1 || s.attended === true;
  };

  const toggle = (dutyId, current) => {
    setPendingUpdates(p => ({ ...p, [dutyId]: !current }));
  };

  const filtered = useMemo(() => {
    if (!searchQ) return centers;
    const q = searchQ.toLowerCase();
    return centers.filter(c =>
      (c.name || '').toLowerCase().includes(q) ||
      (c.gp_name || '').toLowerCase().includes(q) ||
      (c.thana || '').toLowerCase().includes(q)
    );
  }, [centers, searchQ]);

  let totalStaff = 0, presentStaff = 0;
  centers.forEach(c => (c.staff || []).forEach(s => {
    totalStaff++;
    if (getAttended(s)) presentStaff++;
  }));

  const saveAll = async () => {
    if (!Object.keys(pendingUpdates).length) return;
    setSaving(true);
    const tId = toast.loading('सेव हो रहा है...');
    try {
      const updates = Object.entries(pendingUpdates).map(([dutyId, attended]) => ({
        dutyId: Number(dutyId), attended,
      }));
      await apiClient.post('/staff/attendance/bulk', { updates });
      setPendingUpdates({});
      onRefresh();
      toast.success('उपस्थिति सेव हो गई ✓', { id: tId });
    } catch (e) {
      toast.error('त्रुटि: ' + (e.message || e), { id: tId });
    } finally { setSaving(false); }
  };

  const pendingCount = Object.keys(pendingUpdates).length;

  return (
    <>
      <div className="relative overflow-hidden bg-gradient-to-br from-slate-800 via-slate-900 to-amber-900 rounded-2xl p-5 mb-4 shadow-xl">
        <div className="absolute -top-8 -right-8 w-40 h-40 rounded-full bg-amber-400/20 blur-2xl" />
        <div className="relative z-10">
          <div className="flex items-center justify-between gap-3 mb-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-white/15 flex items-center justify-center">
                <Vote className="w-5 h-5 text-white" />
              </div>
              <div>
                <p className="font-extrabold text-white text-lg">बूथ उपस्थिति</p>
                <p className="text-xs text-amber-100/70">रियल-टाइम अपडेट</p>
              </div>
            </div>
            {pendingCount > 0 && (
              <button
                onClick={saveAll}
                disabled={saving}
                className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-60 text-white px-4 py-2.5 rounded-xl font-bold text-sm flex items-center gap-2 shadow-lg transition-all"
              >
                {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
                {saving ? 'सेव...' : `${pendingCount} सेव करें`}
              </button>
            )}
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div className="bg-white/10 backdrop-blur-sm rounded-xl p-3 text-center">
              <p className="text-2xl font-extrabold text-white">{totalStaff}</p>
              <p className="text-[10px] text-amber-100/70 uppercase tracking-wider">कुल स्टाफ</p>
            </div>
            <div className="bg-emerald-500/20 backdrop-blur-sm border border-emerald-400/30 rounded-xl p-3 text-center">
              <p className="text-2xl font-extrabold text-emerald-300">{presentStaff}</p>
              <p className="text-[10px] text-emerald-200 uppercase tracking-wider">उपस्थित</p>
            </div>
            <div className="bg-red-500/20 backdrop-blur-sm border border-red-400/30 rounded-xl p-3 text-center">
              <p className="text-2xl font-extrabold text-red-300">{totalStaff - presentStaff}</p>
              <p className="text-[10px] text-red-200 uppercase tracking-wider">अनुपस्थित</p>
            </div>
          </div>
        </div>
      </div>

      <div className="relative mb-4">
        <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
        <input
          type="text"
          value={searchQ}
          onChange={e => setSearchQ(e.target.value)}
          placeholder="बूथ / थाना / ग्राम पंचायत खोजें..."
          className="w-full bg-white border border-slate-200 rounded-xl pl-11 pr-4 py-3 text-sm focus:border-amber-500 focus:ring-2 focus:ring-amber-200 outline-none transition-all"
        />
      </div>

      {filtered.length === 0 ? (
        <div className="py-16 text-center bg-white rounded-2xl border border-slate-200">
          <Search className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <p className="text-sm text-slate-500">कोई बूथ नहीं मिला</p>
        </div>
      ) : filtered.map((center, ci) => {
        const staff = center.staff || [];
        const present = staff.filter(s => getAttended(s)).length;
        const tc = typeColorClass(center.center_type);
        const allPresent = present === staff.length && staff.length > 0;
        return (
          <div key={ci} className="bg-white rounded-2xl border border-slate-200 overflow-hidden mb-3 shadow-sm hover:shadow-md transition-shadow">
            <div className={`flex items-center gap-3 px-4 py-3 ${tc.light} border-b ${tc.border}`}>
              <span className={`${tc.bg} text-white text-[11px] font-extrabold px-2.5 py-1 rounded-md`}>
                {center.center_type || 'C'}
              </span>
              <div className="flex-1 min-w-0">
                <p className="font-bold text-sm text-slate-800 truncate">{center.name || '—'}</p>
                <p className="text-[11px] text-slate-500">{center.gp_name || ''} · {center.thana || ''}</p>
              </div>
              <span className={`px-3 py-1 rounded-full text-[11px] font-extrabold border ${allPresent ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-slate-50 text-slate-600 border-slate-200'}`}>
                {present}/{staff.length}
              </span>
            </div>
            {staff.length === 0 ? (
              <p className="text-center text-sm text-slate-500 py-6">कोई स्टाफ असाइन नहीं</p>
            ) : staff.map((s, si) => {
              const attended = getAttended(s);
              const armed = s.is_armed === 1 || s.is_armed === true;
              return (
                <div key={si} className={`flex items-center gap-3 px-4 py-3 ${si < staff.length - 1 ? 'border-b border-slate-100' : ''}`}>
                  <div className={`w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0 border ${armed ? 'bg-emerald-50 border-emerald-200' : 'bg-slate-50 border-slate-200'}`}>
                    {armed ? <Shield className="w-4 h-4 text-emerald-700" /> : <User className="w-4 h-4 text-slate-600" />}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-bold text-sm text-slate-800 truncate">{s.name || '—'}</p>
                    <div className="flex items-center gap-2 flex-wrap mt-0.5">
                      <span className="text-[11px] text-slate-500">{rh(s.user_rank)}</span>
                      <span className="text-[11px] text-slate-400">·</span>
                      <span className="text-[11px] text-slate-500">{s.pno || ''}</span>
                      <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded ${armed ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-100 text-slate-600'}`}>
                        {armed ? 'सशस्त्र' : 'निःशस्त्र'}
                      </span>
                    </div>
                  </div>
                  <button
                    onClick={() => s.duty_id && toggle(s.duty_id, attended)}
                    className={`flex items-center gap-1 px-3 py-1.5 rounded-full text-[11px] font-bold border transition-all hover:scale-105 ${attended ? 'bg-emerald-600 text-white border-emerald-600 shadow-sm' : 'bg-red-50 text-red-700 border-red-200'}`}
                  >
                    {attended ? <Check className="w-3 h-3" /> : <X className="w-3 h-3" />}
                    {attended ? 'हाँ' : 'नहीं'}
                  </button>
                </div>
              );
            })}
          </div>
        );
      })}
    </>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ZONE SECTIONS
// ═══════════════════════════════════════════════════════════════════════════════
function ZoneOverview({ duty, user }) {
  if (!duty) return <NoDutyState />;
  return (
    <>
      <HeroCard user={user} duty={duty} noDuty={false} subtitle="जोनल अधिकारी" />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
        <StatCard icon={Grid3x3} label="कुल सेक्टर" value={`${duty.totalSectors || 0}`} color="amber" />
        <StatCard icon={Vote} label="कुल बूथ" value={`${duty.totalBooths || 0}`} color="blue" />
        <StatCard icon={Users} label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} color="green" />
        <StatCard icon={Globe} label="सुपर जोन" value={v(duty.superZoneName)} color="orange" />
      </div>
      <SectionCard icon={Map} title="जोन विवरण">
        <InfoTile icon={Map} label="जोन" value={v(duty.zoneName)} />
        <InfoTile icon={Home} label="मुख्यालय" value={v(duty.hqAddress)} />
        <InfoTile icon={Globe} label="सुपर जोन" value={v(duty.superZoneName)} />
      </SectionCard>
    </>
  );
}

function ZoneInfo({ duty }) {
  if (!duty) return <NoDutyState />;
  return (
    <>
      <SectionCard icon={Map} title="जोन विस्तार जानकारी">
        <InfoTile icon={Map} label="जोन" value={v(duty.zoneName)} />
        <InfoTile icon={Home} label="HQ" value={v(duty.hqAddress)} />
        <InfoTile icon={Globe} label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile icon={Grid3x3} label="कुल सेक्टर" value={`${duty.totalSectors || 0}`} />
        <InfoTile icon={Vote} label="कुल बूथ" value={`${duty.totalBooths || 0}`} />
        <InfoTile icon={Users} label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} />
      </SectionCard>
      {(duty.coOfficers || []).length > 0 && <OfficerCard label="जोनल अधिकारी" officers={duty.coOfficers} />}
      {(duty.superOfficers || []).length > 0 && <OfficerCard label="क्षेत्र अधिकारी (वरिष्ठ)" officers={duty.superOfficers} />}
    </>
  );
}

function ZoneSectors({ duty }) {
  if (!duty) return <NoDutyState />;
  const sectors = duty.sectors || [];
  return (
    <SectionCard icon={Grid3x3} title={`सेक्टर (${sectors.length})`}>
      {sectors.length === 0 ? (
        <div className="py-10 text-center">
          <Grid3x3 className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <p className="text-sm text-slate-500">कोई सेक्टर नहीं</p>
        </div>
      ) : sectors.map((s, i) => (
        <div key={i} className={`py-3 ${i < sectors.length - 1 ? 'border-b border-slate-100' : ''}`}>
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-amber-50 border border-amber-200 flex items-center justify-center flex-shrink-0">
              <Grid3x3 className="w-4 h-4 text-amber-700" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-bold text-sm text-slate-800">{s.name || '—'}</p>
              <p className="text-[11px] text-slate-500 mt-0.5">
                {s.gp_count || 0} GP · {s.center_count || 0} बूथ · {s.staff_assigned || 0} स्टाफ
              </p>
            </div>
          </div>
          {(s.officers || []).length > 0 && (
            <div className="flex flex-wrap gap-2 mt-3 ml-13">
              {(s.officers || []).map((o, j) => (
                <span key={j} className="bg-amber-50 border border-amber-200 text-amber-700 text-[10px] font-semibold px-2.5 py-1 rounded-full">
                  {o.name} ({rh(o.user_rank || o.rank)})
                </span>
              ))}
            </div>
          )}
        </div>
      ))}
    </SectionCard>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// KSHETRA SECTIONS
// ═══════════════════════════════════════════════════════════════════════════════
function KshetraOverview({ duty, user }) {
  if (!duty) return <NoDutyState />;
  return (
    <>
      <HeroCard user={user} duty={duty} noDuty={false} subtitle="क्षेत्र अधिकारी" />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
        <StatCard icon={Map} label="कुल जोन" value={`${duty.totalZones || 0}`} color="amber" />
        <StatCard icon={Grid3x3} label="कुल सेक्टर" value={`${duty.totalSectors || 0}`} color="blue" />
        <StatCard icon={Vote} label="कुल बूथ" value={`${duty.totalBooths || 0}`} color="green" />
        <StatCard icon={Users} label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} color="orange" />
      </div>
      <SectionCard icon={Layers} title="क्षेत्र विवरण">
        <InfoTile icon={Layers} label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile icon={Building2} label="जिला" value={v(duty.district)} />
        <InfoTile icon={Briefcase} label="ब्लॉक" value={v(duty.block)} />
      </SectionCard>
    </>
  );
}

function KshetraInfo({ duty }) {
  if (!duty) return <NoDutyState />;
  return (
    <>
      <SectionCard icon={Layers} title="क्षेत्र जानकारी">
        <InfoTile icon={Layers} label="सुपर जोन" value={v(duty.superZoneName)} />
        <InfoTile icon={Building2} label="जिला" value={v(duty.district)} />
        <InfoTile icon={Briefcase} label="ब्लॉक" value={v(duty.block)} />
        <InfoTile icon={Map} label="कुल जोन" value={`${duty.totalZones || 0}`} />
        <InfoTile icon={Grid3x3} label="कुल सेक्टर" value={`${duty.totalSectors || 0}`} />
        <InfoTile icon={Vote} label="कुल बूथ" value={`${duty.totalBooths || 0}`} />
        <InfoTile icon={Users} label="असाइन स्टाफ" value={`${duty.totalAssigned || 0}`} />
      </SectionCard>
      {(duty.coOfficers || []).length > 0 && <OfficerCard label="सह-क्षेत्र अधिकारी" officers={duty.coOfficers} />}
    </>
  );
}

function KshetraZones({ duty }) {
  if (!duty) return <NoDutyState />;
  const zones = duty.zones || [];
  return (
    <SectionCard icon={Map} title={`जोन (${zones.length})`}>
      {zones.length === 0 ? (
        <div className="py-10 text-center">
          <Map className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <p className="text-sm text-slate-500">कोई जोन नहीं</p>
        </div>
      ) : zones.map((z, i) => (
        <div key={i} className={`py-3 ${i < zones.length - 1 ? 'border-b border-slate-100' : ''}`}>
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-blue-50 border border-blue-200 flex items-center justify-center flex-shrink-0">
              <Map className="w-4 h-4 text-blue-700" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-bold text-sm text-slate-800">{z.name || '—'}</p>
              <p className="text-[11px] text-slate-500 mt-0.5">
                {z.sector_count || 0} सेक्टर · {z.center_count || 0} बूथ · {z.staff_assigned || 0} स्टाफ
              </p>
              {z.hq_address && <p className="text-[10px] text-slate-400 mt-0.5">HQ: {z.hq_address}</p>}
            </div>
          </div>
          {(z.officers || []).length > 0 && (
            <div className="flex flex-wrap gap-2 mt-3">
              {(z.officers || []).map((o, j) => (
                <span key={j} className="bg-amber-50 border border-amber-200 text-amber-700 text-[10px] font-semibold px-2.5 py-1 rounded-full">
                  {o.name} ({rh(o.user_rank || o.rank)})
                </span>
              ))}
            </div>
          )}
        </div>
      ))}
    </SectionCard>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// DISTRICT DUTY SECTIONS
// ═══════════════════════════════════════════════════════════════════════════════
function DistrictOverview({ duty, user, electionConfig, onGoToDutyCard }) {
  const dutyType = duty.dutyType || '';
  const batchNo = duty.batchNo;
  const busNo = duty.busNo || '';
  const note = duty.note || '';
  const batchStaff = duty.batchStaff || [];

  return (
    <>
      <ElectionConfigBanner electionConfig={electionConfig} />

      <div className="relative overflow-hidden rounded-2xl p-6 mb-5 bg-gradient-to-br from-purple-700 via-purple-800 to-fuchsia-900 shadow-xl shadow-purple-500/30">
        <div className="absolute -top-12 -right-12 w-48 h-48 rounded-full bg-purple-400/20 blur-2xl" />
        <div className="absolute -bottom-8 -left-8 w-40 h-40 rounded-full bg-fuchsia-500/10 blur-2xl" />

        <div className="relative z-10">
          <div className="flex items-center gap-4 mb-4">
            <div className="w-14 h-14 rounded-2xl bg-white/15 backdrop-blur-sm border border-white/30 flex items-center justify-center flex-shrink-0">
              <ShieldCheck className="w-7 h-7 text-white" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[10px] font-bold tracking-widest uppercase text-purple-200 mb-0.5">जनपदीय ड्यूटी</p>
              <p className="text-xl font-extrabold text-white">{dutyLabel(dutyType)}</p>
            </div>
            <span className="px-3 py-1.5 rounded-full bg-white/15 border border-white/20 text-white text-xs font-extrabold flex-shrink-0">
              बैच {batchNo ?? '—'}
            </span>
          </div>

          {(busNo || note) && (
            <>
              <div className="h-px bg-white/15 my-3" />
              {busNo && (
                <div className="flex items-center gap-2 mb-1.5">
                  <Bus className="w-3.5 h-3.5 text-purple-200" />
                  <p className="text-xs text-purple-50">बस: {busNo}</p>
                </div>
              )}
              {note && (
                <div className="flex items-start gap-2">
                  <FileText className="w-3.5 h-3.5 text-purple-200 mt-0.5 flex-shrink-0" />
                  <p className="text-xs text-purple-50/90">{note}</p>
                </div>
              )}
            </>
          )}
        </div>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
        <StatCard icon={ShieldCheck} label="ड्यूटी प्रकार" value={dutyLabel(dutyType)} color="purple" />
        <StatCard icon={TicketCheck} label="बैच संख्या" value={`बैच ${batchNo ?? '—'}`} color="amber" />
        <StatCard icon={Users} label="बैच कर्मी" value={`${batchStaff.length} कर्मी`} color="green" />
        <StatCard icon={Bus} label="बस संख्या" value={busNo || '—'} color="blue" />
      </div>

      <SectionCard icon={User} title="कर्मी विवरण" accent="purple">
        <InfoTile icon={User} label="नाम" value={user?.name} />
        <InfoTile icon={Hash} label="PNO" value={user?.pno} />
        <InfoTile icon={Star} label="पद" value={rh(user?.rank || user?.user_rank)} />
        <InfoTile icon={Shield} label="थाना" value={user?.thana} />
        <InfoTile icon={Building2} label="जनपद" value={user?.district || electionConfig?.district} />
      </SectionCard>

      <NavButton icon={Printer} label="ड्यूटी कार्ड प्रिंट करें" color="purple" onClick={onGoToDutyCard} />
    </>
  );
}

function DistrictDetail({ duty }) {
  const dutyType = duty.dutyType || '';
  const batchNo = duty.batchNo;
  const busNo = duty.busNo || '';
  const note = duty.note || '';
  const district = duty.district || '';
  const assignedAt = duty.assignedAt || '';

  return (
    <>
      <SectionCard icon={ShieldCheck} title="जनपदीय ड्यूटी विवरण" accent="purple">
        <InfoTile icon={Briefcase} label="ड्यूटी प्रकार" value={dutyLabel(dutyType)} />
        <InfoTile icon={TicketCheck} label="बैच संख्या" value={`बैच ${batchNo ?? '—'}`} />
        {busNo && <InfoTile icon={Bus} label="बस संख्या" value={busNo} />}
        {district && <InfoTile icon={Building2} label="जनपद" value={district} />}
        {note && <InfoTile icon={FileText} label="विशेष नोट" value={note} />}
        {assignedAt && <InfoTile icon={Clock} label="नियुक्ति समय" value={assignedAt} />}
      </SectionCard>

      <div className="bg-purple-50/60 border border-purple-200 rounded-2xl p-5">
        <div className="flex items-center gap-2 mb-3">
          <Info className="w-4 h-4 text-purple-700" />
          <h3 className="font-extrabold text-sm text-purple-800">ड्यूटी जानकारी</h3>
        </div>
        <p className="text-sm text-purple-700/80 leading-relaxed">
          आप <strong>"{dutyLabel(dutyType)}"</strong> ड्यूटी पर बैच <strong>{batchNo}</strong> में तैनात हैं।
          यह जनपद स्तरीय ड्यूटी है जो व्यवस्थापक द्वारा सौंपी गई है।
        </p>
      </div>
    </>
  );
}

function DistrictBatchStaff({ duty }) {
  const staff = duty.batchStaff || [];
  const batchNo = duty.batchNo;

  return (
    <SectionCard icon={Users} title={`बैच ${batchNo} के सहयोगी कर्मी (${staff.length})`} accent="purple">
      {staff.length === 0 ? (
        <div className="py-10 text-center">
          <Users className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <p className="text-sm text-slate-500">कोई सहयोगी नहीं</p>
        </div>
      ) : (
        <div className="space-y-1">
          {staff.map((s, i) => (
            <StaffRow
              key={i}
              index={i}
              total={staff.length}
              staff={s}
              armed={s.is_armed === 1 || s.is_armed === true}
            />
          ))}
        </div>
      )}
    </SectionCard>
  );
}

function DistrictDutyCard({ duty, user, electionConfig }) {
  const [printing, setPrinting] = useState(false);
  const [hasMarked, setHasMarked] = useState(false);

  const toAdminShapeDistrict = () => {
    const ec = electionConfig || {};
    const batchStaff = duty.batchStaff || [];
    return {
      name: user?.name || '',
      pno: user?.pno || '',
      mobile: user?.mobile || '',
      rank: user?.rank || user?.user_rank || '',
      user_rank: user?.rank || user?.user_rank || '',
      isArmed: user?.isArmed || false,
      staffThana: user?.thana || '',
      thana: user?.thana || '',
      district: user?.district || ec.district || '',
      centerName: dutyLabel(duty.dutyType),
      centerType: 'district',
      gpName: '',
      sectorName: '',
      zoneName: '',
      superZoneName: '',
      busNo: duty.busNo || '',
      bus_no: duty.busNo || '',
      zonalOfficers: [],
      sectorOfficers: [],
      superOfficers: [],
      sahyogi: batchStaff,
      allStaff: batchStaff,
      electionName: ec.election_name || '',
      electionType: ec.election_type || '',
      electionDate: ec.election_date || '',
      phase: ec.phase || '',
      pratahSamay: ec.pratah_samay || '',
      sayaSamay: ec.saya_samay || '',
      batchNo: duty.batchNo?.toString() || '',
    };
  };

  const handlePrint = async () => {
    setPrinting(true);
    const tId = toast.loading('कार्ड प्रिंट हो रहा है...');
    try {
      await printDutyCard(toAdminShapeDistrict());
      try {
        await apiClient.post('/staff/mark-card-downloaded', {});
      } catch (e) { console.error('mark-card-downloaded', e); }
      setHasMarked(true);
      toast.success('ड्यूटी कार्ड डाउनलोड हो गया!', { id: tId });
    } catch (e) {
      toast.error('प्रिंट त्रुटि: ' + (e.message || e), { id: tId });
    } finally {
      setPrinting(false);
    }
  };

  const ec = electionConfig || {};

  return (
    <>
      <div className="relative overflow-hidden rounded-2xl p-6 mb-4 bg-gradient-to-br from-purple-700 via-purple-800 to-fuchsia-900 shadow-xl">
        <div className="absolute -top-8 -right-8 w-40 h-40 rounded-full bg-fuchsia-500/20 blur-2xl" />
        <div className="relative z-10 flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl bg-white/15 backdrop-blur-sm flex items-center justify-center flex-shrink-0">
            <Badge className="w-7 h-7 text-white" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="font-extrabold text-white text-lg">जनपदीय ड्यूटी कार्ड</p>
            <p className="text-xs text-purple-100/70">District Duty Card</p>
          </div>
          <button
            onClick={handlePrint}
            disabled={printing}
            className="bg-amber-600 hover:bg-amber-700 disabled:opacity-60 text-white px-5 py-3 rounded-xl font-bold text-sm flex items-center gap-2 shadow-lg transition-all hover:-translate-y-0.5"
          >
            {printing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Printer className="w-4 h-4" />}
            {printing ? 'प्रिंट हो रहा है...' : 'प्रिंट'}
          </button>
        </div>
      </div>

      {hasMarked && (
        <div className="bg-emerald-50 border border-emerald-200 rounded-xl px-4 py-3 mb-4 flex items-center gap-3">
          <CheckCircle2 className="w-5 h-5 text-emerald-600 flex-shrink-0" />
          <span className="text-sm font-bold text-emerald-700">ड्यूटी कार्ड डाउनलोड हो गया ✓</span>
        </div>
      )}

      <SectionCard icon={EyeIcon} title="कार्ड विवरण" accent="purple">
        <PreviewRow label="नाम" value={user?.name} />
        <PreviewRow label="PNO" value={user?.pno} />
        <PreviewRow label="पद" value={rh(user?.rank || user?.user_rank)} />
        <PreviewRow label="ड्यूटी प्रकार" value={dutyLabel(duty.dutyType)} />
        <PreviewRow label="बैच संख्या" value={`बैच ${duty.batchNo ?? '—'}`} />
        {duty.busNo && <PreviewRow label="बस" value={duty.busNo} />}
        <PreviewRow label="जनपद" value={user?.district || ec.district} />
        {ec.election_name && <PreviewRow label="चुनाव" value={ec.election_name} />}
        {ec.election_date && <PreviewRow label="मतदान तिथि" value={ec.election_date} />}
        {ec.pratah_samay && <PreviewRow label="प्रातः समय" value={ec.pratah_samay} />}
        {ec.saya_samay && <PreviewRow label="सायं समय" value={ec.saya_samay} />}
        <PreviewRow label="सहयोगी" value={`${(duty.batchStaff || []).length} कर्मी`} />
      </SectionCard>
    </>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// RULES SECTION
// ═══════════════════════════════════════════════════════════════════════════════
const RULES_CONFIG = {
  'A++': { label: 'अत्यति संवेदनशील', color: 'purple', bg: 'bg-purple-600', text: 'text-purple-700', light: 'bg-purple-50', border: 'border-purple-200' },
  A: { label: 'अति संवेदनशील', color: 'red', bg: 'bg-red-600', text: 'text-red-700', light: 'bg-red-50', border: 'border-red-200' },
  B: { label: 'संवेदनशील', color: 'amber', bg: 'bg-amber-600', text: 'text-amber-700', light: 'bg-amber-50', border: 'border-amber-200' },
  C: { label: 'सामान्य', color: 'blue', bg: 'bg-blue-600', text: 'text-blue-700', light: 'bg-blue-50', border: 'border-blue-200' },
};

function RulesSection({ rules = [] }) {
  const grouped = {};
  rules.forEach(r => {
    const s = (r.sensitivity || '?').toString();
    if (!grouped[s]) grouped[s] = [];
    grouped[s].push(r);
  });

  return (
    <>
      <div className="relative overflow-hidden bg-gradient-to-br from-slate-800 via-slate-900 to-amber-900 rounded-2xl p-5 mb-4 shadow-xl">
        <div className="absolute -top-8 -right-8 w-40 h-40 rounded-full bg-amber-400/20 blur-2xl" />
        <div className="relative z-10 flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl bg-white/15 flex items-center justify-center flex-shrink-0">
            <ClipboardList className="w-6 h-6 text-white" />
          </div>
          <div>
            <p className="font-extrabold text-white text-lg">बूथ स्टाफ मानक</p>
            <p className="text-xs text-amber-100/70">संवेदनशीलता के अनुसार आवश्यक स्टाफ</p>
          </div>
        </div>
      </div>

      {rules.length === 0 ? (
        <SectionCard icon={Info} title="मानक">
          <div className="py-10 text-center">
            <ClipboardList className="w-12 h-12 text-slate-300 mx-auto mb-3" />
            <p className="text-sm text-slate-500">कोई मानक सेट नहीं है</p>
          </div>
        </SectionCard>
      ) : ['A++', 'A', 'B', 'C'].filter(s => grouped[s]).map(s => {
        const config = RULES_CONFIG[s] || RULES_CONFIG.C;
        const list = grouped[s];
        const total = list.reduce((a, r) => a + ((r.count || 0)), 0);
        return (
          <div key={s} className={`bg-white rounded-2xl border ${config.border} mb-3 overflow-hidden shadow-sm hover:shadow-md transition-shadow`}>
            <div className={`flex items-center gap-3 px-4 py-3 ${config.light} border-b ${config.border}`}>
              <span className={`${config.bg} text-white px-2.5 py-1 rounded-md font-extrabold text-xs`}>{s}</span>
              <span className={`flex-1 font-bold ${config.text} text-sm`}>{config.label}</span>
              <span className={`font-extrabold ${config.text} text-sm`}>{total} कर्मी</span>
            </div>
            <div className="p-3 space-y-2">
              {list.map((r, i) => {
                const isArmed = r.isArmed === true || r.is_armed === 1;
                return (
                  <div key={i} className="flex items-center gap-3 bg-amber-50/30 border border-amber-100 rounded-xl px-4 py-3">
                    {isArmed ? <Shield className="w-4 h-4 text-emerald-700 flex-shrink-0" /> : <User className="w-4 h-4 text-slate-600 flex-shrink-0" />}
                    <div className="flex-1 min-w-0">
                      <p className="font-bold text-sm text-slate-800">{rh(r.rank)}</p>
                      <p className={`text-[10px] ${isArmed ? 'text-emerald-700' : 'text-slate-500'}`}>
                        {isArmed ? 'सशस्त्र' : 'निःशस्त्र'}
                      </p>
                    </div>
                    <span className={`px-3 py-1.5 rounded-full text-sm font-extrabold ${config.light} ${config.text} border ${config.border}`}>
                      {r.count}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// POST ELECTION VIEW
// ═══════════════════════════════════════════════════════════════════════════════
function PostElectionView({ user, electionConfig, onOpenHistory }) {
  const ec = electionConfig || {};
  const dateStr = formatHindiDate(ec.election_date);
  const eName = ec.election_name || '';
  const phase = ec.phase || '';

  return (
    <div className="max-w-3xl mx-auto">
      <div className="relative overflow-hidden rounded-3xl p-8 mb-6 bg-gradient-to-br from-emerald-700 via-emerald-800 to-green-900 shadow-2xl shadow-emerald-500/30">
        <div className="absolute -top-12 -right-12 w-56 h-56 rounded-full bg-emerald-400/20 blur-3xl" />
        <div className="absolute -bottom-12 -left-12 w-56 h-56 rounded-full bg-green-500/20 blur-3xl" />
        <div className="relative z-10 text-center">
          <div className="w-20 h-20 mx-auto mb-5 rounded-full bg-white/15 backdrop-blur-sm border-2 border-white/30 flex items-center justify-center">
            <Vote className="w-10 h-10 text-white" />
          </div>
          <p className="text-white font-extrabold text-2xl mb-2">चुनाव सम्पन्न हो गया</p>
          {eName && <p className="text-emerald-100/90 text-sm mb-1">{eName}</p>}
          {dateStr !== '—' && <p className="text-emerald-200/70 text-xs mb-1">तिथि: {dateStr}</p>}
          {phase && <p className="text-emerald-200/70 text-xs mb-3">चरण: {phase}</p>}
          <p className="text-emerald-100/80 text-sm mt-4 max-w-md mx-auto">
            {user?.name || ''} जी, आपकी ड्यूटी का रिकॉर्ड इतिहास में सुरक्षित है।
          </p>
        </div>
      </div>

      <div className="bg-white rounded-2xl p-5 mb-5 border border-slate-200 shadow-sm flex items-center gap-4">
        <div className="w-14 h-14 rounded-full bg-amber-50 border border-amber-200 flex items-center justify-center flex-shrink-0">
          <User className="w-7 h-7 text-amber-700" />
        </div>
        <div className="min-w-0">
          <p className="font-extrabold text-slate-800 text-base truncate">{user?.name || '—'}</p>
          <p className="text-xs text-slate-500 mt-0.5">PNO: {user?.pno || '—'} · {rh(user?.rank || user?.user_rank)}</p>
          <p className="text-xs text-slate-500">{user?.thana || ''}{user?.district ? ` · ${user.district}` : ''}</p>
        </div>
      </div>

      <button
        onClick={onOpenHistory}
        className="w-full bg-gradient-to-br from-slate-800 to-slate-900 hover:from-slate-900 hover:to-black text-white p-5 rounded-2xl shadow-xl shadow-slate-700/30 transition-all hover:-translate-y-0.5 mb-5 group"
      >
        <div className="flex items-center justify-center gap-3 mb-2">
          <div className="w-12 h-12 rounded-xl bg-white/12 flex items-center justify-center group-hover:scale-110 transition-transform">
            <History className="w-6 h-6 text-white" />
          </div>
          <div className="text-left">
            <p className="text-white font-extrabold text-lg">ड्यूटी इतिहास देखें</p>
            <p className="text-slate-400 text-xs">Duty History</p>
          </div>
        </div>
        <div className="inline-flex items-center px-4 py-1.5 rounded-full bg-white/10 border border-white/20">
          <p className="text-slate-200 text-xs">सभी ड्यूटी रिकॉर्ड देखने के लिए क्लिक करें</p>
        </div>
      </button>

      <div className="bg-blue-50/60 border border-blue-200 rounded-2xl p-4 flex items-start gap-3">
        <Info className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
        <p className="text-sm text-blue-700 leading-relaxed">
          चुनाव समाप्त हो जाने के बाद यहाँ कोई सक्रिय ड्यूटी नहीं दिखाई जाती।
          आपकी सभी पुरानी ड्यूटियाँ <strong>"इतिहास"</strong> में उपलब्ध हैं।
        </p>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOGOUT DIALOG
// ═══════════════════════════════════════════════════════════════════════════════
function LogoutDialog({ onConfirm, onCancel }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-2xl border border-red-200 animate-[fadeIn_0.2s_ease-out]">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-11 h-11 rounded-xl bg-red-50 flex items-center justify-center">
            <LogOut className="w-5 h-5 text-red-600" />
          </div>
          <p className="font-extrabold text-lg text-red-700">लॉग आउट</p>
        </div>
        <p className="text-sm text-slate-700 mb-6">क्या आप वाकई लॉग आउट करना चाहते हैं?</p>
        <div className="flex gap-3">
          <button
            onClick={onCancel}
            className="flex-1 px-4 py-3 rounded-xl font-bold text-sm text-slate-600 border border-slate-300 hover:bg-slate-50 transition-colors"
          >
            रद्द करें
          </button>
          <button
            onClick={onConfirm}
            className="flex-1 px-4 py-3 rounded-xl font-bold text-sm text-white bg-red-600 hover:bg-red-700 shadow-lg shadow-red-500/30 transition-all"
          >
            लॉग आउट
          </button>
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// NAV CONFIG
// ═══════════════════════════════════════════════════════════════════════════════
const buildNavItems = ({ isAfterElection, hasDistrictDuty, roleType }) => {
  if (isAfterElection) {
    return [{ key: 'history', label: 'इतिहास', icon: History }];
  }
  if (hasDistrictDuty && roleType === 'none') {
    return [
      { key: 'overview', label: 'डैशबोर्ड', icon: LayoutDashboard },
      { key: 'duty', label: 'ड्यूटी', icon: MapPin },
      { key: 'costaff', label: 'सहयोगी', icon: Users },
      { key: 'dutycard', label: 'ड्यूटी कार्ड', icon: Badge },
    ];
  }
  switch (roleType) {
    case 'sector':
      return [
        { key: 'overview', label: 'डैशबोर्ड', icon: LayoutDashboard },
        { key: 'duty', label: 'ड्यूटी', icon: MapPin },
        { key: 'attendance', label: 'बूथ & उपस्थिति', icon: Vote },
        { key: 'rules', label: 'मानक', icon: ClipboardList },
      ];
    case 'zone':
      return [
        { key: 'overview', label: 'डैशबोर्ड', icon: LayoutDashboard },
        { key: 'duty', label: 'ड्यूटी', icon: MapPin },
        { key: 'sectors', label: 'सेक्टर', icon: Grid3x3 },
        { key: 'rules', label: 'मानक', icon: ClipboardList },
      ];
    case 'kshetra':
      return [
        { key: 'overview', label: 'डैशबोर्ड', icon: LayoutDashboard },
        { key: 'duty', label: 'ड्यूटी', icon: MapPin },
        { key: 'zones', label: 'जोन', icon: Map },
        { key: 'rules', label: 'मानक', icon: ClipboardList },
      ];
    default:
      return [
        { key: 'overview', label: 'डैशबोर्ड', icon: LayoutDashboard },
        { key: 'duty', label: 'ड्यूटी', icon: MapPin },
        { key: 'costaff', label: 'सहयोगी', icon: Users },
        { key: 'dutycard', label: 'ड्यूटी कार्ड', icon: Badge },
      ];
  }
};

const roleIconMap = {
  sector: Grid3x3,
  zone: Map,
  kshetra: Layers,
  booth: Vote,
};
const districtRoleIcon = ShieldCheck;

const roleLabelMap = {
  sector: 'सेक्टर अधिकारी',
  zone: 'जोनल अधिकारी',
  kshetra: 'क्षेत्र अधिकारी',
  booth: 'बूथ स्टाफ',
};

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════
export default function StaffDashboardPage() {
  const [activeTab, setActiveTab] = useState('overview');
  const [duty, setDuty] = useState(null);
  const [user, setUser] = useState(null);
  const [districtDuty, setDistrictDuty] = useState(null);
  const [electionConfig, setElectionConfig] = useState(null);
  const [roleType, setRoleType] = useState('none');
  const [isAfterElection, setIsAfterElection] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showLogout, setShowLogout] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const nav = useNavigate();

  // Normalize duty data (snake_case -> camelCase)
  const normalizeDuty = (d) => {
    if (!d || typeof d !== 'object' || Array.isArray(d)) return d;
    return {
      ...d,
      centerName: d.centerName || d.center_name,
      centerAddress: d.centerAddress || d.center_address,
      centerType: d.centerType || d.center_type,
      superZoneName: d.superZoneName || d.super_zone_name,
      zoneName: d.zoneName || d.zone_name,
      zoneHq: d.zoneHq || d.zone_hq,
      sectorName: d.sectorName || d.sector_name,
      busNo: d.busNo || d.bus_no,
      gpName: d.gpName || d.gp_name,
      hqAddress: d.hqAddress || d.hq_address,
      assignedBy: d.assignedBy || d.assigned_by,
      totalBooths: d.totalBooths || d.total_booths,
      totalSectors: d.totalSectors || d.total_sectors,
      totalZones: d.totalZones || d.total_zones,
      totalAssigned: d.totalAssigned || d.total_assigned,
      gramPanchayats: d.gramPanchayats || d.gram_panchayats || [],
      allStaff: d.allStaff || d.all_staff || [],
      sectorOfficers: d.sectorOfficers || d.sector_officers || [],
      zonalOfficers: d.zonalOfficers || d.zonal_officers || [],
      superOfficers: d.superOfficers || d.super_officers || [],
      coOfficers: d.coOfficers || d.co_officers || [],
      boothRules: d.boothRules || d.booth_rules || [],
      sectors: d.sectors || [],
      zones: d.zones || [],
      centers: d.centers || [],
    };
  };

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [userRes, dutyRes, electionRes, districtRes] = await Promise.all([
        apiClient.get('/staff/profile'),
        apiClient.get('/staff/my-duty'),
        apiClient.get('/staff/election-config').catch(() => null),
        apiClient.get('/staff/district-duty').catch(() => null),
      ]);

      const userData = userRes?.data || userRes || {};
      const rawDuty = dutyRes?.data || dutyRes || null;
      const dutyData = normalizeDuty(rawDuty);
      const role = (dutyData?.roleType || dutyData?.role_type || 'none').toString().toLowerCase();

      const ec = electionRes?.data || electionRes || null;
      const electionDateStr = ec?.election_date;
      let isAfter = false;
      if (electionDateStr) {
        const parsed = new Date(electionDateStr);
        if (!isNaN(parsed)) isAfter = new Date() > parsed;
      }

      const dd = districtRes?.data || districtRes || null;

      setUser(userData);
      setDuty(dutyData);
      setRoleType(role);
      setElectionConfig(ec);
      setDistrictDuty(dd);
      setIsAfterElection(isAfter);
      setActiveTab('overview');
    } catch (e) {
      setError(e.message || 'Error loading data');
      toast.error('डेटा लोड करने में त्रुटि');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadData(); }, [loadData]);

  const handleLogout = () => {
    setShowLogout(false);
    try {
      localStorage.clear();
      sessionStorage.clear();
    } catch {}
    toast.success('लॉग आउट हो गया');
    setTimeout(() => { window.location.href = '/login'; }, 400);
  };

  const openMap = () => {
    if (!duty?.latitude || !duty?.longitude) {
      toast.error('इस केंद्र की GPS लोकेशन अभी तक दर्ज नहीं है।');
      return;
    }
    window.open(
      `https://www.google.com/maps/dir/?api=1&destination=${duty.latitude},${duty.longitude}&travelmode=driving`,
      '_blank',
    );
  };

  const hasDistrictDuty = !!districtDuty;
  const navItems = useMemo(
    () => buildNavItems({ isAfterElection, hasDistrictDuty, roleType }),
    [isAfterElection, hasDistrictDuty, roleType],
  );

  const RoleIcon = hasDistrictDuty && roleType === 'none' ? districtRoleIcon : (roleIconMap[roleType] || Vote);
  const roleLabel = hasDistrictDuty && roleType === 'none' ? 'जनपदीय ड्यूटी' : (roleLabelMap[roleType] || 'सक्रिय');
  const roleAccent = hasDistrictDuty && roleType === 'none' ? 'purple' : 'emerald';

  const renderSection = () => {
    if (loading) return <LoadingSpinner />;
    if (error) return <ErrorState error={error} onRetry={loadData} />;
    if (isAfterElection) {
      return <PostElectionView user={user} electionConfig={electionConfig} onOpenHistory={() => nav('/staff/history')} />;
    }

    // District duty takes priority if no other role
    if (hasDistrictDuty && roleType === 'none') {
      switch (activeTab) {
        case 'overview': return <DistrictOverview duty={districtDuty} user={user} electionConfig={electionConfig} onGoToDutyCard={() => setActiveTab('dutycard')} />;
        case 'duty': return <DistrictDetail duty={districtDuty} />;
        case 'costaff': return <DistrictBatchStaff duty={districtDuty} />;
        case 'dutycard': return <DistrictDutyCard duty={districtDuty} user={user} electionConfig={electionConfig} />;
        default: return null;
      }
    }

    switch (roleType) {
      case 'sector':
        switch (activeTab) {
          case 'overview': return <SectorOverview duty={duty} user={user} />;
          case 'duty': return <SectorInfo duty={duty} />;
          case 'attendance': return <SectorBoothAttendance duty={duty} onRefresh={loadData} />;
          case 'rules': return <RulesSection rules={duty?.boothRules || []} />;
          default: return null;
        }
      case 'zone':
        switch (activeTab) {
          case 'overview': return <ZoneOverview duty={duty} user={user} />;
          case 'duty': return <ZoneInfo duty={duty} />;
          case 'sectors': return <ZoneSectors duty={duty} />;
          case 'rules': return <RulesSection rules={duty?.boothRules || []} />;
          default: return null;
        }
      case 'kshetra':
        switch (activeTab) {
          case 'overview': return <KshetraOverview duty={duty} user={user} />;
          case 'duty': return <KshetraInfo duty={duty} />;
          case 'zones': return <KshetraZones duty={duty} />;
          case 'rules': return <RulesSection rules={duty?.boothRules || []} />;
          default: return null;
        }
      default:
        switch (activeTab) {
          case 'overview': return <BoothOverview duty={duty} user={user} onGoToDutyCard={() => setActiveTab('dutycard')} onOpenMap={openMap} />;
          case 'duty': return <BoothDutyDetail duty={duty} onOpenMap={openMap} />;
          case 'costaff': return <BoothCoStaff duty={duty} />;
          case 'dutycard': return <BoothDutyCard duty={duty} user={user} />;
          default: return null;
        }
    }
  };

  const currentTab = navItems.find(n => n.key === activeTab) || navItems[0];

  return (
    <>
      <Toaster
        position="top-right"
        toastOptions={{
          style: {
            fontFamily: "'Noto Sans Devanagari', sans-serif",
            borderRadius: '12px',
            background: '#1e293b',
            color: '#fff',
            fontSize: '13px',
            fontWeight: 600,
          },
          success: { iconTheme: { primary: '#10b981', secondary: '#fff' } },
          error: { iconTheme: { primary: '#ef4444', secondary: '#fff' } },
        }}
      />

      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;500;600;700;800;900&display=swap');
        body { font-family: 'Noto Sans Devanagari', sans-serif; background: #fafaf5; }
        @keyframes fadeIn { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
        @keyframes slideIn { from { opacity: 0; transform: translateX(-20px); } to { opacity: 1; transform: translateX(0); } }
        .animate-slideIn { animation: slideIn 0.25s ease-out; }
        ::-webkit-scrollbar { width: 8px; height: 8px; }
        ::-webkit-scrollbar-track { background: #f1f5f9; }
        ::-webkit-scrollbar-thumb { background: #d4a843; border-radius: 4px; }
        ::-webkit-scrollbar-thumb:hover { background: #b8860b; }
      `}</style>

      <div className="flex h-screen overflow-hidden bg-gradient-to-br from-amber-50/30 via-yellow-50/20 to-stone-50 font-['Noto_Sans_Devanagari',sans-serif]">

        {/* Mobile sidebar overlay */}
        {sidebarOpen && (
          <div
            className="fixed inset-0 z-30 bg-black/50 lg:hidden backdrop-blur-sm"
            onClick={() => setSidebarOpen(false)}
          />
        )}

        {/* ── SIDEBAR ── */}
        <aside className={`
          ${sidebarOpen ? 'translate-x-0' : '-translate-x-full'}
          ${sidebarCollapsed ? 'lg:w-20' : 'lg:w-72'}
          lg:translate-x-0
          fixed lg:relative inset-y-0 left-0 z-40 w-72 flex-shrink-0
          bg-gradient-to-b from-slate-900 via-slate-900 to-amber-950
          flex flex-col
          transition-all duration-300 ease-in-out
          shadow-2xl shadow-slate-900/40
        `}>
          {/* Header */}
          <div className={`p-4 border-b border-white/10 ${sidebarCollapsed ? 'lg:px-2' : ''}`}>
            <div className={`flex items-center gap-3 ${sidebarCollapsed ? 'lg:justify-center' : ''}`}>
              <div className={`w-12 h-12 rounded-2xl bg-gradient-to-br from-amber-500 to-amber-700 border border-amber-400/50 flex items-center justify-center flex-shrink-0 shadow-lg shadow-amber-500/30`}>
                <RoleIcon className="w-6 h-6 text-white" />
              </div>
              {!sidebarCollapsed && (
                <div className="min-w-0 flex-1">
                  <p className="font-extrabold text-white text-sm truncate">{user?.name || 'Staff Portal'}</p>
                  <div className="flex items-center gap-1.5 mt-1">
                    <div className={`w-1.5 h-1.5 rounded-full ${roleAccent === 'purple' ? 'bg-purple-400' : 'bg-emerald-400'} animate-pulse`} />
                    <span className={`text-[10px] font-bold ${roleAccent === 'purple' ? 'text-purple-300' : 'text-emerald-300'}`}>
                      {roleLabel}
                    </span>
                  </div>
                </div>
              )}
            </div>

            {!sidebarCollapsed && user?.pno && (
              <div className="mt-3 px-3 py-2 rounded-lg bg-white/5 border border-white/10">
                <p className="text-[10px] uppercase tracking-wider text-amber-200/60 font-bold">PNO</p>
                <p className="text-xs text-white font-bold">{user.pno}</p>
              </div>
            )}
          </div>

          {/* Election badge */}
          {!sidebarCollapsed && electionConfig?.election_date && (
            <div className="px-4 pt-4">
              <div className={`px-3 py-2 rounded-xl border ${isAfterElection ? 'bg-emerald-500/10 border-emerald-500/30' : 'bg-blue-500/10 border-blue-500/30'} flex items-center gap-2`}>
                {isAfterElection ? <CheckCircle2 className="w-4 h-4 text-emerald-400 flex-shrink-0" /> : <Calendar className="w-4 h-4 text-blue-400 flex-shrink-0" />}
                <div className="min-w-0">
                  <p className={`text-[9px] uppercase tracking-wider font-bold ${isAfterElection ? 'text-emerald-300' : 'text-blue-300'}`}>
                    {isAfterElection ? 'चुनाव संपन्न' : 'मतदान तिथि'}
                  </p>
                  <p className="text-[11px] text-white font-bold truncate">{formatHindiDate(electionConfig.election_date)}</p>
                </div>
              </div>
            </div>
          )}

          {/* Nav Items */}
          <nav className="flex-1 overflow-y-auto py-4 px-3">
            {!sidebarCollapsed && (
              <p className="px-3 text-[10px] uppercase tracking-wider text-amber-200/40 font-bold mb-2">मेनू</p>
            )}
            <div className="space-y-1">
              {navItems.map(({ key, label, icon: ItemIcon }) => {
                const active = activeTab === key;
                return (
                  <button
                    key={key}
                    onClick={() => {
                      if (key === 'history') {
                        nav('/staff/history');
                        return;
                      }
                      setActiveTab(key);
                      setSidebarOpen(false);
                    }}
                    title={sidebarCollapsed ? label : ''}
                    className={`
                      w-full flex items-center gap-3 px-3 py-2.5 rounded-xl
                      transition-all duration-200 group
                      ${sidebarCollapsed ? 'lg:justify-center lg:px-2' : ''}
                      ${active
                        ? 'bg-gradient-to-r from-amber-600/30 to-amber-500/10 border border-amber-500/30 shadow-lg shadow-amber-500/10'
                        : 'hover:bg-white/5 border border-transparent'
                      }
                    `}
                  >
                    <ItemIcon className={`w-5 h-5 flex-shrink-0 ${active ? 'text-amber-400' : 'text-slate-400 group-hover:text-white'}`} />
                    {!sidebarCollapsed && (
                      <>
                        <span className={`text-sm font-bold flex-1 text-left ${active ? 'text-white' : 'text-slate-300 group-hover:text-white'}`}>
                          {label}
                        </span>
                        {active && <ChevronRight className="w-4 h-4 text-amber-400" />}
                      </>
                    )}
                  </button>
                );
              })}
            </div>
          </nav>

          {/* Footer */}
          <div className="border-t border-white/10 p-3 space-y-1">
            <button
              onClick={() => nav('/staff/history')}
              title={sidebarCollapsed ? 'इतिहास' : ''}
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-white/5 transition-colors group ${sidebarCollapsed ? 'lg:justify-center lg:px-2' : ''}`}
            >
              <History className="w-5 h-5 text-slate-400 group-hover:text-white flex-shrink-0" />
              {!sidebarCollapsed && <span className="text-sm font-bold text-slate-300 group-hover:text-white">इतिहास</span>}
            </button>
            <button
              onClick={() => setShowLogout(true)}
              title={sidebarCollapsed ? 'लॉग आउट' : ''}
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl hover:bg-red-500/10 transition-colors group ${sidebarCollapsed ? 'lg:justify-center lg:px-2' : ''}`}
            >
              <LogOut className="w-5 h-5 text-red-400 flex-shrink-0" />
              {!sidebarCollapsed && <span className="text-sm font-bold text-red-300 group-hover:text-red-200">लॉग आउट</span>}
            </button>
          </div>
        </aside>

        {/* ── MAIN AREA ── */}
        <div className="flex-1 flex flex-col min-w-0">
          {/* Top Bar */}
          <header className="bg-white/95 backdrop-blur-sm border-b border-slate-200 px-4 lg:px-6 h-16 flex items-center gap-3 flex-shrink-0 shadow-sm sticky top-0 z-20">
            <button
              onClick={() => setSidebarOpen(true)}
              className="lg:hidden w-10 h-10 rounded-xl bg-slate-100 hover:bg-slate-200 flex items-center justify-center transition-colors"
            >
              <Menu className="w-5 h-5 text-slate-700" />
            </button>

            <button
              onClick={() => setSidebarCollapsed(p => !p)}
              className="hidden lg:flex w-10 h-10 rounded-xl bg-slate-100 hover:bg-slate-200 items-center justify-center transition-colors"
              title="साइडबार टॉगल करें"
            >
              <Menu className="w-5 h-5 text-slate-700" />
            </button>

            <div className="flex items-center gap-3 min-w-0 flex-1">
              {currentTab && (
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-amber-100 to-yellow-100 border border-amber-200 flex items-center justify-center flex-shrink-0">
                  <currentTab.icon className="w-5 h-5 text-amber-700" />
                </div>
              )}
              <div className="min-w-0">
                <p className="font-extrabold text-slate-800 text-base truncate">
                  {isAfterElection ? 'ड्यूटी इतिहास' : (currentTab?.label || 'डैशबोर्ड')}
                </p>
                <p className="text-[11px] text-slate-500 truncate">{user?.name || 'Loading...'} · {roleLabel}</p>
              </div>
            </div>

            <button
              onClick={loadData}
              className="w-10 h-10 rounded-xl bg-slate-100 hover:bg-amber-100 flex items-center justify-center transition-colors group"
              title="रीफ्रेश"
            >
              <RefreshCw className={`w-4 h-4 text-slate-700 group-hover:text-amber-700 ${loading ? 'animate-spin' : ''}`} />
            </button>

            <button
              onClick={() => setShowLogout(true)}
              className="hidden sm:flex w-10 h-10 rounded-xl bg-red-50 hover:bg-red-100 items-center justify-center transition-colors"
              title="लॉग आउट"
            >
              <LogOut className="w-4 h-4 text-red-600" />
            </button>
          </header>

          {/* Content */}
          <main className="flex-1 overflow-y-auto">
            <div className="max-w-6xl mx-auto p-4 lg:p-6 animate-slideIn" key={activeTab}>
              {renderSection()}
            </div>
          </main>
        </div>
      </div>

      {showLogout && <LogoutDialog onConfirm={handleLogout} onCancel={() => setShowLogout(false)} />}
    </>
  );
}