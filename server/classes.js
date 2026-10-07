// Class definitions (shared with client via /classes.js)
const CLASSES = {
  fighter: { name: 'Fighter', title: 'Demir Taht Şövalyesi', shape: 'square', color: '#b3202a', hp: 160, armor: 40, agility: 8, damage: 18, magic: 0, speed: 140 },
  archer: { name: 'Archer', title: "Gece Nöbetçisi Okçusu", shape: 'triangle', color: '#2f8f3a', hp: 100, armor: 15, agility: 30, damage: 14, magic: 0, speed: 200 },
  mystic: { name: 'Greenseer / Red Priest', title: 'Ormanın Çocukları / Işık Tanrısı Rahibi', shape: 'circle', color: '#2a5fc4', hp: 70, armor: 5, agility: 15, damage: 6, magic: 32, speed: 170 }
};
if (typeof module !== 'undefined') module.exports = { CLASSES };
