export const RANKS = [
  'SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable',
];

export const RANK_MAP = {
  constable: 'आरक्षी',
  'head constable': 'मुख्य आरक्षी',
  hc: 'मुख्य आरक्षी',
  si: 'उप निरीक्षक',
  'sub inspector': 'उप निरीक्षक',
  inspector: 'निरीक्षक',
  asi: 'सहायक उप निरीक्षक',
  'assistant sub inspector': 'सहायक उप निरीक्षक',
  dsp: 'उपाधीक्षक',
  asp: 'सहा0 पुलिस अधीक्षक',
  sp: 'पुलिस अधीक्षक',
  co: 'क्षेत्राधिकारी',
  'circle officer': 'क्षेत्राधिकारी',
};

export const SENSITIVITY_CONFIG = {
  'A++': { label: 'अति-अति संवेदनशील', color: '#6C3483', bg: '#f3e5f5' },
  A: { label: 'अति संवेदनशील', color: '#C0392B', bg: '#fdecea' },
  B: { label: 'संवेदनशील', color: '#E67E22', bg: '#fef3e2' },
  C: { label: 'सामान्य', color: '#1A5276', bg: '#e3f0fb' },
};

export const UP_DISTRICTS = [
  'आगरा',
  'आज़मगढ़',
  'बिजनौर',
  'इटावा',
  'अलीगढ़',
  'बागपत',
  'बदायूं',
  'फर्रुखाबाद',
  'अंबेडकर नगर',
  'बहराइच',
  'बुलंदशहर',
  'फतेहपुर',
  'अमेठी',
  'बलिया',
  'चंदौली',
  'फिरोजाबाद',
  'अमरोहा',
  'बलरामपुर',
  'चित्रकूट',
  'गौतम बुद्ध नगर',
  'औरैया',
  'बांदा',
  'देवरिया',
  'गाज़ियाबाद',
  'अयोध्या',
  'बाराबंकी',
  'एटा',
  'गाज़ीपुर',
  'गोंडा',
  'जालौन',
  'कासगंज',
  'लखनऊ',
  'गोरखपुर',
  'जौनपुर',
  'कौशांबी',
  'महाराजगंज',
  'हमीरपुर',
  'झांसी',
  'कुशीनगर',
  'महोबा',
  'हापुड़',
  'कन्नौज',
  'लखीमपुर खीरी',
  'मैनपुरी',
  'हरदोई',
  'कानपुर देहात',
  'ललितपुर',
  'मथुरा',
  'हाथरस',
  'कानपुर नगर',
  'मऊ',
  'पीलीभीत',
  'संभल',
  'सोनभद्र',
  'मेरठ',
  'प्रतापगढ़',
  'संतकबीर नगर',
  'सुल्तानपुर',
  'मिर्जापुर',
  'प्रयागराज',
  'भदोही (संत रविदास नगर)',
  'उन्नाव',
  'मुरादाबाद',
  'रायबरेली',
  'शाहजहाँपुर',
  'वाराणसी',
  'मुजफ्फरनगर',
  'रामपुर',
  'शामली',
  'सहारनपुर',
  'श्रावस्ती',
  'सिद्धार्थनगर',
  'सीतापुर',
];

export function rankHindi(val) {
  return RANK_MAP[(val || '').toLowerCase().trim()] || val || '—';
}

export function safeVal(x) {
  return x == null || String(x).trim() === '' ? '—' : String(x);
}

export function formatDate(d) {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
  });
}

export function debounce(fn, delay = 350) {
  let t;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), delay);
  };
}
