// Run with: npm i playwright && node icons.mjs, then paste icons.json into src/client/IconData.luau.
// Draws the UI icons as SVG and writes their RGBA pixels (base64) to icons.json and a preview sheet.
import { chromium } from 'playwright';
import fs from 'fs';
const S = 96;
const stroke = '#1d1033';
const defs = `
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff38a"/><stop offset=".5" stop-color="#ffcf1f"/><stop offset="1" stop-color="#e58a00"/></linearGradient>
<linearGradient id="red" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff6b5b"/><stop offset="1" stop-color="#c3161c"/></linearGradient>
<linearGradient id="green" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2fa83a"/><stop offset=".35" stop-color="#8af06a"/><stop offset="1" stop-color="#17761f"/></linearGradient>
<linearGradient id="blue" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#bff3ff"/><stop offset=".45" stop-color="#3fb8ff"/><stop offset="1" stop-color="#1450d8"/></linearGradient>
<linearGradient id="purple" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f3c4ff"/><stop offset=".5" stop-color="#b058ff"/><stop offset="1" stop-color="#5a1fc0"/></linearGradient>
<linearGradient id="steel" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset=".5" stop-color="#c9d6ea"/><stop offset="1" stop-color="#7d8ca8"/></linearGradient>
<linearGradient id="brown" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c47a3a"/><stop offset="1" stop-color="#6b3612"/></linearGradient>
<radialGradient id="shine" cx=".35" cy=".3" r=".6"><stop offset="0" stop-color="#fff" stop-opacity=".9"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>`;
const sw = 'stroke="' + stroke + '" stroke-width="5" stroke-linejoin="round" stroke-linecap="round"';
function star(cx, cy, R, r) {
  let p = [];
  for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + i * Math.PI / 5; const rr = i % 2 ? r : R; p.push((cx + rr * Math.cos(a)).toFixed(1) + ',' + (cy + rr * Math.sin(a)).toFixed(1)); }
  return p.join(' ');
}
const sword = (rot) => `<g transform="rotate(${rot} 48 48)">
 <path d="M41 12 L55 12 L55 62 L41 62 Z" fill="url(#steel)" ${sw}/>
 <path d="M41 12 L48 2 L55 12" fill="url(#steel)" ${sw}/>
 <rect x="27" y="59" width="42" height="10" rx="3" fill="url(#gold)" ${sw}/>
 <rect x="44" y="68" width="8" height="16" rx="2" fill="url(#brown)" ${sw}/>
 <circle cx="48" cy="88" r="5" fill="url(#gold)" ${sw}/></g>`;
