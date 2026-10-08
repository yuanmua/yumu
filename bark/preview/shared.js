/* 三个设计版本共用：数据、图标、像素封面生成、主题与小组件。 */

/* ---------- 数据 ---------- */
const MODS = {
  perf: ['Sodium', 'Lithium', 'FerriteCore', 'ModernFix', 'Entity Culling', 'ImmediatelyFast'],
  qol: ['Mod Menu', 'Xaero 小地图', 'Jade', 'JEI', 'AppleSkin', 'Controlling'],
  content: ['Create', 'Farmer\'s Delight', 'Supplementaries', 'Cobblemon'],
  visual: ['Iris Shaders', 'Continuity', 'LambDynamicLights', 'Falling Leaves'],
};
const DATA = {
  instances: [
    { id: 'survival', name: '生存服 2026', loader: 'Fabric', loaderVersion: '0.17.3', version: '26.3', biome: 'forest', lastPlayed: '昨天 22:14', playtime: '42 小时', hours: 42, favorite: true,
      mods: [...MODS.perf, ...MODS.qol.slice(0, 3), ...MODS.visual.slice(0, 2)], shaders: ['Complementary Reimagined'], packs: ['Faithful 32x'],
      worlds: [{ name: '主世界', size: '1.2 GB', last: '昨天', mode: '生存' }, { name: '极限模式', size: '310 MB', last: '上周', mode: '极限' }] },
    { id: 'vanilla', name: '原版 26.3', loader: null, loaderVersion: '', version: '26.3', biome: 'plains', lastPlayed: '3 天前', playtime: '6 小时', hours: 6, favorite: false,
      mods: [], shaders: [], packs: [], worlds: [{ name: '新的世界', size: '140 MB', last: '3 天前', mode: '创造' }] },
    { id: 'create', name: 'Create 工业', loader: 'NeoForge', loaderVersion: '21.1.209', version: '1.21.1', biome: 'cave', lastPlayed: '上周', playtime: '118 小时', hours: 118, favorite: true,
      mods: ['Create', 'JEI', 'Jade', 'Create: Steam \'n Rails', 'Farmer\'s Delight', 'Supplementaries', 'Xaero 小地图', 'AppleSkin', 'ModernFix', 'FerriteCore', 'Embeddium'], shaders: [], packs: [],
      worlds: [{ name: '工厂 v3', size: '2.8 GB', last: '上周', mode: '生存' }] },
    { id: 'skyblock', name: '空岛挑战', loader: 'Forge', loaderVersion: '47.3.0', version: '1.20.1', biome: 'sky', lastPlayed: '两周前', playtime: '27 小时', hours: 27, favorite: false,
      mods: ['SkyBlock Builder', 'JEI', 'Ex Nihilo', 'Applied Energistics 2', 'Mekanism'], shaders: [], packs: [],
      worlds: [{ name: '空岛 #1', size: '85 MB', last: '两周前', mode: '生存' }] },
    { id: 'nether', name: '下界探险', loader: 'Quilt', loaderVersion: '0.27.1', version: '1.21.4', biome: 'nether', lastPlayed: '从未', playtime: '0 分钟', hours: 0, favorite: false,
      mods: ['Sodium', 'Mod Menu', 'Cobblemon'], shaders: [], packs: [], worlds: [] },
  ],
  accounts: [
    { id: 'steve', name: 'Steve', kind: '微软', uuid: '069a79f4-44e9-4726-a5be-fca90e38aaf5', active: true },
    { id: 'alex', name: 'Alex', kind: '离线', uuid: '——', active: false },
  ],
  packs: [
    { name: 'Fabulously Optimized', by: 'robotkoer', dl: '2,310 万', desc: '一键优化原版性能，装上就比原版快。', biome: 'plains', loader: 'Fabric', version: '26.3', tags: ['优化', '原版+'] },
    { name: 'Cobblemon', by: 'Cobblemon Team', dl: '620 万', desc: '在 Minecraft 里收集与对战宝可梦。', biome: 'forest', loader: 'Fabric', version: '1.21.1', tags: ['冒险', '生物'] },
    { name: 'Prominence II', by: 'ProminenceTeam', dl: '410 万', desc: 'RPG 向整合，任务、地牢与新维度。', biome: 'nether', loader: 'Fabric', version: '1.20.1', tags: ['RPG', '任务'] },
    { name: 'Better MC', by: 'LunaPixelStudios', dl: '380 万', desc: '更丰富的原版体验，不改变核心玩法。', biome: 'snow', loader: 'Forge', version: '1.20.1', tags: ['原版+', '探索'] },
    { name: 'All the Mods 10', by: 'ATMTeam', dl: '290 万', desc: '什么都有的厨房水槽整合。', biome: 'cave', loader: 'NeoForge', version: '1.21.1', tags: ['科技', '魔法'] },
    { name: 'SkyFactory 5', by: 'Darkosto', dl: '150 万', desc: '从一棵树开始的空岛工业。', biome: 'sky', loader: 'NeoForge', version: '1.21.1', tags: ['空岛', '科技'] },
  ],
  versions: ['26.3', '26.2', '26.1', '1.21.4', '1.21.1', '1.20.1'],
  javas: [{ name: 'Mojang 运行时 21', path: '自动管理', ver: '21.0.6', auto: true }, { name: 'Temurin 17', path: '/Library/Java/JavaVirtualMachines/temurin-17.jdk', ver: '17.0.14' }, { name: '系统 Java 8', path: '/usr/bin/java', ver: '1.8.0_432' }],
};
const ACCENTS = [
  { id: 'system', name: '跟随系统', color: null },
  { id: 'moss', name: '苔绿', color: '#2F8A5A' },
  { id: 'amber', name: '琥珀', color: '#C47A2C' },
  { id: 'indigo', name: '靛青', color: '#3B6FD4' },
  { id: 'rose', name: '玫瑰', color: '#C94A6B' },
  { id: 'graphite', name: '石墨', color: '#5B6068' },
];
const BIOMES = {
  forest: { sky: ['#9fd3ff', '#dff2ff'], top: '#5fae4a', dirt: '#8a5a37', stone: '#8c8c8c', tree: true, water: null },
  plains: { sky: ['#8ec9ff', '#e6f4ff'], top: '#7ac54f', dirt: '#946140', stone: '#8f8f8f', tree: false, water: '#3f76e4' },
  cave: { sky: ['#2b2f36', '#3b414b'], top: '#6d6d6d', dirt: '#5a5a5a', stone: '#4b4b4b', tree: false, water: '#d96b1a', dark: true },
  sky: { sky: ['#6fb5ff', '#f5fbff'], top: '#75c951', dirt: '#8a5a37', stone: '#8c8c8c', tree: true, island: true },
  nether: { sky: ['#3a0d0d', '#6b1b1b'], top: '#b03a2e', dirt: '#5e1f1a', stone: '#4a1612', tree: false, water: '#ff8c1a', dark: true },
  snow: { sky: ['#bcd6f0', '#eef5fb'], top: '#f2f6f8', dirt: '#8a6a4a', stone: '#8c8c8c', tree: true },
};

