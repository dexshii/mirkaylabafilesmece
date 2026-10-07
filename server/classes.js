// Class definitions (shared with client via /classes.js)
// attack: type, cooldown (s), range (px), arc (rad, melee), projectile speed (px/s)
const CLASSES = {
  fighter: { name: 'Fighter', title: 'Demir Taht Şövalyesi', shape: 'square', color: '#b3202a', hp: 160, armor: 40, agility: 8, damage: 18, magic: 0, speed: 140,
    attack: { type: 'melee', cooldown: 0.6, range: 60, arc: Math.PI * 0.75 } },
  archer: { name: 'Archer', title: "Gece Nöbetçisi Okçusu", shape: 'triangle', color: '#2f8f3a', hp: 100, armor: 15, agility: 30, damage: 14, magic: 0, speed: 200,
    attack: { type: 'arrow', cooldown: 0.5, range: 900, projSpeed: 750 } },
  mystic: { name: 'Greenseer / Red Priest', title: 'Ormanın Çocukları / Işık Tanrısı Rahibi', shape: 'circle', color: '#2a5fc4', hp: 70, armor: 5, agility: 15, damage: 6, magic: 32, speed: 170,
    attack: { type: 'nova', cooldown: 3, range: 130 } }
};
const PLAYER_RADIUS = 14;
const RESPAWN_TIME = 3;
// Armor mitigates damage: 40 armor -> ~29% reduction
const mitigate = (dmg, armor) => Math.max(1, Math.round(dmg * 100 / (100 + armor)));
if (typeof module !== 'undefined') module.exports = { CLASSES, PLAYER_RADIUS, RESPAWN_TIME, mitigate };
