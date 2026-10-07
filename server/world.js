// Shared tilemap: generation (server) and collision (server + client prediction)
(function (root) {
  const TILE = 48, W = 80, H = 80;
  const T = { GRASS: 0, DIRT: 1, WALL: 2, TREE: 3, WATER: 4 };
  const SOLID = [false, false, true, true, true];
  const BLOCKS_ARROW = [false, false, true, true, false];

  function rng(seed) { let s = seed % 2147483647; return () => (s = (s * 16807) % 2147483647) / 2147483647; }

  // Smoothed value noise in [0,1]
  function noise(r, scale) {
    const gw = Math.ceil(W / scale) + 2;
    const g = Array.from({ length: gw * (Math.ceil(H / scale) + 2) }, r);
    const sm = (t) => t * t * (3 - 2 * t);
    return (x, y) => {
      const fx = x / scale, fy = y / scale, ix = Math.floor(fx), iy = Math.floor(fy);
      const tx = sm(fx - ix), ty = sm(fy - iy), v = (a, b) => g[b * gw + a];
      const top = v(ix, iy) * (1 - tx) + v(ix + 1, iy) * tx;
      const bot = v(ix, iy + 1) * (1 - tx) + v(ix + 1, iy + 1) * tx;
      return top * (1 - ty) + bot * ty;
    };
  }

  function generate(seed) {
    const r = rng(seed || 1337);
    const t = new Array(W * H).fill(T.GRASS);
    const set = (x, y, v) => { if (x >= 0 && y >= 0 && x < W && y < H) t[y * W + x] = v; };
    const lake = noise(r, 9), forest = noise(r, 6), soil = noise(r, 5);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      if (lake(x, y) > 0.74) set(x, y, T.WATER);
      else if (forest(x, y) > 0.66 ? r() < 0.75 : r() < 0.025) set(x, y, T.TREE);
      else if (soil(x, y) > 0.7) set(x, y, T.DIRT);
    }
    // Ruined keeps: wall outlines with dirt floors and two breaches
    for (let i = 0; i < 10; i++) {
      const w = 6 + Math.floor(r() * 6), h = 6 + Math.floor(r() * 6);
      const x0 = 2 + Math.floor(r() * (W - w - 4)), y0 = 2 + Math.floor(r() * (H - h - 4));
      for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) {
        const edge = x === x0 || y === y0 || x === x0 + w - 1 || y === y0 + h - 1;
        set(x, y, edge ? T.WALL : T.DIRT);
      }
      set(x0 + (w >> 1), y0 + h - 1, T.DIRT);
      set(x0 + (w >> 1) + 1, y0 + h - 1, T.DIRT);
      const side = Math.floor(r() * 3), k = 1 + Math.floor(r() * (h - 2));
      if (side === 0) set(x0, y0 + k, T.DIRT); else if (side === 1) set(x0 + w - 1, y0 + k, T.DIRT); else set(x0 + 1 + Math.floor(r() * (w - 2)), y0, T.DIRT);
    }
    // Kingsroad: two dirt roads crossing at the center (bridges over water)
    for (let i = 0; i < W; i++) for (const d of [-1, 0]) { set(i, H / 2 + d, T.DIRT); set(W / 2 + d, i, T.DIRT); }
    // Central camp clearing
    for (let dy = -7; dy <= 7; dy++) for (let dx = -7; dx <= 7; dx++) {
      const d2 = dx * dx + dy * dy;
      if (d2 <= 49) set(W / 2 + dx, H / 2 + dy, d2 <= 12 ? T.DIRT : T.GRASS);
    }
    for (let i = 0; i < W; i++) { set(i, 0, T.WALL); set(i, H - 1, T.WALL); set(0, i, T.WALL); set(W - 1, i, T.WALL); }
    return t;
  }

  function tileAt(t, px, py) {
    const tx = Math.floor(px / TILE), ty = Math.floor(py / TILE);
    if (tx < 0 || ty < 0 || tx >= W || ty >= H) return T.WALL;
    return t[ty * W + tx];
  }

  function collides(t, x, y, r) {
    for (let ty = Math.floor((y - r) / TILE); ty <= Math.floor((y + r) / TILE); ty++)
      for (let tx = Math.floor((x - r) / TILE); tx <= Math.floor((x + r) / TILE); tx++) {
        if (tx < 0 || ty < 0 || tx >= W || ty >= H || SOLID[t[ty * W + tx]]) return true;
      }
    return false;
  }

  // Axis-separated movement so entities slide along walls
  function moveCircle(t, x, y, dx, dy, r) {
    if (!collides(t, x + dx, y, r)) x += dx;
    if (!collides(t, x, y + dy, r)) y += dy;
    return { x, y };
  }

  const blocksArrow = (t, x, y) => BLOCKS_ARROW[tileAt(t, x, y)];

  // 4-way BFS over tiles; returns the center of the first tile to step into, or null
  function nextStep(t, sx, sy, gx, gy, maxNodes) {
    const s = Math.floor(sy / TILE) * W + Math.floor(sx / TILE);
    const g = Math.floor(gy / TILE) * W + Math.floor(gx / TILE);
    if (s === g) return null;
    const prev = new Int32Array(W * H).fill(-1);
    const queue = [s];
    prev[s] = s;
    for (let qi = 0; qi < queue.length && qi < (maxNodes || W * H); qi++) {
      const c = queue[qi];
      if (c === g) {
        let n = c;
        while (prev[n] !== s) n = prev[n];
        return { x: (n % W + 0.5) * TILE, y: (Math.floor(n / W) + 0.5) * TILE };
      }
      const cx = c % W;
      for (const n of [c - W, c + W, cx > 0 ? c - 1 : -1, cx < W - 1 ? c + 1 : -1]) {
        if (n < 0 || n >= W * H || prev[n] !== -1 || SOLID[t[n]]) continue;
        prev[n] = c;
        queue.push(n);
      }
    }
    return null;
  }

  const api = { TILE, W, H, T, SOLID, generate, tileAt, collides, moveCircle, blocksArrow, nextStep };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.World = api;
})(typeof window !== 'undefined' ? window : globalThis);
