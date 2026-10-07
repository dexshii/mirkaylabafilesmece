const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');
const { CLASSES } = require('./server/classes');

const PORT = process.env.PORT || 3000;
const MAP = { w: 2000, h: 2000 };

const app = express();
app.use(express.static(path.join(__dirname, 'public')));
app.get('/classes.js', (req, res) => res.sendFile(path.join(__dirname, 'server', 'classes.js')));

const server = http.createServer(app);
const io = new Server(server);
const players = {};

io.on('connection', (socket) => {
  socket.on('join', ({ cls, name }) => {
    if (!CLASSES[cls] || players[socket.id]) return;
    players[socket.id] = {
      id: socket.id,
      cls,
      name: String(name || 'Yabancı').slice(0, 16),
      x: MAP.w / 2 + (Math.random() - 0.5) * 300,
      y: MAP.h / 2 + (Math.random() - 0.5) * 300,
      hp: CLASSES[cls].hp
    };
    socket.emit('init', { id: socket.id, players, map: MAP });
    socket.broadcast.emit('playerJoined', players[socket.id]);
    console.log(`+ ${players[socket.id].name} (${cls})`);
  });

  socket.on('move', ({ x, y }) => {
    const p = players[socket.id];
    if (!p || !Number.isFinite(x) || !Number.isFinite(y)) return;
    p.x = Math.max(0, Math.min(MAP.w, x));
    p.y = Math.max(0, Math.min(MAP.h, y));
  });

  socket.on('disconnect', () => {
    if (!players[socket.id]) return;
    console.log(`- ${players[socket.id].name}`);
    delete players[socket.id];
    io.emit('playerLeft', socket.id);
  });
});

// Broadcast positions 20x/sec
setInterval(() => {
  const state = {};
  for (const id in players) state[id] = { x: players[id].x, y: players[id].y };
  io.emit('state', state);
}, 50);

server.listen(PORT, () => console.log(`Server running on http://localhost:${PORT}`));
