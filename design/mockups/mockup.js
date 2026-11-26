// Shared behaviour for the Wiffletree iPhone mockups: the icon sprite, the phone's fixed chrome
// (Dynamic Island, status bar, home indicator) and the Light / Dark / Both appearance switch.
// Plain script, no modules, so the pages also work from file://.

// SF Symbols-like line icons on a 24-point grid. Use as <svg class="i"><use href="#i-name"/></svg>.
const ICONS = {
  back: '<path d="M15 5l-7 7 7 7"/>',
  chev: '<path d="M9 5l7 7-7 7"/>',
  down: '<path d="M6 9l6 6 6-6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  qr: '<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2v2h-2zM18 18h2v2h-2zM14 18h2M18 14h2"/>',
  play: '<path d="M8 5.5v13l11-6.5z"/>',
  wifi: '<path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19.3" r="0.9"/>',
  offline: '<path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.5 16a5 5 0 0 1 7 0M3.5 3.5l17 17"/>',
  vpn: '<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/><path d="M9 12l2 2 4-4"/>',
  network: '<circle cx="12" cy="5" r="2"/><circle cx="5" cy="19" r="2"/><circle cx="19" cy="19" r="2"/><path d="M12 7v5M12 12l-5.5 5.5M12 12l5.5 5.5"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>',
  tray: '<path d="M3 13l3-8h12l3 8v6H3zM3 13h5l1 3h6l1-3h5"/>',
  grid: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
  gauge: '<path d="M4 17a8 8 0 1 1 16 0M12 17l4-5"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M5.6 18.4l1.8-1.8M16.6 7.4l1.8-1.8"/><circle cx="12" cy="12" r="6.5"/>',
  agents: '<circle cx="9" cy="8" r="3.2"/><path d="M3 19c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5"/><circle cx="17" cy="9" r="2.5"/><path d="M16.5 13.6c2.6.2 4.5 2 4.5 4.9"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>',
  up: '<path d="M12 19V5M6 11l6-6 6 6"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7"/>',
  branch: '<circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="7" r="2"/><path d="M6 7v10M18 9c0 5-12 3-12 8"/>',
  pr: '<circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="19" r="2"/><path d="M6 7v10M18 17V9a3 3 0 0 0-3-3h-4M13 3.5L10.5 6 13 8.5"/>',
  merge: '<circle cx="6" cy="5" r="2"/><circle cx="6" cy="19" r="2"/><circle cx="18" cy="12" r="2"/><path d="M6 7v10M6 7c0 4 4 5 10 5"/>',
  bell: '<path d="M6 16v-5a6 6 0 0 1 12 0v5l2 2H4zM10 20.5a2 2 0 0 0 4 0"/>',
  dots: '<circle cx="5.5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="18.5" cy="12" r="1.4"/>',
  trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>',
  bolt: '<path d="M13 3L5 14h6l-1 7 8-11h-6z"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>',
  warn: '<path d="M12 3.5l9.5 17h-19zM12 10v5M12 18v.3"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  mac: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M9 20h6M12 16v4"/>',
  chat: '<path d="M4 5h16v11H9l-5 4z"/>',
  ticket: '<path d="M6 3h9l4 4v14H6zM14 3v5h5M9 13h6M9 17h4"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  demo: '<rect x="3" y="5" width="18" height="13" rx="2"/><path d="M10 9v5l4-2.5z"/>',
  question: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .8-1 1.5v.5M12 16.8v.3"/>',
  spin: '<path d="M12 3a9 9 0 1 0 9 9"/>',
  external: '<path d="M8 16L16 8M9 8h7v7"/>',
  stop: '<rect x="7" y="7" width="10" height="10" rx="2"/>',
  flash: '<path d="M9 3h6l-1 6h4l-8 12 1-8H7z"/>',
  photo: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M21 16l-5-5-8 8"/>',
  camera: '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
  phone: '<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
  eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
  doc: '<path d="M6 3h9l4 4v14H6zM14 3v5h5"/>',
};

// The Interlock symbol from the brand kit: main strokes in currentColor, the joint in Signal red.
const SYMBOL = '<symbol id="i-symbol" viewBox="0 0 444 214"><path fill="currentColor" d="M18 0 H79 Q97 0 107 16 L190 146 Q193 150 190 155 L149 201 Q128 223 107 203 L3 29 Q0 10 7 2 Q11 0 18 0 Z M277 106 L324 18 Q334 0 355 0 H425 Q453 0 439 26 L326 191 Z M212 147 H265 L302 201 Q310 210 299 210 H269 Q248 210 239 192 Z"/><path fill="var(--signal)" d="M176 74 H207 Q220 74 229 88 L265 143 Q268 147 261 147 H212 L169 83 Q165 74 176 74 Z"/></symbol>';

