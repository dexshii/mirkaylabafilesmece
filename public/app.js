const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
const TILE = World.TILE;

let socket, myId, tiles = null, map = { w: 0, h: 0 }, npc = null, minimap = null;
const players = {};
const enemies = {};
let arrows = [];
let fires = [];
const effects = [];
const floaters = [];
const toasts = [];
const keys = {};
const mouse = { x: 0, y: 0 };
let nextAttack = 0, deadUntil = 0, killer = '';
let stats = { level: 1, xp: 0, xpNext: 100, quest: null, questsDone: 0 };
let banner = null, levelUp = null, dialog = null;
let last = performance.now(), sendTimer = 0;

function resize() { canvas.width = innerWidth; canvas.height = innerHeight; }
addEventListener('resize', resize); resize();

// ---------------- Assets ----------------
// Sprites are listed in assets/manifest.json; swap .svg for .png there when real art exists.
const sprites = {};
const previews = {};
const TILE_SPRITES = ['grass', 'dirt', 'wall', 'grass', 'water']; // trees are drawn over grass
const TILE_COLORS = ['#26331f', '#3d3123', '#4a4a50', '#14261a', '#132233'];

fetch('assets/manifest.json').then((r) => r.json()).then((m) => {
  for (const key in m) {
    const img = new Image();
    img.onload = () => { sprites[key] = img; drawPreviews(); };
    img.src = 'assets/' + m[key];
  }
}).catch(() => {});

function drawShape(c, shape, color, x, y, r) {
  c.fillStyle = color; c.strokeStyle = '#000'; c.lineWidth = 2;
  c.beginPath();
  if (shape === 'square') c.rect(x - r, y - r, r * 2, r * 2);
  else if (shape === 'triangle') { c.moveTo(x, y - r); c.lineTo(x + r, y + r); c.lineTo(x - r, y + r); c.closePath(); }
  else c.arc(x, y, r, 0, Math.PI * 2);
  c.fill(); c.stroke();
}

function drawSprite(key, x, y, size) {
  const img = sprites[key];
  if (!img) return false;
  ctx.drawImage(img, x - size / 2, y - size / 2, size, size);
  return true;
}

function drawPreviews() {
  for (const cls in previews) {
    const c = previews[cls].getContext('2d'), k = CLASSES[cls];
    c.clearRect(0, 0, 64, 64);
    if (sprites[k.sprite]) c.drawImage(sprites[k.sprite], 0, 0, 64, 64);
    else drawShape(c, k.shape, k.color, 32, 32, 18);
  }
}

// ---------------- Class select ----------------
const cards = document.getElementById('cards');
for (const key in CLASSES) {
  const k = CLASSES[key];
  const card = document.createElement('div');
  card.className = 'card';
  const pv = previews[key] = document.createElement('canvas');
  pv.width = pv.height = 64;
  card.appendChild(pv);
  card.insertAdjacentHTML('beforeend', `<h3>${k.name}</h3><div class="t">${k.title}</div>
    <div class="s">HP: ${k.hp}<br>Zırh: ${k.armor}<br>Çeviklik: ${k.agility}<br>Hasar: ${k.damage}<br>Büyü: ${k.magic}<br>Hız: ${k.speed}</div>`);
  card.onclick = () => start(key);
  cards.appendChild(card);
}
drawPreviews();

// ---------------- Networking ----------------
const withRender = (p) => ({ ...p, rx: p.x, ry: p.y });