const icons = {
  play: `${sword(-38)}${sword(38)}`,
  star: `<polygon points="${star(48, 50, 42, 19)}" fill="url(#gold)" ${sw}/>
   <ellipse cx="40" cy="47" rx="4" ry="9" fill="${stroke}"/><ellipse cx="56" cy="47" rx="4" ry="9" fill="${stroke}"/>
   <ellipse cx="40" cy="44" rx="1.6" ry="3" fill="#fff"/><ellipse cx="56" cy="44" rx="1.6" ry="3" fill="#fff"/>
   <polygon points="${star(48, 50, 42, 19)}" fill="url(#shine)"/>`,
  mushroom: `<path d="M14 54 C10 22 86 22 82 54 Z" fill="url(#red)" ${sw}/>
   <circle cx="48" cy="30" r="10" fill="#fff"/><circle cx="24" cy="46" r="7" fill="#fff"/><circle cx="72" cy="46" r="7" fill="#fff"/>
   <path d="M28 54 L68 54 L66 80 Q48 90 30 80 Z" fill="#fff4dc" ${sw}/>
   <ellipse cx="41" cy="66" rx="3.5" ry="7" fill="${stroke}"/><ellipse cx="55" cy="66" rx="3.5" ry="7" fill="${stroke}"/>
   <path d="M14 54 C10 22 86 22 82 54 Z" fill="url(#shine)"/>`,
  crystal: `<path d="M48 6 L76 34 L48 90 L20 34 Z" fill="url(#purple)" ${sw}/>
   <path d="M20 34 L76 34 M48 6 L38 34 L48 90 M48 6 L58 34 L48 90" fill="none" stroke="${stroke}" stroke-width="2.5" stroke-opacity=".55"/>
   <path d="M48 10 L38 34 L28 34 Z" fill="#fff" fill-opacity=".55"/>`,
  gem: `<path d="M24 14 L72 14 L88 36 L48 88 L8 36 Z" fill="url(#blue)" ${sw}/>
   <path d="M8 36 L88 36 M24 14 L34 36 L48 88 M72 14 L62 36 L48 88 M34 36 L48 14 L62 36" fill="none" stroke="${stroke}" stroke-width="2.5" stroke-opacity=".5"/>
   <path d="M26 17 L46 17 L34 34 L12 34 Z" fill="#fff" fill-opacity=".6"/>`,
  coin: `<ellipse cx="48" cy="48" rx="34" ry="42" fill="url(#gold)" ${sw}/>
   <ellipse cx="48" cy="48" rx="23" ry="31" fill="none" stroke="#b86a00" stroke-width="4"/>
   <rect x="43" y="28" width="10" height="40" rx="4" fill="#fff6b0" stroke="#b86a00" stroke-width="3"/>
   <ellipse cx="48" cy="48" rx="34" ry="42" fill="url(#shine)"/>`,
  trophy: `<path d="M26 14 L70 14 L68 44 Q48 66 28 44 Z" fill="url(#gold)" ${sw}/>
   <path d="M26 20 Q8 20 12 36 Q16 46 30 46 M70 20 Q88 20 84 36 Q80 46 66 46" fill="none" ${sw}/>
   <rect x="42" y="56" width="12" height="14" fill="url(#gold)" ${sw}/>
   <rect x="26" y="70" width="44" height="16" rx="4" fill="url(#brown)" ${sw}/>
   <polygon points="${star(48, 32, 11, 5)}" fill="#fff8c0" stroke="#b86a00" stroke-width="2"/>
   <path d="M30 18 L40 18 L38 40 Z" fill="#fff" fill-opacity=".5"/>`,
  lock: `<path d="M30 44 L30 30 Q30 12 48 12 Q66 12 66 30 L66 44" fill="none" stroke="${stroke}" stroke-width="15"/>
   <path d="M30 44 L30 30 Q30 12 48 12 Q66 12 66 30 L66 44" fill="none" stroke="url(#steel)" stroke-width="8"/>
   <rect x="18" y="42" width="60" height="44" rx="9" fill="url(#gold)" ${sw}/>
   <circle cx="48" cy="60" r="7" fill="${stroke}"/><rect x="45" y="62" width="6" height="14" rx="2" fill="${stroke}"/>`,
  pipe: `<rect x="22" y="36" width="52" height="54" fill="url(#green)" ${sw}/>
   <rect x="12" y="14" width="72" height="26" rx="4" fill="url(#green)" ${sw}/>
   <rect x="20" y="18" width="8" height="18" fill="#d6ffc6" fill-opacity=".8"/><rect x="30" y="40" width="7" height="46" fill="#d6ffc6" fill-opacity=".6"/>`,
  wrench: `<g transform="rotate(45 48 48)"><rect x="42" y="30" width="12" height="58" rx="6" fill="url(#steel)" ${sw}/>
   <path d="M30 10 Q30 34 48 34 Q66 34 66 10 L58 10 L58 22 L38 22 L38 10 Z" fill="url(#steel)" ${sw}/></g>`,
  flower: `<g ${sw}><circle cx="48" cy="22" r="14" fill="url(#red)"/><circle cx="26" cy="38" r="14" fill="url(#red)"/><circle cx="70" cy="38" r="14" fill="url(#red)"/><circle cx="36" cy="58" r="14" fill="url(#red)"/><circle cx="60" cy="58" r="14" fill="url(#red)"/></g>
   <circle cx="48" cy="42" r="14" fill="#fff8c0" ${sw}/>
   <path d="M48 72 L48 92" stroke="#1f8a2a" stroke-width="7"/>`,
  heart: `<path d="M48 86 C10 60 6 34 24 22 C36 14 46 22 48 30 C50 22 60 14 72 22 C90 34 86 60 48 86 Z" fill="url(#red)" ${sw}/>
   <ellipse cx="32" cy="34" rx="7" ry="10" fill="#fff" fill-opacity=".6"/>`,
};
const html = `<html><body style="margin:0;background:#2a2040"><canvas id=c width=${S} height=${S}></canvas><div id=sheet></div></body></html>`;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1300, height: 320 } });
await page.setContent(html);
const out = {};
for (const [name, body] of Object.entries(icons)) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="-2 -2 100 100"><defs>${defs}</defs>${body}</svg>`;
  out[name] = await page.evaluate(async ({ svg, S }) => {
    const img = new Image(); img.src = 'data:image/svg+xml;base64,' + btoa(svg); await img.decode();
    const c = document.getElementById('c'); const g = c.getContext('2d'); g.clearRect(0, 0, S, S); g.drawImage(img, 0, 0, S, S);
    const d = g.getImageData(0, 0, S, S).data; let s = ''; for (let i = 0; i < d.length; i++) s += String.fromCharCode(d[i]);
    const prev = document.createElement('img'); prev.src = c.toDataURL(); prev.style.margin = '4px'; document.getElementById('sheet').appendChild(prev);
    return btoa(s);
  }, { svg, S });
}
await page.screenshot({ path: 'sheet.png' });
fs.writeFileSync('icons.json', JSON.stringify(out));
await browser.close();
console.log(Object.keys(out).join(' '));