/* ---------- 像素封面 ---------- */
function rng(seed) { let s = 0; for (const c of seed) s = (s * 31 + c.charCodeAt(0)) >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }
function cover(seed, biome = 'forest', w = 32, h = 18) {
  const b = BIOMES[biome] || BIOMES.forest, r = rng(seed + biome), cells = [];
  const heights = []; let hh = 8 + Math.floor(r() * 3);
  for (let x = 0; x < w; x++) { hh += Math.round((r() - 0.5) * 2); hh = Math.max(5, Math.min(h - 4, hh)); heights.push(hh); }
  const shade = (hex, d) => { const n = parseInt(hex.slice(1), 16); const f = c => Math.max(0, Math.min(255, Math.round(c * d))); return `rgb(${f(n >> 16)},${f((n >> 8) & 255)},${f(n & 255)})`; };
  for (let x = 0; x < w; x++) {
    const ground = h - heights[x];
    for (let y = ground; y < h; y++) {
      let c = y === ground ? b.top : y < ground + 3 ? b.dirt : b.stone;
      if (b.island && y > ground + 4 + Math.floor(r() * 3)) continue;
      if (b.water && y >= h - 2 && heights[x] < 7) c = b.water;
      cells.push(`<rect x="${x}" y="${y}" width="1" height="1" fill="${shade(c, 0.92 + r() * 0.16)}"/>`);
    }
    if (b.tree && r() < 0.14 && x > 1 && x < w - 2) {
      const ty = ground - 1;
      for (let i = 0; i < 3; i++) cells.push(`<rect x="${x}" y="${ty - i}" width="1" height="1" fill="#5a3a21"/>`);
      for (let dx = -1; dx <= 1; dx++) for (let dy = -5; dy <= -3; dy++) cells.push(`<rect x="${x + dx}" y="${ty + dy + 1}" width="1" height="1" fill="${shade('#3f8f3a', 0.85 + r() * 0.3)}"/>`);
    }
    if (b.dark && r() < 0.08) cells.push(`<rect x="${x}" y="${Math.floor(r() * 4)}" width="1" height="1" fill="rgba(255,255,255,0.35)"/>`);
  }
  const sun = b.dark ? '' : `<rect x="${w - 6}" y="2" width="2" height="2" fill="#fff3b0"/>`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges"><defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${b.sky[0]}"/><stop offset="1" stop-color="${b.sky[1]}"/></linearGradient></defs><rect width="${w}" height="${h}" fill="url(#s)"/>${sun}${cells.join('')}</svg>`;
  return `url('data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg).replace(/'/g, '%27')}')`;
}

