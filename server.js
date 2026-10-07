const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');
const { CLASSES, ENEMIES, PLAYER_RADIUS, RESPAWN_TIME, QUEST, xpNeeded, mitigate } = require('./server/classes');
const World = require('./server/world');

const PORT = process.env.PORT || 3000;
const DEV = process.env.DEV === '1'; // enables debug socket commands for local testing
const TICK = 50;
const MAX_WALKERS = 3;
const FIRE_DURATION = 30000;
const BUFF_DURATION = 10000;

const tiles = World.generate(1337);
const MAP = { w: World.W * World.TILE, h: World.H * World.TILE };
const CENTER = { x: MAP.w / 2, y: MAP.h / 2 };
const NPC = { name: 'Gece Nöbetçisi Komutanı', x: CENTER.x, y: CENTER.y - World.TILE * 3, range: 90 };

const app = express();
app.use(express.static(path.join(__dirname, 'public')));
app.get('/classes.js', (req, res) => res.sendFile(path.join(__dirname, 'server', 'classes.js')));
app.get('/world.js', (req, res) => res.sendFile(path.join(__dirname, 'server', 'world.js')));

const server = http.createServer(app);
const io = new Server(server);
const players = {};
const enemies = {};
let projectiles = [];
let fires = [];
let nextId = 0;

// Random passable position; radiusTiles limits it to an area around the map center
function randPos(radiusTiles) {
  for (let i = 0; i < 1000; i++) {
    const tx = radiusTiles ? World.W / 2 + Math.round((Math.random() * 2 - 1) * radiusTiles) : 1 + Math.floor(Math.random() * (World.W - 2));
    const ty = radiusTiles ? World.H / 2 + Math.round((Math.random() * 2 - 1) * radiusTiles) : 1 + Math.floor(Math.random() * (World.H - 2));
    const x = (tx + 0.5) * World.TILE, y = (ty + 0.5) * World.TILE;
    if (!World.collides(tiles, x, y, 20)) return { x, y };
  }
  return { ...CENTER };
}

const isBuffed = (p) => p.buffUntil > Date.now();
const speedOf = (p) => CLASSES[p.cls].speed * (isBuffed(p) ? 2 : 1);
const powerOf = (p, base) => base * p.dmgMult * (isBuffed(p) ? 2 : 1);

const publicPlayer = (p) => ({ id: p.id, cls: p.cls, name: p.name, x: p.x, y: p.y, hp: p.hp, maxHp: p.maxHp, level: p.level, dead: p.dead, buffed: isBuffed(p) });
const publicEnemy = (e) => ({ id: e.id, type: e.type, x: e.x, y: e.y, hp: e.hp, maxHp: e.maxHp });
const mapOf = (obj, fn) => Object.fromEntries(Object.entries(obj).map(([id, v]) => [id, fn(v)]));

function sendStats(p) {
  io.to(p.id).emit('stats', { level: p.level, xp: p.xp, xpNext: xpNeeded(p.level), maxHp: p.maxHp, dmgMult: p.dmgMult, quest: p.quest, questsDone: p.questsDone });
}

function gainXp(p, amount) {
  p.xp += amount;
  io.to(p.id).emit('xp', { amount });
  while (p.xp >= xpNeeded(p.level)) {
    p.xp -= xpNeeded(p.level);
    p.level++;
    p.maxHp = Math.round(p.maxHp * 1.1);
    p.dmgMult *= 1.1;
    if (!p.dead) p.hp = p.maxHp;
    io.to(p.id).emit('levelUp', { level: p.level });
    io.emit('fx', { type: 'levelup', x: p.x, y: p.y });
  }
  sendStats(p);
}

function creditKill(killer, victim) {
  if (!killer.isPlayer || !players[killer.id]) return;
  let xp = victim.isPlayer ? 50 + 10 * victim.level : ENEMIES[victim.type].xp;
  const q = killer.quest;
  if (q) {
    q.kills++;
    if (q.kills >= q.need) {
      killer.quest = null;
      killer.questsDone++;
      xp += QUEST.reward;
      io.to(killer.id).emit('questComplete', { reward: QUEST.reward });
    }
  }
  gainXp(killer, xp);
}

function damage(attacker, target, amount) {
  if (target.dead || target === attacker) return;
  const dealt = mitigate(amount, target.armor);
  target.hp = Math.max(0, target.hp - dealt);
  io.emit('hit', { id: target.id, amount: dealt });
  if (target.hp > 0) return;
  target.dead = true;
  io.emit('died', { id: target.id, by: attacker.name, enemy: !target.isPlayer });
  console.log(`x ${target.name} slain by ${attacker.name}`);
  creditKill(attacker, target);
  if (!target.isPlayer) { delete enemies[target.id]; return; }
  setTimeout(() => {
    if (!players[target.id]) return;
    Object.assign(target, randPos(), { hp: target.maxHp, dead: false, buffUntil: 0, lastMove: Date.now() });
    io.emit('respawn', { id: target.id, x: target.x, y: target.y, hp: target.hp });
  }, RESPAWN_TIME * 1000);
}