function start(cls) {
  document.getElementById('select').style.display = 'none';
  socket = io();
  socket.on('connect', () => socket.emit('join', { cls, name: document.getElementById('name').value.trim() }));
  socket.on('init', (d) => {
    myId = d.id; map = d.map; tiles = d.tiles; npc = d.npc;
    for (const id in players) delete players[id];
    for (const id in enemies) delete enemies[id];
    for (const id in d.players) players[id] = withRender(d.players[id]);
    for (const id in d.enemies) enemies[id] = withRender(d.enemies[id]);
    fires = d.fires;
    buildMinimap();
    document.getElementById('quest').style.display = 'block';
  });
  socket.on('playerJoined', (p) => { players[p.id] = withRender(p); });
  socket.on('playerLeft', (id) => { delete players[id]; });
  socket.on('state', (s) => {
    for (const id in s.players) {
      const p = players[id], u = s.players[id];
      if (!p) continue;
      Object.assign(p, { hp: u.hp, maxHp: u.maxHp, dead: u.dead, level: u.level, buffed: u.buffed });
      if (id !== myId) { p.x = u.x; p.y = u.y; }
    }
    for (const id in enemies) if (!s.enemies[id]) delete enemies[id];
    for (const id in s.enemies) {
      if (enemies[id]) Object.assign(enemies[id], s.enemies[id]);
      else enemies[id] = withRender(s.enemies[id]);
    }
    arrows = s.arrows;
    fires = s.fires;
  });
  socket.on('pos', ({ x, y }) => {
    const me = players[myId];
    if (me) Object.assign(me, { x, y, rx: x, ry: y });
  });
  socket.on('fx', (f) => effects.push({ ...f, t: 0 }));
  socket.on('hit', ({ id, amount }) => {
    const p = players[id] || enemies[id];
    if (p) floaters.push({ x: p.rx, y: p.ry - 34, text: '-' + amount, color: '255,70,50', t: 0 });
  });
  socket.on('died', ({ id, by, enemy }) => {
    if (enemy) {
      const e = enemies[id];
      if (e) effects.push({ type: 'shatter', x: e.rx, y: e.ry, t: 0 });
      delete enemies[id];
      return;
    }
    if (players[id]) players[id].dead = true;
    if (id === myId) { deadUntil = performance.now() + RESPAWN_TIME * 1000; killer = by; }
  });
  socket.on('respawn', ({ id, x, y, hp }) => {
    const p = players[id];
    if (p) Object.assign(p, { x, y, rx: x, ry: y, hp, dead: false });
  });
  socket.on('stats', (s) => { stats = s; updateQuestPanel(); });
  socket.on('xp', ({ amount }) => {
    const me = players[myId];
    if (me) floaters.push({ x: me.rx, y: me.ry - 50, text: `+${amount} XP`, color: '230,200,90', t: 0 });
  });
  socket.on('levelUp', ({ level }) => { levelUp = { level, t: 0 }; });
  socket.on('questComplete', ({ reward }) => toast(`Görev tamamlandı! +${reward} XP`, '#e6c35a'));
  socket.on('dialog', (d) => { dialog = { ...d, until: performance.now() + 7000 }; });
  socket.on('event', (e) => { banner = { ...e, t: 0 }; });
  socket.on('blessed', ({ duration }) => toast(`R'hllor seni kutsadı! ${duration} sn x2 hasar ve hız`, '#ff6a2a'));
  requestAnimationFrame(loop);
}

function toast(text, color) { toasts.push({ text, color, t: 0 }); }

function updateQuestPanel() {
  const el = document.getElementById('quest'), q = stats.quest;
  el.innerHTML = q
    ? `<div class="qt">${q.title}</div>Gece Nöbetçisi Komutanı için düşman ya da hain öldür.<div class="qp">Öldürülen: <b>${q.kills}/${q.need}</b></div>`
    : `<div class="qt">Görev yok</div>Kamptaki <span style="color:#e6c35a">Gece Nöbetçisi Komutanı</span> ile konuş <b>[E]</b>${stats.questsDone ? `<div class="qp">Tamamlanan: ${stats.questsDone}</div>` : ''}`;
}

const nearNpc = (me) => npc && me && !me.dead && Math.hypot(me.x - npc.x, me.y - npc.y) <= npc.range;

// ---------------- Input ----------------
addEventListener('keydown', (e) => {
  const k = e.key.toLowerCase();
  keys[k] = true;
  if (k === 'e' && !e.repeat && socket && nearNpc(players[myId])) socket.emit('talk');
});
addEventListener('keyup', (e) => { keys[e.key.toLowerCase()] = false; });
addEventListener('blur', () => { for (const k in keys) keys[k] = false; });
addEventListener('mousemove', (e) => { mouse.x = e.clientX; mouse.y = e.clientY; });
canvas.addEventListener('mousedown', (e) => {
  const me = players[myId];
  if (e.button !== 0 || !me || me.dead) return;
  const now = performance.now();
  if (now < nextAttack) return;
  nextAttack = now + CLASSES[me.cls].attack.cooldown * 1000;
  socket.emit('attack', { angle: Math.atan2(mouse.y - canvas.height / 2, mouse.x - canvas.width / 2) });
});