/* ---------- 图标 ---------- */
const ICONS = {
  cube: '<path d="M12 3 4 7v10l8 4 8-4V7l-8-4z"/><path d="M4 7l8 4 8-4M12 11v10"/>',
  puzzle: '<path d="M10 4a2 2 0 1 1 4 0v1h3a1 1 0 0 1 1 1v3h-1a2 2 0 1 0 0 4h1v3a1 1 0 0 1-1 1h-3v-1a2 2 0 1 0-4 0v1H7a1 1 0 0 1-1-1v-3h1a2 2 0 1 0 0-4H6V6a1 1 0 0 1 1-1h3V4z"/>',
  play: '<path d="M7 5v14l11-7z" fill="currentColor" stroke="none"/>',
  stop: '<rect x="6" y="6" width="12" height="12" rx="2" fill="currentColor" stroke="none"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  import: '<path d="M12 3v11M8 10l4 4 4-4"/><path d="M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>',
  package: '<path d="M3 8l9-4 9 4v9l-9 4-9-4V8z"/><path d="M3 8l9 4 9-4M12 12v9M7.5 6l9 4"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/>',
  search: '<circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5"/>',
  more: '<circle cx="6" cy="12" r="1.2" fill="currentColor"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><circle cx="18" cy="12" r="1.2" fill="currentColor"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3"/>',
  check: '<path d="M5 12l5 5L20 7"/>',
  chevron: '<path d="M9 6l6 6-6 6"/>',
  chevronDown: '<path d="M6 9l6 6 6-6"/>',
  back: '<path d="M15 6l-6 6 6 6"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>',
  warning: '<path d="M12 4 2.5 20h19L12 4z"/><path d="M12 10v4M12 17v.5"/>',
  moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  motion: '<path d="M4 12h6M4 7h10M4 17h8"/><circle cx="17" cy="12" r="3"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2 20a7 7 0 0 1 14 0M16 4a3.5 3.5 0 0 1 0 7M22 20a7 7 0 0 0-5-6.7"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a1 1 0 0 1 1-1h9"/>',
  pen: '<path d="M4 20h4l10-10-4-4L4 16v4z"/>',
  log: '<path d="M6 4h9l4 4v12a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z"/><path d="M9 13h6M9 17h6"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  home: '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1v-9z"/>',
  grid: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
  globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  palette: '<path d="M12 3a9 9 0 0 0 0 18c1.5 0 2-1 2-2s-.5-2 1-2h2a4 4 0 0 0 4-4 10 10 0 0 0-9-10z"/><circle cx="7.5" cy="11" r="1" fill="currentColor"/><circle cx="10.5" cy="7" r="1" fill="currentColor"/><circle cx="15" cy="7.5" r="1" fill="currentColor"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8v.5"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  cpu: '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="10" y="10" width="4" height="4"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
  download: '<path d="M12 4v12M7 11l5 5 5-5M5 20h14"/>',
  sliders: '<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>',
  refresh: '<path d="M20 12a8 8 0 1 1-2.3-5.7M20 4v5h-5"/>',
  external: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
  star: '<path d="M12 3l2.8 5.9 6.4.8-4.7 4.4 1.2 6.3L12 17.3l-5.7 3.1 1.2-6.3L2.8 9.7l6.4-.8z"/>',
  starFill: '<path d="M12 3l2.8 5.9 6.4.8-4.7 4.4 1.2 6.3L12 17.3l-5.7 3.1 1.2-6.3L2.8 9.7l6.4-.8z" fill="currentColor"/>',
  layers: '<path d="M12 3l9 5-9 5-9-5 9-5z"/><path d="M3 13l9 5 9-5M3 17l9 5 9-5"/>',
  terminal: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9l3 3-3 3M12 15h5"/>',
  image: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="M21 16l-5-5-8 8"/>',
  world: '<circle cx="12" cy="12" r="9"/><path d="M8 5c2 3 2 11 0 14M16 5c-2 3-2 11 0 14M3 12h18"/>',
  shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3z"/>',
  bell: '<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4l2-2z"/><path d="M10 20a2 2 0 0 0 4 0"/>',
  heart: '<path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z"/>',
  sparkle: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>',
  key: '<circle cx="8" cy="14" r="4"/><path d="M11 11l9-9M17 5l2 2M14 8l2 2"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  laptop: '<rect x="4" y="5" width="16" height="11" rx="2"/><path d="M2 19h20"/>',
  zap: '<path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z"/>',
  file: '<path d="M6 3h8l5 5v12a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/><path d="M14 3v5h5"/>',
  book: '<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2V5z"/><path d="M4 19a2 2 0 0 1 2-2h13"/>',
  github: '<path d="M12 2a10 10 0 0 0-3.2 19.5c.5.1.7-.2.7-.5v-1.8c-2.8.6-3.4-1.2-3.4-1.2-.4-1.1-1.1-1.4-1.1-1.4-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.5 2.3 1.1 2.9.8.1-.6.3-1.1.6-1.3-2.2-.3-4.6-1.1-4.6-5 0-1.1.4-2 1-2.7-.1-.3-.4-1.3.1-2.7 0 0 .8-.3 2.7 1a9.4 9.4 0 0 1 5 0c1.9-1.3 2.7-1 2.7-1 .5 1.4.2 2.4.1 2.7.6.7 1 1.6 1 2.7 0 3.9-2.4 4.7-4.6 5 .4.3.7.9.7 1.9v2.8c0 .3.2.6.7.5A10 10 0 0 0 12 2z"/>',
  memory: '<rect x="3" y="7" width="18" height="10" rx="2"/><path d="M7 7v10M11 7v10M15 7v10M19 7v10M3 12h18"/>',
  monitor: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
  volume: '<path d="M4 10v4h3l5 4V6L7 10H4z"/><path d="M16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  tag: '<path d="M3 12V4h8l9 9-8 8-9-9z"/><circle cx="7.5" cy="8.5" r="1.2" fill="currentColor"/>',
  disc: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2.5"/>',
  arrowRight: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  skin: '<rect x="8" y="3" width="8" height="8" rx="1"/><path d="M5 21v-6a3 3 0 0 1 3-3h8a3 3 0 0 1 3 3v6"/>',
};
const icon = (n, s = 16) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[n] || ''}</svg>`;
function hydrateIcons(root = document) { root.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon, el.dataset.size || 16); el.style.display = 'inline-flex'; }); }

/* ---------- 玩家头像（像素） ---------- */
function face(seed = 'steve', size = 32) {
  const r = rng(seed); const skin = seed === 'alex' ? '#f0c9a0' : '#e8b690'; const hair = seed === 'alex' ? '#c8742c' : '#4a2e1a'; const eye = seed === 'alex' ? '#3a7a3a' : '#3c4fb0';
  const px = [];
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
    let c = skin;
    if (y < 2 || (y === 2 && (x < 1 || x > 6)) || (y === 3 && r() < 0.15)) c = hair;
    if (y === 4 && (x === 1 || x === 6)) c = '#fff';
    if (y === 4 && (x === 2 || x === 5)) c = eye;
    if (y === 6 && x > 2 && x < 5) c = '#b06a4a';
    px.push(`<rect x="${x}" y="${y}" width="1" height="1" fill="${c}"/>`);
  }
  return `<svg width="${size}" height="${size}" viewBox="0 0 8 8" shape-rendering="crispEdges" style="border-radius:inherit">${px.join('')}</svg>`;
}

/* ---------- 设置状态 ---------- */
const SETTINGS = Object.assign({
  theme: 'system', accent: 'system', language: 'system', density: 'comfortable', motion: 'system', sidebarCovers: true,
  source: 'auto', concurrency: 8, proxy: '', afterLaunch: 'keep', closeToTray: false, notify: true, discover: true,
}, (() => { try { return JSON.parse(localStorage.getItem('yumu-settings') || '{}'); } catch { return {}; } })());
function saveSettings() { try { localStorage.setItem('yumu-settings', JSON.stringify(SETTINGS)); } catch {} }

/* ---------- 主题与动效 ---------- */
function applyTheme(defaultAccent) {
  const root = document.documentElement;
  const dark = SETTINGS.theme === 'dark' || (SETTINGS.theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  root.dataset.theme = dark ? 'dark' : 'light';
  const acc = ACCENTS.find(a => a.id === SETTINGS.accent);
  root.style.setProperty('--accent', acc && acc.color ? acc.color : defaultAccent);
  const reduced = SETTINGS.motion === 'reduced' || (SETTINGS.motion === 'system' && matchMedia('(prefers-reduced-motion: reduce)').matches);
  root.dataset.motion = reduced ? 'reduced' : 'full';
  root.dataset.density = SETTINGS.density;
}

/* ---------- 小组件 ---------- */
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
function el(html) { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; }

function segmented(root, onChange) {
  const thumb = root.querySelector('.thumb'); const buttons = $$('button', root);
  const place = b => { if (!thumb || !b) return; thumb.style.width = b.offsetWidth + 'px'; thumb.style.transform = `translateX(${b.offsetLeft - (thumb.offsetParent === root ? 2 : 0)}px)`; };
  buttons.forEach(b => b.addEventListener('click', () => { if (b.disabled) return; buttons.forEach(x => x.setAttribute('aria-selected', x === b)); place(b); onChange && onChange(b); }));
  const cur = () => buttons.find(b => b.getAttribute('aria-selected') === 'true') || buttons[0];
  requestAnimationFrame(() => place(cur()));
  return { place: () => place(cur()), select: i => buttons[i] && buttons[i].click() };
}
function bindSwitches(root) { $$('.switch', root).forEach(b => b.onclick = () => b.setAttribute('aria-checked', b.getAttribute('aria-checked') !== 'true')); }

function openSheet(container, html, cls = '') {
  const scrim = el(`<div class="scrim"><div class="sheet ${cls}" role="dialog">${html}</div></div>`);
  container.appendChild(scrim);
  const close = () => { scrim.classList.add('out'); setTimeout(() => scrim.remove(), 320); document.removeEventListener('keydown', onKey); };
  const onKey = e => { if (e.key === 'Escape') close(); if (e.key === 'Enter' && !e.target.matches('select, textarea')) { const p = scrim.querySelector('.btn.primary:not(:disabled)'); p && p.click(); } };
  document.addEventListener('keydown', onKey);
  scrim.addEventListener('pointerdown', e => { if (e.target === scrim) close(); });
  $$('[data-close]', scrim).forEach(b => b.onclick = close);
  hydrateIcons(scrim); bindSwitches(scrim); $$('.segmented', scrim).forEach(s => segmented(s));
  return { sheet: scrim.firstElementChild, close };
}
function toast(container, text, action) {
  $$('.toast', container).forEach(t => t.remove());
  const t = el(`<div class="toast">${icon('check')}<span>${text}</span>${action ? `<button class="btn text">${action}</button>` : ''}</div>`);
  container.appendChild(t);
  setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 200); }, 3200);
}
function menu(container, x, y, items) {
  $$('.menu', container).forEach(m => m.remove());
  const m = el('<div class="menu"></div>');
  const r = container.getBoundingClientRect();
  m.style.left = Math.min(x - r.left, r.width - 200) + 'px'; m.style.top = Math.min(y - r.top, r.height - items.length * 28 - 16) + 'px';
  items.forEach(it => {
    if (it === '-') { m.appendChild(el('<hr>')); return; }
    const b = el(`<button class="${it.danger ? 'danger' : ''}">${icon(it.icon)}<span>${it.label}</span></button>`);
    b.onclick = () => { m.remove(); it.run && it.run(); }; m.appendChild(b);
  });
  container.appendChild(m);
  setTimeout(() => document.addEventListener('pointerdown', function h(e) { if (!m.contains(e.target)) { m.remove(); document.removeEventListener('pointerdown', h); } }), 0);
}

/* ---------- 路由 ---------- */
function router(handler) {
  const run = () => handler((location.hash || '#/').slice(1).split('/').filter(Boolean));
  addEventListener('hashchange', run); run();
}
const go = path => { location.hash = '#' + path; };

/* ---------- 新建实例表单（三版共用的内容，样式各自定义） ---------- */
function newInstanceForm() {
  return `
    <div class="form">
      <label>名称</label><div class="field"><input id="nName" placeholder="26.3"></div>
      <label>版本</label><div class="field select"><select id="nVer">${DATA.versions.map((v, i) => `<option>${v}${i === 0 ? '（最新）' : ''}</option>`).join('')}<option>显示全部版本…</option></select></div>
      <label>模组加载器</label><div class="segmented" id="nLoader"><div class="thumb"></div><button aria-selected="true">原版</button><button>Fabric</button><button>Quilt</button><button>Forge</button><button>NeoForge</button></div>
      <label>图标</label><div class="iconpick">${['forest', 'plains', 'cave', 'sky', 'nether', 'snow'].map((b, i) => `<button class="${i === 0 ? 'on' : ''}" style="background-image:${cover('new' + i, b, 8, 8)}" title="${b}"></button>`).join('')}<button class="custom" title="自定义图片…">${icon('image')}</button></div>
    </div>
    <div class="disclosure" data-open="false"><button type="button">${icon('chevron')}高级选项</button><div class="body-wrap"><div><div class="inner">
      <label>加载器版本</label><div class="field select"><select><option>推荐</option><option>最新</option><option>指定…</option></select></div>
      <label>Java</label><div class="field select"><select>${DATA.javas.map(j => `<option>${j.name}</option>`).join('')}</select></div>
      <label>内存</label><div class="field"><input value="4 GB"></div><small>内存越大加载越快，但不要超过物理内存的一半。</small>
      <label>JVM 参数</label><div class="field"><input placeholder="留空用默认值"></div>
    </div></div></div></div>`;
}
function bindDisclosures(root) { $$('.disclosure', root).forEach(d => d.querySelector(':scope > button').onclick = () => d.dataset.open = d.dataset.open !== 'true'); }
function bindIconPick(root) { $$('.iconpick', root).forEach(p => $$('button', p).forEach(b => b.onclick = () => { $$('button', p).forEach(x => x.classList.remove('on')); b.classList.add('on'); })); }

/* ---------- 设置页内容（三版共用的字段，样式各自定义） ---------- */
const SETTINGS_SECTIONS = [
  { id: 'general', name: '通用', icon: 'sliders' },
  { id: 'appearance', name: '外观', icon: 'palette' },
  { id: 'download', name: '下载', icon: 'download' },
  { id: 'java', name: 'Java', icon: 'cpu' },
  { id: 'accounts', name: '账号', icon: 'users' },
  { id: 'about', name: '关于', icon: 'info' },
];
function settingsSection(id) {
  const sw = (k) => `<button class="switch" aria-checked="${SETTINGS[k]}" data-setting="${k}"></button>`;
  const sel = (k, opts) => `<div class="field select"><select data-setting="${k}">${opts.map(([v, l]) => `<option value="${v}" ${SETTINGS[k] === v ? 'selected' : ''}>${l}</option>`).join('')}</select></div>`;
  const row = (title, desc, control) => `<div class="srow"><div class="stexts"><b>${title}</b>${desc ? `<small>${desc}</small>` : ''}</div><div class="scontrol">${control}</div></div>`;
  switch (id) {
    case 'general': return `
      <div class="sgroup"><h5>启动</h5>
        ${row('开始游戏后', '', sel('afterLaunch', [['keep', '保持 Yumu 打开'], ['hide', '隐藏 Yumu'], ['quit', '退出 Yumu']]))}
        ${row('关闭窗口时留在菜单栏', '游戏运行时仍能看到状态。', sw('closeToTray'))}
        ${row('游戏退出后通知我', '', sw('notify'))}
      </div>
      <div class="sgroup"><h5>本机</h5>
        ${row('发现本机已有的存档和版本', '扫描官方启动器与其他启动器的目录，一键导入。', sw('discover'))}
        ${row('数据目录', '~/Library/Application Support/Yumu', `<button class="btn">打开</button><button class="btn">迁移…</button>`)}
      </div>`;
    case 'appearance': return `
      <div class="sgroup"><h5>主题</h5>
        <div class="themepick">${[['system', '跟随系统'], ['light', '浅色'], ['dark', '深色']].map(([v, l]) => `<button class="${SETTINGS.theme === v ? 'on' : ''}" data-theme-pick="${v}"><span class="thumb-${v}"></span>${l}</button>`).join('')}</div>
      </div>
      <div class="sgroup"><h5>强调色</h5>
        <div class="accentpick">${ACCENTS.map(a => `<button class="${SETTINGS.accent === a.id ? 'on' : ''}" data-accent="${a.id}" title="${a.name}" style="${a.color ? '--c:' + a.color : '--c: conic-gradient(#2F8A5A,#C47A2C,#3B6FD4,#C94A6B,#2F8A5A)'}"><i></i><span>${a.name}</span></button>`).join('')}</div>
      </div>
      <div class="sgroup"><h5>界面</h5>
        ${row('密度', '', sel('density', [['comfortable', '舒适'], ['compact', '紧凑']]))}
        ${row('侧栏显示封面', '', sw('sidebarCovers'))}
        ${row('动效', '跟随系统的「减弱动态效果」。', sel('motion', [['system', '跟随系统'], ['full', '完整'], ['reduced', '减弱']]))}
        ${row('语言', '', sel('language', [['system', '跟随系统'], ['zh-Hans', '简体中文'], ['en', 'English'], ['ja', '日本語']]))}
      </div>`;
    case 'download': return `
      <div class="sgroup"><h5>下载源</h5>
        ${row('来源', '自动会测速后选最快的。', sel('source', [['auto', '自动'], ['official', '官方'], ['bmclapi', 'BMCLAPI 镜像']]))}
        ${row('并发数', '', `<div class="field" style="width:80px"><input value="${SETTINGS.concurrency}"></div>`)}
        ${row('代理', '留空不用代理。', `<div class="field" style="width:220px"><input placeholder="http://127.0.0.1:7890"></div>`)}
      </div>
      <div class="sgroup"><h5>缓存</h5>
        ${row('共享缓存', '资源、库文件与 Java 运行时在实例间共享，占用 3.4 GB。', `<button class="btn">校验</button><button class="btn danger">清空</button>`)}
      </div>`;
    case 'java': return `
      <div class="sgroup"><h5>Java 运行时</h5>
        <div class="jlist">${DATA.javas.map(j => `<div class="jrow">${icon('cpu')}<div class="stexts"><b>${j.name}${j.auto ? ' <span class="tag accent">自动</span>' : ''}</b><small>${j.ver} · ${j.path}</small></div>${j.auto ? '' : `<button class="btn icon">${icon('trash')}</button>`}</div>`).join('')}</div>
        <div class="srow"><div class="stexts"><small>Mojang 运行时按游戏版本自动下载，用不着手动管。只有要用自己的 Java 时才加。</small></div><div class="scontrol"><button class="btn">添加…</button><button class="btn">重新扫描</button></div></div>
      </div>
      <div class="sgroup"><h5>默认值</h5>
        ${row('内存', '新实例的默认内存，可按实例覆盖。', `<div class="field" style="width:100px"><input value="4 GB"></div>`)}
        ${row('JVM 参数', '', `<div class="field" style="width:260px"><input placeholder="留空用默认值"></div>`)}
      </div>`;
    case 'accounts': return `
      <div class="sgroup"><h5>账号</h5>
        <div class="alist">${DATA.accounts.map(a => `<div class="arow ${a.active ? 'active' : ''}"><div class="avatar">${face(a.id, 36)}</div><div class="stexts"><b>${a.name}${a.active ? ' <span class="tag accent">当前</span>' : ''}</b><small>${a.kind} · ${a.uuid}</small></div><button class="btn">${a.active ? '皮肤…' : '切换'}</button><button class="btn icon">${icon('more')}</button></div>`).join('')}</div>
        <div class="srow"><div class="stexts"><small>皮肤与披风预览即将推出。</small></div><div class="scontrol"><button class="btn primary">${icon('plus')}用微软账号登录</button><button class="btn">添加离线账号</button></div></div>
      </div>`;
    case 'about': return `
      <div class="about">
        <div class="about-head"><div class="about-logo">${icon('cube', 40)}</div><div><div class="about-name">Yumu</div><div class="about-ver">版本 0.4.0 (128) · Heartwood 0.4.0 · macOS arm64</div></div><button class="btn">检查更新</button></div>
        <div class="sgroup">
          ${row('自动更新', '后台下载，下次启动时安装。', sw('notify'))}
          ${row('更新通道', '', sel('source', [['auto', '稳定版'], ['beta', '测试版']]))}
        </div>
        <div class="sgroup"><h5>链接</h5>
          <div class="linkrow"><a>${icon('github')}源代码</a><a>${icon('book')}使用指南</a><a>${icon('warning')}报告问题</a><a>${icon('heart')}支持开发</a></div>
        </div>
        <div class="sgroup"><h5>致谢</h5><p class="small">Yumu 使用了 Mojang、Modrinth、Fabric、Quilt、Forge、NeoForge 的公开服务。Minecraft 是 Mojang Studios 的商标，Yumu 与 Mojang 无关。开源许可：MIT。</p>
        <div class="linkrow"><a>第三方许可</a><a>隐私说明</a><a>日志目录</a></div></div>
      </div>`;
  }
}
function bindSettings(root, rerender) {
  $$('[data-setting]', root).forEach(c => {
    if (c.classList.contains('switch')) c.onclick = () => { const v = c.getAttribute('aria-checked') !== 'true'; c.setAttribute('aria-checked', v); SETTINGS[c.dataset.setting] = v; saveSettings(); rerender(); };
    else c.onchange = () => { SETTINGS[c.dataset.setting] = c.value; saveSettings(); rerender(); };
  });
  $$('[data-theme-pick]', root).forEach(b => b.onclick = () => { SETTINGS.theme = b.dataset.themePick; saveSettings(); rerender(true); });
  $$('[data-accent]', root).forEach(b => b.onclick = () => { SETTINGS.accent = b.dataset.accent; saveSettings(); rerender(true); });
}

/* ---------- 设计控制台（页面底部的浮条，不属于产品） ---------- */
function designBar(opts) {
  if (window.top !== window) return;
  const bar = el(`<div class="designbar">
    <span class="db-name">${opts.name}</span>
    <span class="db-sep"></span>
    <button data-db="theme" title="切换深浅色">${icon('moon')}</button>
    <button data-db="motion" title="模拟减弱动态效果">${icon('motion')}</button>
    <span class="db-sep"></span>
    <button data-db="frame" title="切换窗口边框">边框：macOS</button>
    <span class="db-sep"></span>
    ${opts.scenes.map(s => `<button data-scene="${s.id}">${s.label}</button>`).join('')}
    <span class="db-sep"></span>
    <a href="index.html">← 选版本</a>
  </div>`);
  document.body.appendChild(bar);
  const frames = ['mac', 'win', 'linux'], names = { mac: 'macOS', win: 'Windows', linux: 'Linux' };
  bar.querySelector('[data-db=theme]').onclick = () => { SETTINGS.theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'; saveSettings(); opts.rerender(true); };
  bar.querySelector('[data-db=motion]').onclick = () => { SETTINGS.motion = document.documentElement.dataset.motion === 'reduced' ? 'full' : 'reduced'; saveSettings(); opts.rerender(true); };
  bar.querySelector('[data-db=frame]').onclick = e => { const app = $('.app'); const i = (frames.indexOf(app.dataset.frame) + 1) % 3; app.dataset.frame = frames[i]; e.currentTarget.textContent = '边框：' + names[frames[i]]; };
  $$('[data-scene]', bar).forEach(b => b.onclick = () => opts.scene(b.dataset.scene));
}