// Everything p can hit: other living players and all enemies
function* targetsFor(p) {
  for (const id in players) { const t = players[id]; if (t !== p && !t.dead) yield t; }
  for (const id in enemies) yield enemies[id];
}

// ---------------- Random events ----------------
const EVENTS = {
  walker() {
    const def = ENEMIES.walker, pos = randPos(28);
    const e = { id: 'e' + (++nextId), type: 'walker', name: def.name, ...pos, hp: def.hp, maxHp: def.hp, armor: def.armor, radius: def.radius, dead: false, nextAttack: 0 };
    enemies[e.id] = e;
    io.emit('event', { type: 'walker', title: 'KIŞ GELİYOR!', sub: 'Bir Ak Gezen buzların arasından uyandı...', x: e.x, y: e.y });
  },
  fire() {
    const pos = randPos(22);
    fires.push({ id: ++nextId, ...pos, expires: Date.now() + FIRE_DURATION });
    io.emit('event', { type: 'fire', title: 'KIRMIZI RAHİP KUTSAMASI', sub: "R'hllor'un ateşi yandı! Üzerinden geç: 10 sn x2 hasar ve hız", x: pos.x, y: pos.y });
  }
};

function triggerEvent(type) {
  type = EVENTS[type] ? type : (Math.random() < 0.5 ? 'walker' : 'fire');
  if (type === 'walker' && Object.keys(enemies).length >= MAX_WALKERS) type = 'fire';
  EVENTS[type]();
  console.log(`! event: ${type}`);
}

(function scheduleEvent() {
  setTimeout(() => { triggerEvent(); scheduleEvent(); }, 30000 + Math.random() * 30000);
})();

// ---------------- Connections ----------------
io.on('connection', (socket) => {
  socket.on('join', ({ cls, name } = {}) => {
    if (!CLASSES[cls] || players[socket.id]) return;
    const k = CLASSES[cls];
    const p = players[socket.id] = {
      id: socket.id, isPlayer: true, cls,
      name: String(name || 'Yabancı').slice(0, 16),
      ...randPos(12), radius: PLAYER_RADIUS, armor: k.armor,
      hp: k.hp, maxHp: k.hp, dmgMult: 1, level: 1, xp: 0,
      dead: false, nextAttack: 0, buffUntil: 0, lastMove: Date.now(),
      quest: null, questsDone: 0
    };
    socket.emit('init', {
      id: socket.id, map: MAP, tiles, npc: NPC,
      players: mapOf(players, publicPlayer), enemies: mapOf(enemies, publicEnemy),
      fires: fires.map(({ id, x, y }) => ({ id, x, y }))
    });
    sendStats(p);
    socket.broadcast.emit('playerJoined', publicPlayer(p));
    console.log(`+ ${p.name} (${cls})`);
  });

  socket.on('move', ({ x, y } = {}) => {
    const p = players[socket.id];
    if (!p || p.dead || !Number.isFinite(x) || !Number.isFinite(y)) return;
    const now = Date.now();
    const elapsed = Math.min(1, (now - p.lastMove) / 1000);
    p.lastMove = now;
    const maxDist = speedOf(p) * (elapsed + 0.1) * 1.25 + 8;
    if (Math.hypot(x - p.x, y - p.y) > maxDist || World.collides(tiles, x, y, PLAYER_RADIUS)) {
      socket.emit('pos', { x: p.x, y: p.y }); // reject and resync the client
      return;
    }
    p.x = x; p.y = y;
  });

  socket.on('attack', ({ angle } = {}) => {
    const p = players[socket.id];
    if (!p || p.dead || !Number.isFinite(angle)) return;
    const now = Date.now();
    const k = CLASSES[p.cls], atk = k.attack;
    if (now < p.nextAttack) return;
    p.nextAttack = now + atk.cooldown * 1000 - 30; // small latency tolerance

    if (atk.type === 'melee') {
      for (const t of targetsFor(p)) {
        const dx = t.x - p.x, dy = t.y - p.y;
        if (Math.hypot(dx, dy) > atk.range + t.radius) continue;
        let diff = Math.atan2(dy, dx) - angle;
        diff = Math.atan2(Math.sin(diff), Math.cos(diff));
        if (Math.abs(diff) <= atk.arc / 2) damage(p, t, powerOf(p, k.damage));
      }
      io.emit('fx', { type: 'slash', x: p.x, y: p.y, angle, range: atk.range, arc: atk.arc });
    } else if (atk.type === 'arrow') {
      projectiles.push({ id: ++nextId, owner: p, x: p.x, y: p.y, dmg: powerOf(p, k.damage),
        vx: Math.cos(angle) * atk.projSpeed, vy: Math.sin(angle) * atk.projSpeed, left: atk.range });
    } else if (atk.type === 'nova') {
      for (const t of [...targetsFor(p)]) {
        if (Math.hypot(t.x - p.x, t.y - p.y) <= atk.range + t.radius) damage(p, t, powerOf(p, k.magic));
      }
      io.emit('fx', { type: 'nova', x: p.x, y: p.y, range: atk.range });
    }
  });

  socket.on('talk', () => {
    const p = players[socket.id];
    if (!p || p.dead || Math.hypot(p.x - NPC.x, p.y - NPC.y) > NPC.range) return;
    let text;
    if (!p.quest) {
      p.quest = { title: QUEST.title, kills: 0, need: QUEST.need };
      text = `Kış geliyor, kardeşim. Sur her gece biraz daha zayıflıyor. Bana ${QUEST.need} düşman ya da hain öldür; ödülün ${QUEST.reward} deneyim olsun.`;
    } else {
      text = `Daha ${p.quest.need - p.quest.kills} kelle lazım. Gece karanlık ve dehşet dolu.`;
    }
    socket.emit('dialog', { name: NPC.name, text });
    sendStats(p);
  });

  if (DEV) {
    socket.on('dev', ({ cmd, x, y, type, amount } = {}) => {
      const p = players[socket.id];
      if (!p) return;
      if (cmd === 'tp') { p.x = x; p.y = y; p.lastMove = Date.now(); socket.emit('pos', { x, y }); }
      if (cmd === 'event') triggerEvent(type);
      if (cmd === 'xp') gainXp(p, amount);
    });
  }

  socket.on('disconnect', () => {
    if (!players[socket.id]) return;
    console.log(`- ${players[socket.id].name}`);
    delete players[socket.id];
    io.emit('playerLeft', socket.id);
  });
});