// ---------------- Loop ----------------
function loop(now) {
  const dt = Math.min(0.05, (now - last) / 1000); last = now;
  const me = players[myId];
  if (me && !me.dead && tiles) {
    const dx = (keys.d ? 1 : 0) - (keys.a ? 1 : 0), dy = (keys.s ? 1 : 0) - (keys.w ? 1 : 0);
    if (dx || dy) {
      const len = Math.hypot(dx, dy), sp = CLASSES[me.cls].speed * (me.buffed ? 2 : 1);
      Object.assign(me, World.moveCircle(tiles, me.x, me.y, dx / len * sp * dt, dy / len * sp * dt, PLAYER_RADIUS));
    }
    me.rx = me.x; me.ry = me.y;
    sendTimer += dt;
    if (sendTimer > 0.05) { sendTimer = 0; socket.emit('move', { x: me.x, y: me.y }); }
  }
  for (const id in players) if (id !== myId) {
    const p = players[id]; p.rx += (p.x - p.rx) * 0.25; p.ry += (p.y - p.ry) * 0.25;
  }
  for (const id in enemies) { const e = enemies[id]; e.rx += (e.x - e.rx) * 0.25; e.ry += (e.y - e.ry) * 0.25; }
  for (const a of arrows) { a.x += a.vx * dt; a.y += a.vy * dt; }
  for (const f of effects) f.t += dt;
  for (const f of floaters) { f.t += dt; f.y -= 30 * dt; }
  for (const t of toasts) t.t += dt;
  if (banner) banner.t += dt;
  if (levelUp) levelUp.t += dt;
  for (let i = effects.length - 1; i >= 0; i--) if (effects[i].t > 0.6) effects.splice(i, 1);
  while (floaters.length && floaters[0].t > 1) floaters.shift();
  while (toasts.length && toasts[0].t > 3.5) toasts.shift();
  render(me, now / 1000);
  requestAnimationFrame(loop);
}

// ---------------- Rendering ----------------
function buildMinimap() {
  minimap = document.createElement('canvas');
  minimap.width = World.W; minimap.height = World.H;
  const m = minimap.getContext('2d');
  const MM_COLORS = ['#2e3d26', '#4a3c2b', '#77777f', '#17301c', '#1d3a55'];
  for (let y = 0; y < World.H; y++) for (let x = 0; x < World.W; x++) {
    m.fillStyle = MM_COLORS[tiles[y * World.W + x]];
    m.fillRect(x, y, 1, 1);
  }
}

function healthBar(x, y, w, hp, maxHp) {
  const ratio = Math.max(0, hp / maxHp);
  ctx.fillStyle = '#300'; ctx.fillRect(x - w / 2, y, w, 4);
  ctx.fillStyle = ratio > 0.5 ? '#3c3' : ratio > 0.25 ? '#cc3' : '#c22';
  ctx.fillRect(x - w / 2, y, w * ratio, 4);
}

function label(text, x, y, color, font) {
  ctx.font = font || '12px Georgia'; ctx.textAlign = 'center';
  ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillText(text, x + 1, y + 1);
  ctx.fillStyle = color; ctx.fillText(text, x, y);
}

