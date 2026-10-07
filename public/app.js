const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
let socket, myId, map = { w: 2000, h: 2000 };
const players = {};
const keys = {};
let arrows = [];
const effects = [];
const floaters = [];
const mouse = { x: 0, y: 0 };
let nextAttack = 0, deadUntil = 0, killer = '';
let last = performance.now(), sendTimer = 0;

function resize() { canvas.width = innerWidth; canvas.height = innerHeight; }
addEventListener('resize', resize); resize();

function drawShape(c, shape, color, x, y, r) {
  c.fillStyle = color; c.strokeStyle = '#000'; c.lineWidth = 2;
  c.beginPath();
  if (shape === 'square') c.rect(x - r, y - r, r * 2, r * 2);
  else if (shape === 'triangle') { c.moveTo(x, y - r); c.lineTo(x + r, y + r); c.lineTo(x - r, y + r); c.closePath(); }
  else c.arc(x, y, r, 0, Math.PI * 2);
  c.fill(); c.stroke();
}

// Class select screen
const cards = document.getElementById('cards');
for (const key in CLASSES) {
  const k = CLASSES[key];
  const card = document.createElement('div');
  card.className = 'card';
  const pv = document.createElement('canvas'); pv.width = pv.height = 60;
  drawShape(pv.getContext('2d'), k.shape, k.color, 30, 30, 18);
  card.appendChild(pv);
  card.insertAdjacentHTML('beforeend', `<h3>${k.name}</h3><div class="t">${k.title}</div>
    <div class="s">HP: ${k.hp}<br>Zırh: ${k.armor}<br>Çeviklik: ${k.agility}<br>Hasar: ${k.damage}<br>Büyü: ${k.magic}<br>Hız: ${k.speed}</div>`);
  card.onclick = () => start(key);
  cards.appendChild(card);
}

function start(cls) {
  document.getElementById('select').style.display = 'none';
  socket = io();
  socket.on('connect', () => socket.emit('join', { cls, name: document.getElementById('name').value.trim() }));
  socket.on('init', (d) => {
    myId = d.id; map = d.map;
    for (const id in players) delete players[id];
    for (const id in d.players) players[id] = { ...d.players[id], rx: d.players[id].x, ry: d.players[id].y };
    const hud = document.getElementById('hud'), k = CLASSES[cls];
    hud.style.display = 'block';
    hud.innerHTML = `<b>${players[myId].name}</b> — ${k.name}<br>HP ${k.hp} · Zırh ${k.armor} · Hız ${k.speed}<br><span style="color:#7d7566">WASD hareket · Sol tık saldırı</span>`;
  });
  socket.on('playerJoined', (p) => { players[p.id] = { ...p, rx: p.x, ry: p.y }; });
  socket.on('playerLeft', (id) => { delete players[id]; });
  socket.on('state', (s) => {
    for (const id in s.players) {
      const p = players[id], u = s.players[id];
      if (!p) continue;
      p.hp = u.hp; p.dead = u.dead;
      if (id !== myId) { p.x = u.x; p.y = u.y; }
    }
    arrows = s.arrows;
  });
  socket.on('fx', (f) => effects.push({ ...f, t: 0 }));
  socket.on('hit', ({ id, amount }) => {
    const p = players[id];
    if (p) floaters.push({ x: p.rx, y: p.ry - 30, text: '-' + amount, t: 0 });
  });
  socket.on('died', ({ id, by }) => {
    if (players[id]) players[id].dead = true;
    if (id === myId) { deadUntil = performance.now() + RESPAWN_TIME * 1000; killer = by; }
  });
  socket.on('respawn', ({ id, x, y, hp }) => {
    const p = players[id];
    if (!p) return;
    Object.assign(p, { x, y, rx: x, ry: y, hp, dead: false });
  });
  requestAnimationFrame(loop);
}