// ---------------- Simulation tick ----------------
setInterval(() => {
  const dt = TICK / 1000, now = Date.now();

  // Arrows (sub-stepped so fast arrows don't tunnel)
  projectiles = projectiles.filter((a) => {
    const steps = 3;
    for (let i = 0; i < steps; i++) {
      a.x += a.vx * dt / steps; a.y += a.vy * dt / steps;
      a.left -= Math.hypot(a.vx, a.vy) * dt / steps;
      if (a.left <= 0 || World.blocksArrow(tiles, a.x, a.y)) return false;
      for (const t of targetsFor(a.owner)) {
        if (Math.hypot(t.x - a.x, t.y - a.y) <= t.radius + 3) { damage(a.owner, t, a.dmg); return false; }
      }
    }
    return true;
  });

  // White Walker AI: chase the nearest living player and strike
  for (const id in enemies) {
    const e = enemies[id], def = ENEMIES[e.type];
    let target = null, best = def.aggro;
    for (const pid in players) {
      const p = players[pid];
      const d = Math.hypot(p.x - e.x, p.y - e.y);
      if (!p.dead && d < best) { best = d; target = p; }
    }
    if (!target) continue;
    const dx = target.x - e.x, dy = target.y - e.y;
    if (best > def.range + target.radius) {
      // Walk straight when close, otherwise follow a tile path (refreshed 4x/sec)
      let goal = target;
      if (best > World.TILE * 1.5) {
        if (!e.waypoint || now >= e.repath) { e.waypoint = World.nextStep(tiles, e.x, e.y, target.x, target.y) || target; e.repath = now + 250; }
        goal = e.waypoint;
        if (Math.hypot(goal.x - e.x, goal.y - e.y) < 4) e.repath = 0;
      }
      const gx = goal.x - e.x, gy = goal.y - e.y, gd = Math.hypot(gx, gy) || 1;
      const step = Math.min(def.speed * dt, gd);
      Object.assign(e, World.moveCircle(tiles, e.x, e.y, gx / gd * step, gy / gd * step, e.radius));
    } else if (now >= e.nextAttack) {
      e.nextAttack = now + def.cooldown * 1000;
      const angle = Math.atan2(dy, dx);
      damage(e, target, def.damage);
      io.emit('fx', { type: 'frost', x: e.x, y: e.y, angle, range: def.range + 12, arc: Math.PI * 0.7 });
    }
  }

  // Red Priest fires: grant the blessing to anyone standing in them
  fires = fires.filter((f) => f.expires > now);
  for (const f of fires) for (const id in players) {
    const p = players[id];
    if (p.dead || Math.hypot(p.x - f.x, p.y - f.y) > 36 || p.buffUntil > now + BUFF_DURATION - 1000) continue;
    p.buffUntil = now + BUFF_DURATION;
    io.to(p.id).emit('blessed', { duration: BUFF_DURATION / 1000 });
  }

  const state = { players: {}, enemies: mapOf(enemies, publicEnemy) };
  for (const id in players) {
    const p = players[id];
    state.players[id] = { x: p.x, y: p.y, hp: p.hp, maxHp: p.maxHp, dead: p.dead, level: p.level, buffed: isBuffed(p) };
  }
  state.arrows = projectiles.map((a) => ({ id: a.id, x: a.x, y: a.y, vx: a.vx, vy: a.vy }));
  state.fires = fires.map(({ id, x, y }) => ({ id, x, y }));
  io.emit('state', state);
}, TICK);

server.listen(PORT, () => console.log(`Server running on port ${PORT}`));
