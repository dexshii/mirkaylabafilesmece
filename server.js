const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');
const { CLASSES, PLAYER_RADIUS, RESPAWN_TIME, mitigate } = require('./server/classes');

const PORT = process.env.PORT || 3000;
const MAP = { w: 2000, h: 2000 };
const TICK = 50;

const app = express();
app.use(express.static(path.join(__dirname, 'public')));
app.get('/classes.js', (req, res) => res.sendFile(path.join(__dirname, 'server', 'classes.js')));

const server = http.createServer(app);
const io = new Server(server);
const players = {};
let projectiles = [];
let projId = 0;

const randPos = () => ({ x: 100 + Math.random() * (MAP.w - 200), y: 100 + Math.random() * (MAP.h - 200) });

function damage(attacker, target, amount) {
  if (target.dead || target.id === attacker.id) return;
  const dealt = mitigate(amount, CLASSES[target.cls].armor);
  target.hp = Math.max(0, target.hp - dealt);
  io.emit('hit', { id: target.id, amount: dealt });
  if (target.hp === 0) {
    target.dead = true;
    io.emit('died', { id: target.id, by: attacker.name });
    console.log(`x ${target.name} slain by ${attacker.name}`);
    setTimeout(() => {
      if (!players[target.id]) return;
      Object.assign(target, randPos(), { hp: CLASSES[target.cls].hp, dead: false });
      io.emit('respawn', { id: target.id, x: target.x, y: target.y, hp: target.hp });
    }, RESPAWN_TIME * 1000);
  }
}

io.on('connection', (socket) => {
  socket.on('join', ({ cls, name }) => {
    if (!CLASSES[cls] || players[socket.id]) return;
    players[socket.id] = {
      id: socket.id, cls,
      name: String(name || 'Yabancı').slice(0, 16),
      ...randPos(),
      hp: CLASSES[cls].hp, dead: false, nextAttack: 0
    };
    socket.emit('init', { id: socket.id, players, map: MAP });
    socket.broadcast.emit('playerJoined', players[socket.id]);
    console.log(`+ ${players[socket.id].name} (${cls})`);
  });

  socket.on('move', ({ x, y }) => {
    const p = players[socket.id];
    if (!p || p.dead || !Number.isFinite(x) || !Number.isFinite(y)) return;
    p.x = Math.max(0, Math.min(MAP.w, x));
    p.y = Math.max(0, Math.min(MAP.h, y));
  });

  socket.on('attack', ({ angle }) => {
    const p = players[socket.id];
    if (!p || p.dead || !Number.isFinite(angle)) return;
    const now = Date.now();
    const k = CLASSES[p.cls], atk = k.attack;
    if (now < p.nextAttack) return;
    p.nextAttack = now + atk.cooldown * 1000 - 30; // small latency tolerance

    if (atk.type === 'melee') {
      for (const id in players) {
        const t = players[id];
        const dx = t.x - p.x, dy = t.y - p.y;
        if (Math.hypot(dx, dy) > atk.range + PLAYER_RADIUS) continue;
        let diff = Math.atan2(dy, dx) - angle;
        diff = Math.atan2(Math.sin(diff), Math.cos(diff));
        if (Math.abs(diff) <= atk.arc / 2) damage(p, t, k.damage);
      }
      io.emit('fx', { type: 'slash', x: p.x, y: p.y, angle, range: atk.range, arc: atk.arc });
    } else if (atk.type === 'arrow') {
      projectiles.push({ id: ++projId, owner: p.id, x: p.x, y: p.y,
        vx: Math.cos(angle) * atk.projSpeed, vy: Math.sin(angle) * atk.projSpeed, left: atk.range });
    } else if (atk.type === 'nova') {
      for (const id in players) {
        const t = players[id];
        if (Math.hypot(t.x - p.x, t.y - p.y) <= atk.range + PLAYER_RADIUS) damage(p, t, k.magic);
      }
      io.emit('fx', { type: 'nova', x: p.x, y: p.y, range: atk.range });
    }
  });

  socket.on('disconnect', () => {
    if (!players[socket.id]) return;
    console.log(`- ${players[socket.id].name}`);
    delete players[socket.id];
    io.emit('playerLeft', socket.id);
  });
});

setInterval(() => {
  const dt = TICK / 1000;
  projectiles = projectiles.filter((a) => {
    // Sub-step so fast arrows don't tunnel through players
    const steps = 3;
    for (let i = 0; i < steps; i++) {
      a.x += a.vx * dt / steps; a.y += a.vy * dt / steps;
      a.left -= Math.hypot(a.vx, a.vy) * dt / steps;
      if (a.left <= 0 || a.x < 0 || a.y < 0 || a.x > MAP.w || a.y > MAP.h) return false;
      for (const id in players) {
        const t = players[id];
        if (id === a.owner || t.dead) continue;
        if (Math.hypot(t.x - a.x, t.y - a.y) <= PLAYER_RADIUS + 3) {
          const owner = players[a.owner];
          if (owner) damage(owner, t, CLASSES.archer.damage);
          return false;
        }
      }
    }
    return true;
  });

  const state = {};
  for (const id in players) { const p = players[id]; state[id] = { x: p.x, y: p.y, hp: p.hp, dead: p.dead }; }
  io.emit('state', { players: state, arrows: projectiles.map((a) => ({ id: a.id, x: a.x, y: a.y, vx: a.vx, vy: a.vy })) });
}, TICK);

server.listen(PORT, () => console.log(`Server running on http://localhost:${PORT}`));