addEventListener('keydown', (e) => { keys[e.key.toLowerCase()] = true; });
addEventListener('mousemove', (e) => { mouse.x = e.clientX; mouse.y = e.clientY; });
canvas.addEventListener('mousedown', (e) => {
  const me = players[myId];
  if (e.button !== 0 || !me || me.dead) return;
  const now = performance.now();
  if (now < nextAttack) return;
  nextAttack = now + CLASSES[me.cls].attack.cooldown * 1000;
  socket.emit('attack', { angle: Math.atan2(mouse.y - canvas.height / 2, mouse.x - canvas.width / 2) });
});
addEventListener('keyup', (e) => { keys[e.key.toLowerCase()] = false; });

// Deterministic scenery (stones, dead grass) so all clients see the same ground
const props = [];
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
for (let i = 0; i < 400; i++) props.push({ x: rnd() * 2000, y: rnd() * 2000, t: rnd() < 0.3 ? 'stone' : 'grass', s: 2 + rnd() * 6 });

function loop(now) {
  const dt = Math.min(0.05, (now - last) / 1000); last = now;
  const me = players[myId];
  if (me && !me.dead) {
    let dx = (keys.d ? 1 : 0) - (keys.a ? 1 : 0), dy = (keys.s ? 1 : 0) - (keys.w ? 1 : 0);
    if (dx || dy) {
      const len = Math.hypot(dx, dy), sp = CLASSES[me.cls].speed;
      me.x = Math.max(0, Math.min(map.w, me.x + dx / len * sp * dt));
      me.y = Math.max(0, Math.min(map.h, me.y + dy / len * sp * dt));
    }
    me.rx = me.x; me.ry = me.y;
    sendTimer += dt;
    if (sendTimer > 0.05) { sendTimer = 0; socket.emit('move', { x: me.x, y: me.y }); }
  }
  for (const id in players) if (id !== myId) {
    const p = players[id]; p.rx += (p.x - p.rx) * 0.25; p.ry += (p.y - p.ry) * 0.25;
  }
  for (const a of arrows) { a.x += a.vx * dt; a.y += a.vy * dt; }
  for (const f of effects) f.t += dt;
  for (const f of floaters) { f.t += dt; f.y -= 30 * dt; }
  while (effects.length && effects[0].t > 0.5) effects.shift();
  while (floaters.length && floaters[0].t > 0.8) floaters.shift();
  render(me);
  requestAnimationFrame(loop);
}

