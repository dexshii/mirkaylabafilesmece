const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
let socket, myId, map = { w: 2000, h: 2000 };
const players = {};
const keys = {};
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
    hud.innerHTML = `<b>${players[myId].name}</b> — ${k.name}<br>HP ${k.hp} · Zırh ${k.armor} · Hız ${k.speed}<br><span style="color:#7d7566">WASD ile hareket et</span>`;
  });
  socket.on('playerJoined', (p) => { players[p.id] = { ...p, rx: p.x, ry: p.y }; });
  socket.on('playerLeft', (id) => { delete players[id]; });
  socket.on('state', (s) => {
    for (const id in s) if (players[id] && id !== myId) { players[id].x = s[id].x; players[id].y = s[id].y; }
  });
  requestAnimationFrame(loop);
}

addEventListener('keydown', (e) => { keys[e.key.toLowerCase()] = true; });
addEventListener('keyup', (e) => { keys[e.key.toLowerCase()] = false; });

// Deterministic scenery (stones, dead grass) so all clients see the same ground
const props = [];
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
for (let i = 0; i < 400; i++) props.push({ x: rnd() * 2000, y: rnd() * 2000, t: rnd() < 0.3 ? 'stone' : 'grass', s: 2 + rnd() * 6 });

function loop(now) {
  const dt = Math.min(0.05, (now - last) / 1000); last = now;
  const me = players[myId];
  if (me) {
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
    drawShape(ctx, k.shape, k.color, p.rx, p.ry, 14);
    ctx.fillStyle = id === myId ? '#e8dcb5' : '#9a917e'; ctx.font = '12px Georgia'; ctx.textAlign = 'center';
    ctx.fillText(p.name, p.rx, p.ry - 22);
  }
  ctx.restore();
  // Vignette for dark atmosphere
  const g = ctx.createRadialGradient(canvas.width / 2, canvas.height / 2, canvas.height * 0.2, canvas.width / 2, canvas.height / 2, canvas.height * 0.8);
  g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.75)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, canvas.width, canvas.height);
}
