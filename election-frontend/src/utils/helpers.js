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
  'Agra','Aligarh','Allahabad','Ambedkar Nagar','Amethi','Amroha','Auraiya',
  'Azamgarh','Baghpat','Bahraich','Ballia','Balrampur','Banda','Barabanki',
  'Bareilly','Basti','Bijnor','Budaun','Bulandshahr','Chandauli','Chitrakoot',
  'Deoria','Etah','Etawah','Farrukhabad','Fatehpur','Firozabad',
  'Gautam Buddh Nagar','Ghaziabad','Ghazipur','Gonda','Gorakhpur',
  'Hamirpur','Hapur','Hardoi','Hathras','Jalaun','Jaunpur','Jhansi',
  'Kannauj','Kanpur Dehat','Kanpur','Kasganj','Kaushambi','Kushinagar',
  'Lakhimpur Kheri','Lalitpur','Lucknow','Maharajganj','Mahoba','Mainpuri',
  'Mathura','Mau','Meerut','Mirzapur','Moradabad','Muzaffarnagar','Pilibhit',
  'Pratapgarh','Prayagraj','Raebareli','Rampur','Saharanpur','Sambhal',
  'Sant Kabir Nagar','Shahjahanpur','Shamli','Shrawasti','Siddharthnagar',
  'Sitapur','Sonbhadra','Sultanpur','Unnao','Varanasi',
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