const STATUS_ICONS =
  '<svg viewBox="0 0 18 12" width="18"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>' +
  '<svg viewBox="0 0 16 12" width="16"><path d="M8 2.3c2.4 0 4.6.9 6.2 2.5l1.2-1.2A10.4 10.4 0 0 0 8 .6 10.4 10.4 0 0 0 .6 3.6l1.2 1.2A8.7 8.7 0 0 1 8 2.3zm0 3.4c1.5 0 2.8.6 3.8 1.5L13 6a7 7 0 0 0-5-2 7 7 0 0 0-5 2l1.2 1.2c1-1 2.3-1.5 3.8-1.5zm0 3.3c.6 0 1.1.2 1.5.6L8 11.1 6.5 9.6c.4-.4.9-.6 1.5-.6z"/></svg>' +
  '<svg viewBox="0 0 27 13" width="27"><rect x="0.5" y="0.5" width="23" height="12" rx="3.5" fill="none" stroke="currentColor" opacity="0.4"/><rect x="2" y="2" width="17" height="9" rx="2"/><path d="M25 4.5v4c.8-.3 1.4-1.1 1.4-2s-.6-1.7-1.4-2z" opacity="0.4"/></svg>';

function installSprite() {
  const symbols = Object.entries(ICONS)
    .map(([name, body]) => `<symbol id="i-${name}" viewBox="0 0 24 24">${body}</symbol>`)
    .join('');
  document.body.insertAdjacentHTML('afterbegin', `<svg width="0" height="0" style="position:absolute" aria-hidden="true">${symbols}${SYMBOL}</svg>`);
}

// Each .phone gets an island, a status bar (unless data-status="none") and a home indicator.
// data-time overrides the clock; data-status="icons" shows only the right-hand icons, as on the lock screen.
function dressPhones() {
  for (const phone of document.querySelectorAll('.phone')) {
    if (!phone.querySelector(':scope > .island')) phone.insertAdjacentHTML('afterbegin', '<div class="island"></div>');
    if (phone.dataset.status !== 'none') {
      const time = phone.dataset.status === 'icons' ? '' : (phone.dataset.time || '9:41');
      phone.querySelector(':scope > .island').insertAdjacentHTML('afterend',
        `<div class="status-bar"><span>${time}</span><span class="sb-icons">${STATUS_ICONS}</span></div>`);
    }
    phone.insertAdjacentHTML('beforeend', '<div class="home-indicator"></div>');
  }
}

// A QR-looking pattern (not a real code): three finder squares and seeded noise.
function drawFakeQr() {
  const size = 25;
  let seed = 7;
  const random = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const inFinder = (x, y) => [[0, 0], [size - 7, 0], [0, size - 7]].some(([fx, fy]) => x >= fx - 1 && x < fx + 8 && y >= fy - 1 && y < fy + 8);
  let cells = '';
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (!inFinder(x, y) && random() > 0.52) cells += `<rect x="${x}" y="${y}" width="1" height="1"/>`;
    }
  }
  const finder = (fx, fy) => `<path fill-rule="evenodd" d="M${fx} ${fy}h7v7h-7zM${fx + 1} ${fy + 1}v5h5v-5z"/><rect x="${fx + 2}" y="${fy + 2}" width="3" height="3"/>`;
  const svg = `<svg viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges">${cells}${finder(0, 0)}${finder(size - 7, 0)}${finder(0, size - 7)}</svg>`;
  document.querySelectorAll('.fake-qr').forEach((holder) => { holder.innerHTML = svg; });
}

const APPEARANCE_KEY = 'wiffletree-mockups-appearance';

function systemTheme() {
  return matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

// Light and Dark theme the whole page; Both shows each screen twice, light beside dark.
// A phone with data-locked-theme, such as the camera, always shows that appearance, once.
function applyAppearance(mode) {
  document.querySelectorAll('.phone.dark-copy').forEach((copy) => copy.remove());
  document.documentElement.dataset.theme = mode === 'both' ? systemTheme() : mode;
  for (const phone of document.querySelectorAll('.phones > .phone')) {
    if (phone.dataset.lockedTheme) {
      phone.dataset.theme = phone.dataset.lockedTheme;
    } else if (mode === 'both') {
      phone.dataset.theme = 'light';
      const copy = phone.cloneNode(true);
      copy.classList.add('dark-copy');
      copy.dataset.theme = 'dark';
      phone.after(copy);
    } else {
      delete phone.dataset.theme;
    }
  }
  document.querySelectorAll('.appearance button').forEach((button) => {
    button.setAttribute('aria-pressed', String(button.value === mode));
  });
  localStorage.setItem(APPEARANCE_KEY, mode);
}

function installAppearanceSwitch() {
  const holder = document.querySelector('.appearance');
  holder.setAttribute('role', 'group');
  holder.setAttribute('aria-label', 'Appearance');
  holder.innerHTML = ['light', 'dark', 'both']
    .map((mode) => `<button type="button" value="${mode}">${mode[0].toUpperCase()}${mode.slice(1)}</button>`)
    .join('');
  holder.addEventListener('click', (event) => {
    if (event.target.value) applyAppearance(event.target.value);
  });
  applyAppearance(localStorage.getItem(APPEARANCE_KEY) || systemTheme());
}

installSprite();
dressPhones();
drawFakeQr();
installAppearanceSwitch();