function render(me) {
  const cx = me ? me.rx - canvas.width / 2 : 0, cy = me ? me.ry - canvas.height / 2 : 0;
  ctx.fillStyle = '#050506'; ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.save(); ctx.translate(-cx, -cy);
  ctx.fillStyle = '#1b1b1e'; ctx.fillRect(0, 0, map.w, map.h);
  ctx.strokeStyle = '#232327'; ctx.lineWidth = 1;
  for (let x = 0; x <= map.w; x += 64) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, map.h); ctx.stroke(); }
  for (let y = 0; y <= map.h; y += 64) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(map.w, y); ctx.stroke(); }
  for (const p of props) {
    if (p.t === 'stone') { ctx.fillStyle = '#2b2a2d'; ctx.beginPath(); ctx.arc(p.x, p.y, p.s, 0, 7); ctx.fill(); }
    else { ctx.strokeStyle = '#2d3326'; ctx.beginPath(); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x - 2, p.y - p.s * 1.5); ctx.moveTo(p.x, p.y); ctx.lineTo(p.x + 2, p.y - p.s * 1.5); ctx.stroke(); }
  }
  ctx.strokeStyle = '#4a1414'; ctx.lineWidth = 4; ctx.strokeRect(0, 0, map.w, map.h);
  for (const id in players) {
    const p = players[id], k = CLASSES[p.cls];
    if (p.dead) continue;
    drawShape(ctx, k.shape, k.color, p.rx, p.ry, PLAYER_RADIUS);
    // Health bar
    const ratio = Math.max(0, p.hp / k.hp), bw = 32;
    ctx.fillStyle = '#300'; ctx.fillRect(p.rx - bw / 2, p.ry - 24, bw, 4);
    ctx.fillStyle = ratio > 0.5 ? '#3c3' : ratio > 0.25 ? '#cc3' : '#c22';
    ctx.fillRect(p.rx - bw / 2, p.ry - 24, bw * ratio, 4);
    ctx.fillStyle = id === myId ? '#e8dcb5' : '#9a917e'; ctx.font = '12px Georgia'; ctx.textAlign = 'center';
    ctx.fillText(p.name, p.rx, p.ry - 30);
  }
  // Arrows
  ctx.lineWidth = 2;
  for (const a of arrows) {
    const ang = Math.atan2(a.vy, a.vx);
    ctx.strokeStyle = '#8b5a2b'; ctx.beginPath(); ctx.moveTo(a.x - Math.cos(ang) * 14, a.y - Math.sin(ang) * 14); ctx.lineTo(a.x, a.y); ctx.stroke();
    ctx.fillStyle = '#e0c040'; ctx.beginPath(); ctx.arc(a.x, a.y, 2, 0, 7); ctx.fill();
  }
  // Attack effects
  for (const f of effects) {
    const life = f.t / 0.5;
    if (f.type === 'slash') {
      ctx.strokeStyle = `rgba(255,255,255,${1 - life})`; ctx.lineWidth = 5;
      ctx.beginPath(); ctx.arc(f.x, f.y, f.range * (0.7 + life * 0.3), f.angle - f.arc / 2, f.angle + f.arc / 2); ctx.stroke();
    } else if (f.type === 'nova') {
      const r = f.range * Math.min(1, life * 1.6);
      const g = ctx.createRadialGradient(f.x, f.y, r * 0.3, f.x, f.y, r);
      g.addColorStop(0, `rgba(60,255,90,${0.05 * (1 - life)})`); g.addColorStop(1, `rgba(40,230,70,${0.55 * (1 - life)})`);
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(f.x, f.y, r, 0, 7); ctx.fill();
      ctx.strokeStyle = `rgba(150,255,120,${1 - life})`; ctx.lineWidth = 3; ctx.stroke();
    }
  }
  ctx.font = 'bold 14px Georgia'; ctx.textAlign = 'center';
  for (const f of floaters) { ctx.fillStyle = `rgba(255,70,50,${1 - f.t / 0.8})`; ctx.fillText(f.text, f.x, f.y); }
  ctx.restore();
  // Vignette for dark atmosphere
  const g = ctx.createRadialGradient(canvas.width / 2, canvas.height / 2, canvas.height * 0.2, canvas.width / 2, canvas.height / 2, canvas.height * 0.8);
  g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.75)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, canvas.width, canvas.height);
  if (me) {
    // Cooldown bar
    const cd = CLASSES[me.cls].attack.cooldown * 1000, left = Math.max(0, nextAttack - performance.now());
    const w = 160, x = canvas.width / 2 - w / 2, y = canvas.height - 30;
    ctx.fillStyle = '#111'; ctx.fillRect(x, y, w, 8);
    ctx.fillStyle = left ? '#665533' : '#c9a24a'; ctx.fillRect(x, y, w * (1 - left / cd), 8);
    ctx.strokeStyle = '#3a352c'; ctx.strokeRect(x, y, w, 8);
  }
  if (me && me.dead) {
    ctx.fillStyle = 'rgba(0,0,0,0.85)'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#c81818'; ctx.font = 'bold 56px Georgia'; ctx.textAlign = 'center';
    ctx.fillText('VALAR MORGHULIS', canvas.width / 2, canvas.height / 2);
    ctx.fillStyle = '#7d7566'; ctx.font = 'italic 16px Georgia';
    const secs = Math.max(0, Math.ceil((deadUntil - performance.now()) / 1000));
    ctx.fillText(`${killer} tarafından öldürüldün · ${secs}s içinde yeniden doğacaksın`, canvas.width / 2, canvas.height / 2 + 40);
  }
}