function drawWorld(cx, cy, time) {
  const vw = canvas.width, vh = canvas.height;
  const x0 = Math.max(0, Math.floor(cx / TILE)), x1 = Math.min(World.W - 1, Math.floor((cx + vw) / TILE));
  const y0 = Math.max(0, Math.floor(cy / TILE)), y1 = Math.min(World.H - 1, Math.floor((cy + vh) / TILE));
  for (let ty = y0; ty <= y1; ty++) for (let tx = x0; tx <= x1; tx++) {
    const t = tiles[ty * World.W + tx], px = tx * TILE, py = ty * TILE;
    const img = sprites[TILE_SPRITES[t]];
    if (img) ctx.drawImage(img, px, py, TILE + 1, TILE + 1);
    else { ctx.fillStyle = TILE_COLORS[t]; ctx.fillRect(px, py, TILE + 1, TILE + 1); }
    if (((tx * 7 + ty * 13) % 5) === 0) { ctx.fillStyle = 'rgba(0,0,0,0.12)'; ctx.fillRect(px, py, TILE, TILE); }
  }
  // Trees overhang their tile a little, so draw them after the ground
  for (let ty = y0; ty <= y1; ty++) for (let tx = x0; tx <= x1; tx++) {
    if (tiles[ty * World.W + tx] !== World.T.TREE) continue;
    const px = tx * TILE + TILE / 2, py = ty * TILE + TILE / 2 - 6;
    if (!drawSprite('tree', px, py, TILE * 1.35)) {
      ctx.fillStyle = TILE_COLORS[3]; ctx.beginPath(); ctx.moveTo(px, py - 22); ctx.lineTo(px + 18, py + 18); ctx.lineTo(px - 18, py + 18); ctx.fill();
    }
  }
  // Red Priest fires
  for (const f of fires) {
    const flicker = 1 + Math.sin(time * 12 + f.id) * 0.06;
    const g = ctx.createRadialGradient(f.x, f.y, 4, f.x, f.y, 90);
    g.addColorStop(0, 'rgba(255,120,40,0.45)'); g.addColorStop(1, 'rgba(255,60,20,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(f.x, f.y, 90, 0, Math.PI * 2); ctx.fill();
    if (!drawSprite('fire', f.x, f.y - 8, 52 * flicker)) { ctx.fillStyle = '#ff5a1a'; ctx.beginPath(); ctx.arc(f.x, f.y, 16 * flicker, 0, Math.PI * 2); ctx.fill(); }
  }
}

function render(me, time) {
  const vw = canvas.width, vh = canvas.height;
  ctx.fillStyle = '#050506'; ctx.fillRect(0, 0, vw, vh);
  if (!tiles) return;
  const cx = Math.round((me ? me.rx : map.w / 2) - vw / 2), cy = Math.round((me ? me.ry : map.h / 2) - vh / 2);
  ctx.save(); ctx.translate(-cx, -cy);
  drawWorld(cx, cy, time);

  // Quest giver
  if (npc) {
    ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.beginPath(); ctx.ellipse(npc.x, npc.y + 18, 16, 6, 0, 0, Math.PI * 2); ctx.fill();
    if (!drawSprite('commander', npc.x, npc.y, 48)) drawShape(ctx, 'square', '#111', npc.x, npc.y, 16);
    label(npc.name, npc.x, npc.y - 32, '#e6c35a');
    const near = nearNpc(me);
    if (near) label('[E] Konuş', npc.x, npc.y - 48, '#e8dcb5', 'bold 13px Georgia');
    if (!stats.quest) label('!', npc.x, npc.y - (near ? 66 : 48) + Math.sin(time * 4) * 3, '#ffd23a', 'bold 22px Georgia');
  }

  // White Walkers
  for (const id in enemies) {
    const e = enemies[id], def = ENEMIES[e.type];
    const g = ctx.createRadialGradient(e.rx, e.ry, 4, e.rx, e.ry, 46);
    g.addColorStop(0, 'rgba(150,210,255,0.35)'); g.addColorStop(1, 'rgba(150,210,255,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(e.rx, e.ry, 46, 0, Math.PI * 2); ctx.fill();
    if (!drawSprite(def.sprite, e.rx, e.ry, 60)) drawShape(ctx, 'circle', '#bfe6ff', e.rx, e.ry, def.radius);
    healthBar(e.rx, e.ry - 38, 50, e.hp, e.maxHp);
    label(def.name, e.rx, e.ry - 44, '#bfe6ff', 'bold 12px Georgia');
  }

  // Players
  for (const id in players) {
    const p = players[id], k = CLASSES[p.cls];
    if (p.dead) continue;
    if (p.buffed) {
      ctx.strokeStyle = `rgba(255,${100 + Math.sin(time * 10) * 50},30,0.8)`; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(p.rx, p.ry, 24, 0, Math.PI * 2); ctx.stroke();
    }
    ctx.fillStyle = k.color + '99'; ctx.beginPath(); ctx.ellipse(p.rx, p.ry + 17, 15, 5, 0, 0, Math.PI * 2); ctx.fill();
    if (!drawSprite(k.sprite, p.rx, p.ry, 44)) drawShape(ctx, k.shape, k.color, p.rx, p.ry, PLAYER_RADIUS);
    healthBar(p.rx, p.ry - 30, 34, p.hp, p.maxHp);
    label(`${p.name} · Sv ${p.level}`, p.rx, p.ry - 35, id === myId ? '#e8dcb5' : '#a89f8b');
  }

  // Arrows
  ctx.lineWidth = 2;
  for (const a of arrows) {
    const ang = Math.atan2(a.vy, a.vx);
    ctx.strokeStyle = '#8b5a2b'; ctx.beginPath(); ctx.moveTo(a.x - Math.cos(ang) * 14, a.y - Math.sin(ang) * 14); ctx.lineTo(a.x, a.y); ctx.stroke();
    ctx.fillStyle = '#e0c040'; ctx.beginPath(); ctx.arc(a.x, a.y, 2, 0, Math.PI * 2); ctx.fill();
  }

  // Effects
  for (const f of effects) {
    const life = Math.min(1, f.t / 0.5);
    if (f.type === 'slash' || f.type === 'frost') {
      ctx.strokeStyle = f.type === 'slash' ? `rgba(255,255,255,${1 - life})` : `rgba(170,225,255,${1 - life})`;
      ctx.lineWidth = f.type === 'slash' ? 5 : 7;
      ctx.beginPath(); ctx.arc(f.x, f.y, f.range * (0.7 + life * 0.3), f.angle - f.arc / 2, f.angle + f.arc / 2); ctx.stroke();
    } else if (f.type === 'nova') {
      const r = f.range * Math.min(1, life * 1.6);
      const g = ctx.createRadialGradient(f.x, f.y, r * 0.3, f.x, f.y, Math.max(1, r));
      g.addColorStop(0, `rgba(60,255,90,${0.05 * (1 - life)})`); g.addColorStop(1, `rgba(40,230,70,${0.55 * (1 - life)})`);
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(f.x, f.y, r, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = `rgba(150,255,120,${1 - life})`; ctx.lineWidth = 3; ctx.stroke();
    } else if (f.type === 'levelup') {
      ctx.strokeStyle = `rgba(255,210,80,${1 - life})`; ctx.lineWidth = 4;
      ctx.beginPath(); ctx.arc(f.x, f.y, 20 + life * 50, 0, Math.PI * 2); ctx.stroke();
    } else if (f.type === 'shatter') {
      ctx.fillStyle = `rgba(200,235,255,${1 - life})`;
      for (let i = 0; i < 10; i++) {
        const a = i * 0.63, d = 10 + life * 60;
        ctx.fillRect(f.x + Math.cos(a) * d - 3, f.y + Math.sin(a) * d - 3, 6, 6);
      }
    }
  }
  for (const f of floaters) label(f.text, f.x, f.y, `rgba(${f.color},${1 - f.t})`, 'bold 14px Georgia');
  ctx.restore();

  // Vignette
  const g = ctx.createRadialGradient(vw / 2, vh / 2, vh * 0.25, vw / 2, vh / 2, vh * 0.85);
  g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.7)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, vw, vh);

  if (me) drawHud(me, time);
}

function panel(x, y, w, h) {
  ctx.fillStyle = 'rgba(10,10,12,0.8)'; ctx.fillRect(x, y, w, h);
  ctx.strokeStyle = '#3a352c'; ctx.lineWidth = 1; ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
}

function bar(x, y, w, h, ratio, color) {
  ctx.fillStyle = '#111'; ctx.fillRect(x, y, w, h);
  ctx.fillStyle = color; ctx.fillRect(x, y, w * Math.max(0, Math.min(1, ratio)), h);
  ctx.strokeStyle = '#3a352c'; ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
}

function drawHud(me, time) {
  const vw = canvas.width, vh = canvas.height, k = CLASSES[me.cls], now = performance.now();

  // Character panel
  panel(12, 12, 230, 92);
  ctx.textAlign = 'left'; ctx.font = 'bold 14px Georgia'; ctx.fillStyle = '#e8dcb5';
  ctx.fillText(`${me.name} — Seviye ${stats.level}`, 22, 32);
  ctx.font = 'italic 12px Georgia'; ctx.fillStyle = '#857c6a'; ctx.fillText(k.name, 22, 48);
  bar(22, 56, 210, 12, me.hp / me.maxHp, '#a8201f');
  bar(22, 74, 210, 8, stats.xp / stats.xpNext, '#c9a24a');
  ctx.font = '10px Georgia'; ctx.fillStyle = '#e8dcb5';
  ctx.fillText(`HP ${Math.ceil(me.hp)}/${me.maxHp}`, 26, 66);
  ctx.fillText(`XP ${stats.xp}/${stats.xpNext}`, 22, 96);
  ctx.textAlign = 'right'; ctx.fillStyle = '#857c6a';
  ctx.fillText(`Hasar x${(stats.dmgMult || 1).toFixed(2)}${me.buffed ? ' · KUTSANMIŞ' : ''}`, 232, 96);

  // Cooldown
  const cd = k.attack.cooldown * 1000, left = Math.max(0, nextAttack - now);
  bar(vw / 2 - 80, vh - 30, 160, 8, 1 - left / cd, left ? '#665533' : '#c9a24a');

  // Minimap
  if (minimap) {
    const s = Math.min(160, Math.floor(vw * 0.3)), mx = vw - s - 12, my = vh - s - 12, sc = s / map.w;
    panel(mx - 4, my - 4, s + 8, s + 8);
    ctx.imageSmoothingEnabled = false; ctx.drawImage(minimap, mx, my, s, s); ctx.imageSmoothingEnabled = true;
    const dot = (x, y, c, r) => { ctx.fillStyle = c; ctx.beginPath(); ctx.arc(mx + x * sc, my + y * sc, r, 0, Math.PI * 2); ctx.fill(); };
    if (npc) dot(npc.x, npc.y, '#ffd23a', 3);
    for (const f of fires) dot(f.x, f.y, Math.sin(time * 8) > 0 ? '#ff6a2a' : '#ffc22a', 4);
    for (const id in enemies) dot(enemies[id].rx, enemies[id].ry, '#bfe6ff', 4);
    for (const id in players) if (!players[id].dead) dot(players[id].rx, players[id].ry, id === myId ? '#fff' : CLASSES[players[id].cls].color, id === myId ? 3.5 : 2.5);
  }

  // NPC dialog
  if (dialog && now < dialog.until) {
    const w = Math.min(560, vw - 32), x = vw / 2 - w / 2, y = vh - 130;
    panel(x, y, w, 80);
    ctx.textAlign = 'left'; ctx.font = 'bold 13px Georgia'; ctx.fillStyle = '#e6c35a'; ctx.fillText(dialog.name, x + 14, y + 22);
    ctx.font = '13px Georgia'; ctx.fillStyle = '#d8cfb8';
    wrapText(dialog.text, x + 14, y + 42, w - 28, 17);
  }

  // Toasts
  toasts.forEach((t, i) => {
    const a = t.t < 3 ? 1 : 1 - (t.t - 3) * 2;
    ctx.globalAlpha = Math.max(0, a);
    label(t.text, vw / 2, vh - 160 - i * 24, t.color, 'bold 16px Georgia');
    ctx.globalAlpha = 1;
  });

  // Random event banner
  if (banner && banner.t < 5) {
    const a = banner.t < 0.3 ? banner.t / 0.3 : banner.t > 4 ? 5 - banner.t : 1;
    const color = banner.type === 'walker' ? '#bfe6ff' : '#ff5a2a';
    ctx.globalAlpha = a;
    const size = Math.round(Math.min(60, vw / 13)), top = 120, base = top + 14 + size * 0.8;
    ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(0, top, vw, size + 52);
    ctx.shadowColor = color; ctx.shadowBlur = 24;
    label(banner.title, vw / 2, base, color, `bold ${size}px Georgia`);
    ctx.shadowBlur = 0;
    label(banner.sub, vw / 2, base + 30, '#d8cfb8', 'italic 16px Georgia');
    ctx.globalAlpha = 1;
  }

  // Level up
  if (levelUp && levelUp.t < 2.5) {
    const a = levelUp.t > 2 ? (2.5 - levelUp.t) * 2 : 1, s = 1 + Math.max(0, 0.3 - levelUp.t);
    ctx.globalAlpha = a;
    ctx.shadowColor = '#ffd23a'; ctx.shadowBlur = 20;
    label('SEVİYE ATLANDI', vw / 2, vh / 2 - 80, '#ffd23a', `bold ${Math.round(Math.min(52, vw / 14) * s)}px Georgia`);
    ctx.shadowBlur = 0;
    label(`Seviye ${levelUp.level} · Maks HP ve Hasar +%10`, vw / 2, vh / 2 - 50, '#e8dcb5', 'italic 16px Georgia');
    ctx.globalAlpha = 1;
  }

  // Death
  if (me.dead) {
    ctx.fillStyle = 'rgba(0,0,0,0.85)'; ctx.fillRect(0, 0, vw, vh);
    label('VALAR MORGHULIS', vw / 2, vh / 2, '#c81818', `bold ${Math.min(56, vw / 12)}px Georgia`);
    const secs = Math.max(0, Math.ceil((deadUntil - now) / 1000));
    label(`${killer} tarafından öldürüldün · ${secs}s içinde yeniden doğacaksın`, vw / 2, vh / 2 + 40, '#7d7566', 'italic 16px Georgia');
  }
}

function wrapText(text, x, y, maxW, lh) {
  let line = '';
  for (const word of text.split(' ')) {
    const test = line ? line + ' ' + word : word;
    if (ctx.measureText(test).width > maxW && line) { ctx.fillText(line, x, y); line = word; y += lh; }
    else line = test;
  }
  ctx.fillText(line, x, y);
}
