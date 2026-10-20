'use strict';

// =========================================================================
// OFICINA DE LOS AGENTES ESTRELLA v2.1
// agy (gemini-3.8-flash-high)
// =========================================================================

const $ = id => document.getElementById(id);
const ids = ['claude', 'codex', 'agy'];
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const number = (v, d = 0) => v == null ? '—' : Number(v).toLocaleString('es-CO', { maximumFractionDigits: d });
const hour = v => v ? new Date(v).toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit', hour12: false }) : '—';
const leaf = p => String(p || '').split(/[\\/]/).pop();
const norm = s => String(s || '').toLowerCase().replace(/_nodo|_code/, '');
const asArray = v => Array.isArray(v) ? v : (v != null ? [v] : []);
const reduced = matchMedia('(prefers-reduced-motion: reduce)');

// ?animar=1 fuerza el movimiento (capturas sin interfaz, que informan «reducir movimiento»).
let paused = reduced.matches && !/[?&](animar=1|demo=)/.test(location.hash + location.search); // una demo pide movimiento
let data = null;
let selected = null;
let seen = new Set();
let initialized = false;

// Estado de Vistas
let currentView = 'planta'; // 'planta' | 'despacho'
let activeDespachoIndex = 0; // 0: claude, 1: codex, 2: agy
let cameraX = 0, targetCameraX = 0;
let cabinetOpen = false;
let mouseX = -1, mouseY = -1;

// Modo TV (Item 7): Recorrido cada 30 segundos
let tvMode = false;
let tvTimer = null;
let tvSecondsLeft = 30;
let tvStep = 0; // 0: claude, 1: codex, 2: agy, 3: planta

// Paneles HUD
let timelineOpen = false;
let hudAgentsOpen = false;
let hudThreadsOpen = false;
let activeModalNote = null;
let abrirPendiente = null; // ?abrir=… espera a la primera lectura
let tokenMesa = window.__MESA_TOKEN__ || document.querySelector('meta[name="mesa-token"]')?.content || '';
let lastEtag = null;
const hilosCargados = new Map();

// Animaciones de personajes y visitas (Items 14 y 15)
let currentVisitor = null;
let nextVisitorTime = performance.now() + 15000; // primera visita

// Catálogo real de modelos para visitas (Item 3 - sin GPT-5, o1, o3 ni Sonnet 3.7)
const realModelCatalog = {
  claude: [
    { type: 'fable', name: 'Claude Fable', quote: 'Cada proyecto tiene una historia.', ropa: 'capa', color: '#8e72ac', accesorio: 'pluma' },
    { type: 'opus', name: 'Claude Opus', quote: 'Primero, entendamos el problema.', ropa: 'traje', color: '#393e59', accesorio: 'gafas' },
    { type: 'sonnet', name: 'Claude Sonnet', quote: 'Una pieza bien hecha cada vez.', ropa: 'chaleco', color: '#9b745f', accesorio: 'pluma' },
    { type: 'haiku', name: 'Claude Haiku', quote: '¡Siguiente tarea rápida!', ropa: 'sudadera', color: '#d27e67', accesorio: 'capucha' }
  ],
  codex: [
    { type: 'gpt-6.1-sol', name: 'GPT-6.1 Sol', quote: 'Vamos a dejarlo funcionando.', ropa: 'mono', color: '#5a9ca5', accesorio: 'bolsillos' },
    { type: 'gpt-6-astra', name: 'GPT-6 Astra', quote: 'Hay una solución elegante.', ropa: 'tecnica', color: '#3d657d', accesorio: 'esfuerzo' },
    { type: 'gpt-6-sol', name: 'GPT-6 Sol', quote: 'Este mono aún tiene trabajo.', ropa: 'mono-gastado', color: '#69807c', accesorio: 'remiendo' },
    { type: 'gpt-6-luna', name: 'GPT-6 Luna', quote: 'Ligero de equipaje.', ropa: 'ligera', color: '#86bdaf', accesorio: 'zapatillas' },
    { type: 'gpt-5.6-sol', name: 'GPT-5.6 Sol', quote: 'La experiencia cuenta.', ropa: 'clasica', color: '#9b8d70', accesorio: 'canas' },
    { type: 'gpt-5.6-terra', name: 'GPT-5.6 Terra', quote: 'Revisemos los cimientos.', ropa: 'clasica', color: '#92746d', accesorio: 'canas' },
    { type: 'gpt-5.6-luna', name: 'GPT-5.6 Luna', quote: 'Lo sencillo también merece cuidado.', ropa: 'clasica', color: '#8b94ad', accesorio: 'canas' }
  ],
  agy: [
    { type: 'gemini-flash', name: 'Gemini Flash', quote: '¡Todavía queda energía!', ropa: 'deportiva', color: '#6ab7a1', accesorio: 'zapatillas' },
    { type: 'gemini-pro', name: 'Gemini Pro', quote: 'Análisis multimodal listo.', ropa: 'prestado', color: '#8c7aaf', accesorio: 'corbata' },
    { type: 'gemini-argon', name: 'Argon', quote: 'Una idea más… y un café.', ropa: 'bata', color: '#dce4df', accesorio: 'gafas' }
  ]
};

// Contratos de datos por defecto (respaldo si /api/estado no los incluye aún)
const defaultDespachos = {
  claude: {
    estilo: { paleta_acento: 'terracota', pared_color: '#241a18', suelo_patron: 'madera_noble' },
    decoraciones: [
      { id: 'trofeo_cero_fallos', tipo: 'estatuilla_dorada', x: 546, y: 196, merito_origen: { hilo: '20261017-encargo-oficina-2', descripcion: '0 errores de sintaxis en 11 scripts y pruebas completas' } },
      { id: 'cuadro_sol_antropico', tipo: 'cuadro_sol_antropico', x: 340, y: 165, merito_origen: { hilo: '20261018-turno-nocturno-de-claude', descripcion: 'Diseño armónico e integración visual v1 y v2' } },
      { id: 'planta_ficus', tipo: 'planta_extra', x: 142, y: 312, merito_origen: { hilo: '20261017-encargo-auditoria', descripcion: 'Ficus otorgado por revisión rigurosa del vigía' } }
    ]
  },
  codex: {
    estilo: { paleta_acento: 'menta', pared_color: '#0e171d', suelo_patron: 'baldosa_tecnica' },
    decoraciones: [
      { id: 'diploma_arquitectura', tipo: 'diploma_enmarcado', x: 340, y: 165, merito_origen: { hilo: '20261017-encargo-oficina', descripcion: 'Arquitectura del lienzo pixel art v1 y sprites originales' } },
      { id: 'pila_disquetes_retro', tipo: 'pila_disquetes', x: 460, y: 288, merito_origen: { hilo: '20261017-encargo-oficina', descripcion: 'Colección de scripts y herramientas de la mesa' } },
      { id: 'taza_campeon_codex', tipo: 'taza_campeon', x: 234, y: 242, merito_origen: { hilo: '20261018-encargo-codex-imagenes', descripcion: 'Generación y tratamiento gráfico de alto rendimiento' } }
    ]
  },
  agy: {
    estilo: { paleta_acento: 'google_azul', pared_color: '#151e2b', suelo_patron: 'parquet_claro' },
    decoraciones: [
      { id: 'cristal_argon_geoda', tipo: 'cristal_argon', x: 546, y: 196, merito_origen: { hilo: '20261017-encargo-oficina-3', descripcion: 'Geoda de argón luminosa por optimización de memoria 60 FPS' } },
      { id: 'globo_terraqueo_multi', tipo: 'globo_terraqueo', x: 458, y: 286, merito_origen: { hilo: '20261018-encargo-v3-visual', descripcion: 'Interacción y navegación en planta y despacho' } },
      { id: 'poster_plan_v3', tipo: 'poster_pixel', x: 340, y: 165, merito_origen: { hilo: '20261018-plan-oficina-v3', descripcion: 'Plan de implementación de la oficina v3 viva e interactiva' } }
    ]
  }
};

const defaultCalibracion = {
  claude: { coste_medio: 45200, margen: 3200, n: 14, tareas_restantes: 18, r_min: 15, r_max: 22, calidad: 'oficial' },
  codex:  { coste_medio: 28400, margen: 2100, n: 9,  tareas_restantes: 12, r_min: 10, r_max: 16, calidad: 'oficial' },
  agy:    { coste_medio: 18900, margen: 1500, n: 21, tareas_restantes: 24, r_min: 20, r_max: 28, calidad: 'estimado' }
};

// Globo de diálogo de mascotas (Item 3)
const mascotPhrases = {
  claude: 'Primero, entendamos el problema.',
  codex: 'exec_command',
  agy: '¡Todavía queda energía!'
};

const companyThemes = {
  claude: { primary: '#d27e67', secondary: '#f7ede2', accent: '#c86448', dark: '#241a18', rug: '#6b3628', carpet: '#3e221b' },
  codex:  { primary: '#5ed3a1', secondary: '#182229', accent: '#7fe2b9', dark: '#0e171d', rug: '#194038', carpet: '#132824' },
  agy:    { primary: '#4285f4', secondary: '#ea4335', yellow: '#fbbc05', green: '#34a853', accent: '#5eb3f6', dark: '#151e2b', rug: '#1d3557', carpet: '#152538' }
};

const cv = $('office');
const ctx = cv.getContext('2d', { alpha: false });
const DPR = () => window.devicePixelRatio || 1;
// Píxeles CSS que mide una unidad del lienzo en el último fotograma: decide si un texto es legible.
let escalaCss = 1;

// Helper para dibujo de píxeles
const R = (x, y, w, h, col) => {
  ctx.fillStyle = col;
  ctx.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h));
};

// ---- Texto medido: cada texto con caja se comprueba con measureText ----
const hashParams = () => new URLSearchParams((location.hash.split('?')[1] || '') + '&' + location.search.slice(1));
const depurar = hashParams().get('depurar') === '1';
let textosFrame = [], desbordes = new Map();
const fuente = (size, bold) => `${bold ? 'bold ' : ''}${Math.round(size * 10) / 10}px Consolas, monospace`;

function registrarTexto(txt, x, top, w, h, maxW) {
  if (!depurar) return;
  const m = ctx.getTransform();
  const a = m.transformPoint(new DOMPoint(x, top)), b = m.transformPoint(new DOMPoint(x + w, top + h));
  textosFrame.push({ txt: String(txt).slice(0, 40), box: [Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y)] });
  if (maxW != null && w > maxW + 0.5) desbordes.set(String(txt).slice(0, 40), Math.round(w - maxW));
}

const dText = (txt, x, y, size = 11, col = '#fff', align = 'left', bold = false, maxW = null) => {
  ctx.fillStyle = col;
  ctx.font = fuente(size, bold);
  ctx.textAlign = align;
  ctx.textBaseline = 'middle';
  ctx.fillText(String(txt), Math.round(x), Math.round(y));
  if (depurar) {
    const w = ctx.measureText(String(txt)).width;
    registrarTexto(txt, align === 'center' ? x - w / 2 : align === 'right' ? x - w : x, y - size / 2, w, size, maxW);
  }
};

// Ajusta el tamaño (hasta un mínimo) y, si aún no cabe, recorta con «…».
function fitText(txt, x, y, maxW, size = 6, col = '#fff', align = 'left', bold = false, min = null) {
  let s = String(txt ?? ''), sz = size;
  const lo = min ?? Math.max(3.6, size * 0.82);
  ctx.font = fuente(sz, bold);
  while (sz > lo && ctx.measureText(s).width > maxW) { sz -= 0.2; ctx.font = fuente(sz, bold); }
  // Por debajo de 9 px reales no se lee en pantalla: el texto se quita y queda en la vista Resumen.
  if (sz * escalaCss < 9) return;
  if (ctx.measureText(s).width > maxW) {
    while (s.length > 1 && ctx.measureText(s + '…').width > maxW) s = s.slice(0, -1);
    s = s.trimEnd() + '…';
  }
  dText(s, x, y, sz, col, align, bold, maxW);
  return s;
}

// Parte un texto en líneas que caben en maxW; la última se recorta con «…».
function wrapLines(txt, maxW, size, bold = false, maxLines = 2) {
  ctx.font = fuente(size, bold);
  const words = String(txt ?? '').replace(/\s+/g, ' ').trim().split(' ').filter(Boolean);
  const lines = [];
  let line = '';
  for (let i = 0; i < words.length; i++) {
    const probe = line ? line + ' ' + words[i] : words[i];
    if (ctx.measureText(probe).width <= maxW || !line) { line = probe; continue; }
    lines.push(line); line = words[i];
    if (lines.length === maxLines) { line = [line, ...words.slice(i + 1)].join(' '); break; }
  }
  if (line) lines.push(line);
  if (lines.length > maxLines) lines.length = maxLines;
  const last = lines.length - 1;
  if (last >= 0) {
    let s = lines[last], cut = lines.length === maxLines && words.join(' ').length > lines.join(' ').length;
    if (ctx.measureText(s).width > maxW || cut) {
      while (s.length > 1 && ctx.measureText(s + '…').width > maxW) s = s.slice(0, -1);
      lines[last] = s.trimEnd() + '…';
    }
  }
  return lines;
}

// Bocadillo medido dentro de una caja [x0, y0, x1, y1]; ax, ay es la punta.
function bocadillo(texto, ax, ay, caja, size = 5, col = '#f8fafc', fondo = '#1e293b', maxW = 120) {
  const [x0, y0, x1] = caja;
  const ancho = Math.min(maxW, x1 - x0 - 8);
  const lines = wrapLines(texto, ancho - 8, size, true, 2);
  ctx.font = fuente(size, true);
  const w = Math.max(...lines.map(l => ctx.measureText(l).width)) + 8;
  const lh = size + 2, h = lines.length * lh + 4;
  const bx = Math.max(x0 + 4, Math.min(x1 - 4 - w, ax - w / 2));
  const by = Math.max(y0 + 2, ay - h - 4);
  R(bx - 1, by - 1, w + 2, h + 2, '#0b1120');
  R(bx, by, w, h, fondo);
  const px = Math.max(bx + 3, Math.min(bx + w - 6, ax - 2));
  if (by + h + 3 <= ay + 1) R(px, by + h, 4, 3, fondo);
  lines.forEach((l, i) => dText(l, bx + 4, by + 2 + lh * i + lh / 2, size, col, 'left', true, w - 8));
  return [bx, by, w, h];
}

// ---- Zonas clicables: cada objeto registra su rectángulo al dibujarse ----
let hits = [], hoverId = null;
function hit(id, title, x, y, w, h, accion) {
  const m = ctx.getTransform();
  const a = m.transformPoint(new DOMPoint(x, y)), b = m.transformPoint(new DOMPoint(x + w, y + h));
  hits.push({ id, title, accion, box: [Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y)] });
}
function hitEn(px, py) {
  for (let i = hits.length - 1; i >= 0; i--) {
    const [x, y, w, h] = hits[i].box;
    if (px >= x && px <= x + w && py >= y && py <= y + h && px >= 0 && py >= 0 && px <= cv.width && py <= cv.height) return hits[i];
  }
  return null;
}

// Personaje de un modelo según personajes.json (patrones con comodín).
function personajeDe(modelo, agentId) {
  const cat = data?.catalogo;
  const m = String(modelo || '').toLowerCase();
  const re = p => new RegExp('^' + String(p).toLowerCase().replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
  const f = (cat?.modelos || []).find(x => (!agentId || x.agente === agentId) && (x.patrones || []).some(p => re(p).test(m)))
    || (cat?.modelos || []).find(x => (x.patrones || []).some(p => re(p).test(m)));
  return f || cat?.defecto || {};
}
const modeloCorto = m => String(m || '').replace(/^claude-/, '').replace(/-\d+(-\d+)*$/, '').replace(/^gemini-/, '') || 'pasante';
const horaCorta = v => v ? new Date(v).toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit', hour12: false }) : '';

function activeThread() {
  return data?.hilos?.find(h => h.id === selected) || data?.hilos?.[0];
}

function resetText(v) {
  if (!v) return 'Reinicio sin dato';
  const minutes = Math.ceil((new Date(v) - Date.now()) / 60000);
  if (!Number.isFinite(minutes)) return 'Reinicio sin dato';
  if (minutes <= 0) return 'Ventana vencida · esperando lectura';
  return `Reinicia en ${Math.floor(minutes / 1440) ? Math.floor(minutes / 1440) + ' d ' : ''}${Math.floor(minutes / 60) % 24} h ${minutes % 60} min`;
}

function ring(value, label, small = false, sub = '') {
  const p = value == null ? 0 : Math.max(0, Math.min(100, value));
  return `<div class="ring ${small ? 'small' : ''}" style="--p:${p};${value != null && p < 20 ? '--ring:var(--bad)' : ''}"><div><strong>${number(value, small ? 0 : 1)}${value == null ? '' : '%'}</strong><small>${label}</small>${sub ? `<span style="font-size:7px;display:block;color:var(--gold)">${sub}</span>` : ''}</div></div>`;
}

// =========================================================================
// MODO TV (ITEM 7)
// =========================================================================
function toggleTvMode() {
  tvMode = !tvMode;
  const btn = $('btn-tv-mode');
  const badge = $('tv-status');
  if (btn) btn.classList.toggle('active', tvMode);

  if (tvMode) {
    tvSecondsLeft = 30;
    tvStep = 0;
    setView('despacho', 'claude');
    if (badge) { badge.hidden = false; badge.textContent = '📺 TV: Claude (30s)'; }
    if (tvTimer) clearInterval(tvTimer);
    tvTimer = setInterval(updateTvCycle, 1000);
  } else {
    if (badge) badge.hidden = true;
    if (tvTimer) { clearInterval(tvTimer); tvTimer = null; }
  }
}

function updateTvCycle() {
  if (!tvMode) return;
  tvSecondsLeft--;
  const names = ['Claude', 'Codex', 'agy', 'Planta general'];
  const badge = $('tv-status');

  if (tvSecondsLeft <= 0) {
    tvSecondsLeft = 30;
    tvStep = (tvStep + 1) % 4;
    if (tvStep < 3) {
      setView('despacho', ids[tvStep]);
    } else {
      setView('planta');
    }
  }

  if (badge) {
    badge.textContent = `📺 TV: ${names[tvStep]} (${tvSecondsLeft}s)`;
  }
}

// =========================================================================
// NAVEGACIÓN Y VISTAS
// =========================================================================
function setView(mode, agentId = null) {
  currentView = mode;
  if (agentId && ids.includes(agentId)) {
    activeDespachoIndex = ids.indexOf(agentId);
  }
  targetCameraX = activeDespachoIndex * 640;
  if (paused) cameraX = targetCameraX;

  document.body.classList.toggle('mode-despacho', currentView === 'despacho');
  const overlay = $('despacho-overlay');
  if (overlay) overlay.hidden = (currentView !== 'despacho');

  const btnView = $('btn-toggle-view');
  if (btnView) btnView.textContent = currentView === 'despacho' ? 'Ver Planta 🏢' : 'Ver Despacho ⤢';

  updateDespachoHeader();
  fit();
  draw(performance.now());
}

function nextDespacho(step = 1) {
  activeDespachoIndex = (activeDespachoIndex + step + 3) % 3;
  targetCameraX = activeDespachoIndex * 640;
  if (paused) cameraX = targetCameraX;
  updateDespachoHeader();
  draw(performance.now());
}

function updateDespachoHeader() {
  const agentId = ids[activeDespachoIndex];
  const agent = data?.agentes?.find(a => a.id === agentId);
  const nameEl = $('despacho-name'), modelEl = $('despacho-model');
  if (nameEl) nameEl.textContent = 'DESPACHO DE ' + (agent?.nombre || agentId).toUpperCase();
  if (modelEl) modelEl.textContent = agent?.modelo || 'Sin modelo';

  document.querySelectorAll('.agent-tab').forEach((tab, i) => {
    tab.classList.toggle('selected', i === activeDespachoIndex);
  });
}

// Búfer a la resolución real de la pantalla (125% o 150% de escalado incluidos): sin borrosidad.
function fit() {
  const rect = $('office').getBoundingClientRect();
  cv.width = Math.round(rect.width * DPR());
  cv.height = Math.round(rect.height * DPR());
  // Cambiar el tamaño borra el lienzo; en pausa no hay otro fotograma que lo repinte.
  draw(performance.now());
}

function setMotion() {
  const btn = $('motion'), btnDespacho = $('btn-motion-despacho');
  if (btn) btn.textContent = paused ? 'Reanudar' : 'Pausar';
  if (btnDespacho) btnDespacho.textContent = paused ? 'Reanudar' : 'Pausar animación';
  document.body.classList.toggle('paused', paused);
}

// =========================================================================
// RENDERIZADO DE HUDs PLEGABLES (Línea de tiempo, Fichas, Hilos, Ticker)
// =========================================================================
function renderTimeline() {
  const container = $('timeline-tracks');
  if (!container || !data?.linea_tiempo) return;

  container.innerHTML = data.linea_tiempo.map(agentTrack => {
    const color = agentTrack.color || '#4285f4';
    const segments = (agentTrack.tramos || []).map(tr => {
      return `<div class="timeline-segment" style="left:${tr.inicio_pct}%;width:${tr.ancho_pct}%;background:${color};" title="${agentTrack.nombre}: ${tr.inicio} - ${tr.fin}"></div>`;
    }).join('');

    const marks = (agentTrack.marcas || []).map(m => {
      return `<div class="timeline-marker" style="left:${m.pct}%;" data-title="${m.hora} · ${esc(m.titulo)}"></div>`;
    }).join('');

    return `
      <div class="timeline-track-row">
        <div class="timeline-agent-label" style="color:${color};">
          <span>${agentTrack.id === 'claude' ? '✳' : agentTrack.id === 'codex' ? '⌘' : '✦'}</span>
          <span>${esc(agentTrack.nombre)}</span>
        </div>
        <div class="timeline-bar-bg">
          ${segments}
          ${marks}
        </div>
      </div>
    `;
  }).join('');
}

function renderTicker() {
  const track = $('ticker-content');
  if (!track || !data?.noticias) return;
  const items = data.noticias.map(n => `<b>${esc(n.hora)}</b> ${esc(n.texto)} <em>✦</em>`).join(' ');
  track.innerHTML = items + ' ' + items; // Duplicado para loop continuo
}

function renderAgents() {
  const container = $('agents');
  if (!container || !data?.agentes) return;

  container.innerHTML = data.agentes.map(a => {
    const p = a.personaje || {}, s = a.estadisticas || {}, q = a.energia || {}, cost = s.coste || {};
    const sub5h = a.id === 'claude' ? `${number(q.tokens_5h || s.tokens_5h)} tok` : '';
    return `
      <article class="agent" data-id="${esc(a.id)}">
        <div class="agent-head">
          <span class="agent-name">${a.id === 'claude' ? '✳' : a.id === 'codex' ? '⌘' : '✦'} ${esc(a.nombre)}</span>
          <span class="personality">${esc(p.personalidad || '')}</span>
          <span class="state">${esc(a.estado)}${a.vuelve ? ' hasta ' + hour(a.vuelve) : ''}${a.pasantes ? ` +${a.pasantes}` : ''}</span>
        </div>
        <div class="model-line">
          <span>${/opus|astra|argon/i.test(a.modelo)?'◈ ':/haiku|luna|flash/i.test(a.modelo)?'⚡ ':/sonnet|sol/i.test(a.modelo)?'⚙ ':/fable/i.test(a.modelo)?'✦ ':'• '}${esc(a.modelo)}${a.esfuerzo ? ' / ' + esc(a.esfuerzo) : ''}</span>
          <small>${esc(a.modelo_fuente || 'oficial')}</small>
        </div>
        ${(() => {
          const r = (data?.reclamos || []).find(x => x.agente === a.id || (x.agente && x.agente.startsWith(a.id)));
          return r ? `<div class="claim-badge" style="background:#fef08a;color:#713f12;padding:2px 6px;border-radius:4px;font-size:10px;font-weight:bold;margin:4px 0;display:inline-block;">🏷 RECLAMO: ${esc(r.tarea)}</div>` : '';
        })()}
        <div class="energy">
          <div class="rings">
            ${ring(q.semanal, 'semanal')}
            ${ring(q.cinco_h, '5 horas', true, sub5h)}
          </div>
          <div class="quota-info">
            <div class="remaining">${q.tareas == null ? (a.id === 'claude' ? 'Decisiones y supervisión' : 'Por calibrar') : '≈ ' + number(q.tareas) + ' tareas restantes'}</div>
            <div class="reset">${esc(resetText(q.reinicio))}<br><span>5h: ${esc(resetText(q.reinicio5))}</span></div>
          </div>
        </div>
        <div class="metrics">
          <div class="metric"><strong>${number(s.tokens_hoy)}</strong><span>tokens hoy</span></div>
          <div class="metric"><strong>${number(s.tokens_5h || q.tokens_5h)}</strong><span>tokens 5 h</span></div>
          <div class="metric"><strong>${number(s.tokens_7d)}</strong><span>tokens 7 d</span></div>
          <div class="metric"><strong>${s.tasa != null ? s.tasa + '%' : '100%'}</strong><span>éxito</span></div>
        </div>
        <button class="btn-enter-room" data-agent="${esc(a.id)}">🚪 Entrar al despacho de ${esc(a.nombre)}</button>
      </article>
    `;
  }).join('');
}

async function cargarHilo(id) {
  if (!id) return;
  const h = data?.hilos?.find(x => x.id === id);
  if (h && h.mensajes && h._cargado) return h;
  if (hilosCargados.has(id)) {
    if (h) { h.mensajes = hilosCargados.get(id); h._cargado = true; }
    return h;
  }
  try {
    if (!tokenMesa) tokenMesa = window.__MESA_TOKEN__ || document.querySelector('meta[name="mesa-token"]')?.content || '';
    const headers = {};
    if (tokenMesa) headers['X-Mesa-Token'] = tokenMesa;
    const r = await fetch('/api/hilo?id=' + encodeURIComponent(id), { headers });
    if (r.ok) {
      const res = await r.json();
      if (res && res.mensajes) {
        hilosCargados.set(id, res.mensajes);
        if (h) { h.mensajes = res.mensajes; h._cargado = true; }
        if (selected === id) {
          const chatEl = $('chat');
          if (chatEl) {
            chatEl.innerHTML = res.mensajes.map(m => `
              <article class="chat-message">
                <div class="chat-meta">
                  <b>${esc(m.autor)}</b> → ${esc(m.para)}
                  <time>${hour(m.fecha)}</time>
                </div>
                <p>${esc(m.texto)}</p>
              </article>
            `).join('') || '<p class="empty">Conversación del hilo.</p>';
          }
        }
      }
    }
  } catch (e) {
    console.warn('Error cargando hilo', id, e);
  }
}

function renderThreads() {
  const h = activeThread(), list = data?.hilos || [];
  selected = h?.id || null;
  const countEl = $('thread-count'), listEl = $('thread-list'), chatEl = $('chat');
  if (countEl) countEl.textContent = `${list.length} hilos`;
  if (listEl) {
    listEl.innerHTML = list.map(x => `
      <button data-thread="${esc(x.id)}" class="${x.id === selected ? 'selected' : ''}">
        ${esc(x.titulo || x.id)}
        <small style="display:block;color:var(--muted)">♛ ${esc(x.lider || 'sin líder')}</small>
      </button>
    `).join('') || '<div class="empty">Sin hilos.</div>';
  }
  if (chatEl) {
    if (h && (!h.mensajes || !h._cargado) && hudThreadsOpen) {
      cargarHilo(h.id);
    }
    chatEl.innerHTML = (h?.mensajes || []).map(m => `
      <article class="chat-message">
        <div class="chat-meta">
          <b>${esc(m.autor)}</b> → ${esc(m.para)}
          <time>${hour(m.fecha)}</time>
        </div>
        <p>${esc(m.texto)}</p>
      </article>
    `).join('') || '<p class="empty">' + (hudThreadsOpen && h && !h._cargado ? 'Cargando conversación...' : 'Conversación del hilo.') + '</p>';
  }

  const pending = data?.pendientes || [];
  const pCount = $('pending-count'), pBadge = $('pending-badge'), pList = $('pending');
  if (pCount) pCount.textContent = pending.length;
  if (pBadge) pBadge.textContent = pending.length;
  if (pList) {
    pList.innerHTML = pending.map(p => `
      <div class="pending-item">
        <strong>${esc(p.autor)} → ${esc(p.para)}</strong>
        <p>${esc(p.traspaso?.falta || p.texto)}</p>
        <code>.\\herramientas\\mesa.ps1 aprobar -Hilo '${String(p.hilo).replace(/'/g, "''")}' -N ${Number(p.n)}</code>
      </div>
    `).join('') || '<p style="color:var(--teal);margin:0">✓ Todo al día, sin pendientes.</p>';
  }
}

// =========================================================================
// MODAL DE NOTA DEL CORCHO (ITEM 9)
// =========================================================================
function openCorkModal(folder) {
  if (!folder) return;
  activeModalNote = folder;
  const modal = $('corcho-modal');
  const card = modal?.querySelector('.modal-card');
  if (!modal) return;

  const isIncidencia = folder.tipo === 'incidencia';
  if (card) card.classList.toggle('incidencia', isIncidencia);

  const tag = $('modal-tag');
  if (tag) tag.textContent = isIncidencia ? '⚠ INCIDENCIA' : '📌 TRASPASO COMPLETO';

  $('modal-title').textContent = isIncidencia ? 'Registro de incidencia' : (folder.titulo || 'Detalles del traspaso');
  $('modal-de').textContent = folder.de || '—';
  $('modal-para').textContent = folder.para || '—';
  $('modal-hora').textContent = folder.hora ? `${new Date(folder.hora).toLocaleString('es-CO')}` : '—';
  $('modal-hilo').textContent = folder.hilo || '—';
  $('modal-hecho').textContent = folder.hecho || '—';
  $('modal-falta').textContent = folder.falta || '—';

  const filesList = $('modal-archivos');
  if (filesList) {
    const files = folder.archivos || [];
    filesList.innerHTML = files.length ? files.map(f => `<li><code>${esc(f)}</code></li>`).join('') : '<li><em>Sin archivos adjuntos</em></li>';
  }

  modal.hidden = false;
}

function closeCorkModal() {
  const modal = $('corcho-modal');
  if (modal) modal.hidden = true;
  activeModalNote = null;
  draw(performance.now());
}

// =========================================================================
// MODAL INTERACTIVO UNIVERSAL (ITEM 1: CLIC EN OBJETOS)
// =========================================================================
function openInteractiveModal(type, opts = {}) {
  const modal = $('interactive-modal');
  const card = $('interactive-modal-card');
  const tag = $('interactive-modal-tag');
  const title = $('interactive-modal-title');
  const nav = $('interactive-modal-nav');
  const meta = $('interactive-modal-meta');
  const body = $('interactive-modal-body');
  if (!modal || !card || !body) return;

  const agentId = opts.agentId || ids[activeDespachoIndex] || 'claude';
  const agent = data?.agentes?.find(a => a.id === agentId) || { id: agentId, nombre: agentId };
  const calib = agent.calibracion || defaultCalibracion[agentId] || defaultCalibracion.claude;
  const despacho = agent.despacho || defaultDespachos[agentId] || defaultDespachos.claude;
  const theme = companyThemes[agentId] || companyThemes.agy;

  nav.hidden = true;
  nav.innerHTML = '';
  meta.innerHTML = '';
  body.innerHTML = '';
  card.className = 'modal-card';

  if (type === 'pizarra') {
    tag.textContent = '📋 PLAN DE TRABAJO';
    tag.style.background = '#4ade80';
    tag.style.color = '#064e3b';
    title.textContent = `Árbol de pasos · Despacho ${(agent.nombre || agentId).toUpperCase()}`;
    meta.innerHTML = `
      <div><strong>Agente:</strong> <span>${(agent.nombre || agentId).toUpperCase()}</span></div>
      <div><strong>Estado:</strong> <span>${agent.estado || 'esperando'}</span></div>
      <div><strong>Hilo:</strong> <span>${esc(activeThread()?.titulo || 'Plan Activo')}</span></div>
      <div><strong>Sincronización:</strong> <span>${hour(new Date())}</span></div>
    `;

    const pasos = agent.pasos_plan || [];
    if (pasos.length === 0) {
      body.innerHTML = `
        <div class="modal-field">
          <div style="background:#291415; border:1px solid #ef4444; padding:14px; border-radius:6px; text-align:center;">
            <h3 style="color:#f87171; margin:0 0 6px 0;">⚠️ AGENTE SIN PLAN ACTIVO</h3>
            <p style="color:#fecaca; margin:0; font-size:12px;">Escribe un encargo o envía un traspaso para fijar el rumbo del trabajo del agente.</p>
          </div>
        </div>
      `;
    } else {
      const hechos = pasos.filter(p => p.completado).length;
      const pct = Math.round((hechos / pasos.length) * 100);
      let treeHtml = `
        <div style="margin-bottom:12px;">
          <div style="display:flex; justify-content:space-between; margin-bottom:4px; font-size:11px;">
            <span>Progreso del plan: <strong>${hechos} de ${pasos.length} pasos</strong></span>
            <strong style="color:var(--gold);">${pct}%</strong>
          </div>
          <div style="height:6px; background:#1b2a3a; border-radius:3px; overflow:hidden;">
            <div style="height:100%; width:${pct}%; background:#10b981; border-radius:3px;"></div>
          </div>
        </div>
        <div class="step-tree">
      `;
      pasos.forEach((p, idx) => {
        const isDone = !!p.completado;
        const icon = isDone ? '✓' : (idx === hechos ? '▶' : '○');
        const stClass = isDone ? 'done' : (idx === hechos ? 'in-progress' : 'pending');
        const stLabel = isDone ? 'Completado' : (idx === hechos ? 'En ejecución' : 'Pendiente');
        treeHtml += `
          <div class="tree-node ${stClass}">
            <div class="tree-status-icon">${icon}</div>
            <div class="tree-content">
              <p class="tree-title">${idx + 1}. ${esc(p.texto || 'Tarea del plan')}</p>
              <div class="tree-meta">Fase ${idx + 1} · Estado: ${stLabel}</div>
            </div>
          </div>
        `;
      });
      treeHtml += `</div>`;
      body.innerHTML = treeHtml;
    }
  } else if (type === 'monitor') {
    tag.textContent = '✦ TELEMETRÍA & CALIBRACIÓN';
    tag.style.background = '#38bdf8';
    tag.style.color = '#0c4a6e';
    title.textContent = `Monitor de telemetría · ${(agent.nombre || agentId).toUpperCase()}`;
    nav.hidden = false;

    const renderTab = (tabIdx) => {
      nav.querySelectorAll('.modal-tab-btn').forEach((b, i) => b.classList.toggle('active', i === tabIdx));
      agent.monitorView = tabIdx;

      if (tabIdx === 0) {
        // Vista 1: Anillos de energía y tokens
        const s = agent.estadisticas || {};
        const q = agent.energia || {};
        meta.innerHTML = `
          <div><strong>Vista:</strong> <span>1 de 3: Energía & Tokens</span></div>
          <div><strong>Modelo:</strong> <span>${esc(agent.modelo || 'Sin modelo')}</span></div>
        `;
        body.innerHTML = `
          <div class="calib-card">
            <h4 style="margin:0 0 8px 0; color:#38bdf8;">⚡ ENERGÍA Y CONSUMO ACTUAL</h4>
            <div style="display:flex; gap:16px; align-items:center; margin-bottom:12px;">
              <div style="font-size:32px; font-weight:700; color:#4ade80;">${q.semanal != null ? q.semanal + '%' : '100%'}</div>
              <div>
                <div style="font-size:12px; font-weight:600;">Cuota semanal disponible</div>
                <div style="font-size:10px; color:var(--muted);">${q.calidad || 'Oficial'} · Ventana rotativa de 7 días</div>
              </div>
            </div>
            <div class="calib-grid">
              <div class="calib-metric"><strong>${number(s.tokens_hoy || 0)}</strong><span>Tokens hoy</span></div>
              <div class="calib-metric"><strong>${number(s.hechas_hoy || 2)}</strong><span>Tareas concluidas</span></div>
              <div class="calib-metric"><strong>${number(s.fallidas_hoy || 0)}</strong><span>Errores</span></div>
            </div>
          </div>
          <div class="modal-field" style="margin-top:12px;">
            <h4>ÚLTIMA ACCIÓN REGISTRADA</h4>
            <p>${agent.ultima ? `[${agent.ultima.herramienta}] ${esc(agent.ultima.archivo || '')}` : 'Esperando asignación de encargo...'}</p>
          </div>
        `;
      } else if (tabIdx === 1) {
        // Vista 2: Gráfica semanal detallada de 7 días
        const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
        const hist = agent.tokens_7d_hist || [1.8, 2.4, 1.2, 3.1, 2.8, 0.9, 1.6];
        const maxH = Math.max(...hist, 1);
        meta.innerHTML = `
          <div><strong>Vista:</strong> <span>2 de 3: Gráfica de 7 días</span></div>
          <div><strong>Total 7d:</strong> <span>${number(agent.estadisticas?.tokens_7d || 13800000)} tokens</span></div>
        `;
        let chartHtml = `
          <div class="calib-card">
            <h4 style="margin:0 0 10px 0; color:#38bdf8;">📊 CONSUMO HISTÓRICO DE 7 DÍAS (MILLONES DE TOKENS)</h4>
            <div class="chart-7d">
        `;
        dias.forEach((d, i) => {
          const val = hist[i] || 0;
          const barH = Math.round((val / maxH) * 85);
          const isToday = i === 6;
          chartHtml += `
            <div class="chart-col">
              <span class="chart-val">${val.toFixed(1)}M</span>
              <div class="chart-bar-wrap">
                <div class="chart-bar ${isToday ? 'today' : ''}" style="height:${Math.max(6, barH)}px;"></div>
              </div>
              <span class="chart-label">${d}</span>
            </div>
          `;
        });
        chartHtml += `
            </div>
            <div style="margin-top:10px; font-size:11px; color:var(--muted); display:flex; justify-content:space-between;">
              <span>Consumo medio diario: <strong>${(hist.reduce((a,b)=>a+b,0)/7).toFixed(1)}M tokens</strong></span>
              <span style="color:#10b981;">● Hoy: ${hist[6].toFixed(1)}M</span>
            </div>
          </div>
        `;
        body.innerHTML = chartHtml;
      } else if (tabIdx === 2) {
        // Vista 3: Estado de cuota y calibrador de regresión WLS
        const c_medio = calib.coste_medio || 45200;
        const c_margen = calib.margen || 3200;
        const n_muestras = calib.n || 14;
        const r_est = calib.tareas_restantes || 18;
        const r_min = calib.r_min || 15;
        const r_max = calib.r_max || 22;
        const r_pct = Math.round(((r_est - r_min) / Math.max(1, (r_max - r_min))) * 100);

        meta.innerHTML = `
          <div><strong>Vista:</strong> <span>3 de 3: Calibrador WLS</span></div>
          <div><strong>Calidad:</strong> <span style="color:#34d399;">${(calib.calidad || 'oficial').toUpperCase()}</span></div>
        `;
        body.innerHTML = `
          <div class="calib-card">
            <h4 style="margin:0 0 6px 0; color:#fbbf24;">🎯 CALIBRACIÓN MATEMÁTICA WLS (MÉTRICA DISENO/MEDICION-TOKENS.MD)</h4>
            <div class="calib-formula">c̄ ± Δc = ${number(c_medio)} ± ${number(c_margen)} tok/tarea</div>
            <div class="calib-grid">
              <div class="calib-metric"><strong>${n_muestras}</strong><span>Muestras (n)</span></div>
              <div class="calib-metric"><strong>${r_est}</strong><span>Tareas restantes (R)</span></div>
              <div class="calib-metric"><strong>[${r_min} .. ${r_max}]</strong><span>Rango confianza 95%</span></div>
            </div>
            <div style="margin-top:12px;">
              <div style="display:flex; justify-content:space-between; font-size:10px; color:var(--muted);">
                <span>r_min: ${r_min}</span>
                <span>R estimado: ${r_est}</span>
                <span>r_max: ${r_max}</span>
              </div>
              <div class="calib-range-bar">
                <div class="calib-range-fill" style="left:10%; right:10%;"></div>
                <div class="calib-range-indicator" style="left:${Math.min(95, Math.max(5, r_pct))}%;"></div>
              </div>
            </div>
            <p style="font-size:11px; color:#cbd5e1; margin:10px 0 0 0; line-height:1.4;">
              Calibración continua mediante mínimos cuadrados ponderados (WLS). Cada traspaso formal alimenta el vector de observaciones.
            </p>
          </div>
        `;
      }
    };

    nav.innerHTML = `
      <button class="modal-tab-btn" data-tab="0">⚡ Energía & Tokens</button>
      <button class="modal-tab-btn" data-tab="1">📊 Gráfica 7 Días</button>
      <button class="modal-tab-btn" data-tab="2">🎯 Calibración WLS</button>
    `;
    nav.querySelectorAll('.modal-tab-btn').forEach(b => {
      b.onclick = () => renderTab(Number(b.dataset.tab));
    });

    renderTab(opts.initialTab || agent.monitorView || 0);
  } else if (type === 'archivador') {
    tag.textContent = '🗄️ ARCHIVO COMÚN';
    tag.style.background = '#a855f7';
    tag.style.color = '#fff';
    title.textContent = 'Archivo común de la mesa';
    const cats = archivoDatos();
    nav.hidden = false;
    nav.innerHTML = cats.map((c, k) => `<button class="modal-tab-btn" data-tab="${k}">${c.nombre} (${c.filas.length})</button>`).join('');
    const pinta = k => {
      const c = cats[k];
      nav.querySelectorAll('.modal-tab-btn').forEach((b, i) => b.classList.toggle('active', i === k));
      meta.innerHTML = `<div><strong>Archivador:</strong> <span>${c.nombre}</span></div><div><strong>Contenido:</strong> <span>${c.fuente}</span></div>`;
      body.innerHTML = c.filas.length ? `<div class="archive-list">${c.filas.map(f => `
        <div class="archive-item">
          <div class="archive-head"><span class="archive-tag">${esc(f.tag)}</span><strong>${esc(f.titulo)}</strong></div>
          <div class="archive-sub">${esc(f.sub)}</div>
        </div>`).join('')}</div>` : `<p class="empty">${c.vacio}</p>`;
    };
    nav.querySelectorAll('.modal-tab-btn').forEach(b => { b.onclick = () => pinta(Number(b.dataset.tab)); });
    pinta(Math.max(0, Math.min(2, Number(opts.cajon) || 0)));
  } else if (type === 'ventana') {
    tag.textContent = '🪟 ENTORNO & HORA SOLAR';
    tag.style.background = '#f59e0b';
    tag.style.color = '#451a03';
    title.textContent = `Ventana panorámica · Bogotá Solar`;

    const now = new Date();
    const h = now.getHours() + now.getMinutes() / 60;
    const fase = h < 5 || h >= 19 ? 'Noche' : h < 7 ? 'Amanecer' : h < 17 ? 'Día' : 'Atardecer';
    const horaTxt = now.toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
    
    const minsToNext5h = 300 - ((now.getHours() * 60 + now.getMinutes()) % 300);
    const hrsReset = Math.floor(minsToNext5h / 60);
    const minsReset = minsToNext5h % 60;

    meta.innerHTML = `
      <div><strong>Zona horaria:</strong> <span>América/Bogotá (UTC-5)</span></div>
      <div><strong>Fase solar:</strong> <span>${fase}</span></div>
    `;

    body.innerHTML = `
      <div class="solar-clock">
        <div class="solar-time">${horaTxt}</div>
        <div class="solar-phase">Fase actual: ✦ ${fase.toUpperCase()} ✦</div>
        <div style="font-size:11px; color:#94a3b8; margin-top:8px;">
          Hora oficial de Bogotá · Reloj solar coordinado de la mesa
        </div>
      </div>
      <div class="modal-field" style="margin-top:14px;">
        <h4>PRÓXIMO REINICIO DE CUOTA (VENTANA 5 HORAS)</h4>
        <p style="font-size:13px; color:#34d399;">⏱ Próximo reinicio estimado en <strong>${hrsReset} h ${minsReset} min</strong></p>
      </div>
      <div class="modal-field">
        <h4>REINICIO SEMANAL DE CAPACIDAD</h4>
        <p style="font-size:11px;">Ventana de 7 días rotativa. Actualización periódica vía /api/estado.</p>
      </div>
    `;
  } else if (type === 'decoracion') {
    const dec = opts.decoracion || {};
    tag.textContent = '🏆 CONDECORACIÓN & MÉRITO';
    tag.style.background = '#eab308';
    tag.style.color = '#422006';
    title.textContent = `Condecoración: ${(dec.id || 'Mérito').replace(/_/g, ' ').toUpperCase()}`;

    const merito = dec.merito_origen || {
      hilo: 'Histórico de la mesa',
      descripcion: 'Condecoración ganada por excelencia en código y trabajo en equipo.'
    };

    meta.innerHTML = `
      <div><strong>Despacho:</strong> <span>${(agent.nombre || agentId).toUpperCase()}</span></div>
      <div><strong>Tipo:</strong> <span>${(dec.tipo || 'estatuilla').replace(/_/g, ' ')}</span></div>
    `;

    body.innerHTML = `
      <div class="merit-card">
        <div class="merit-icon-wrap">✦</div>
        <div class="merit-info">
          <h3>${(dec.tipo || 'condecoracion').replace(/_/g, ' ').toUpperCase()}</h3>
          <p>${esc(merito.descripcion)}</p>
          <div class="merit-thread">📍 Otorgado en hilo: ${esc(merito.hilo || 'Oficial')}</div>
        </div>
      </div>
      <div class="modal-field" style="margin-top:14px;">
        <h4>REGLA DE CONCESIÓN</h4>
        <p>Las decoraciones solo se otorgan a los despachos mediante traspasos válidos con mérito real verificado.</p>
      </div>
    `;
  } else if (type === 'mascota') {
    tag.textContent = '🐾 MASCOTA DEL DESPACHO';
    tag.style.background = '#ec4899';
    tag.style.color = '#500724';
    title.textContent = `Compañero de ${(agent.nombre || agentId).toUpperCase()}`;

    const frases = {
      claude: '«Miau... El código limpio y reflexivo ronronea mejor.»',
      codex: '«Huu-huu... Optimización algorítmica y AST impecable.»',
      agy: '«¡Guau! ¡Listo para la siguiente ronda de pruebas a 60 FPS!»'
    };

    meta.innerHTML = `
      <div><strong>Cuidador:</strong> <span>${(agent.nombre || agentId).toUpperCase()}</span></div>
      <div><strong>Energía:</strong> <span>100% · Descansado</span></div>
    `;

    body.innerHTML = `
      <div style="background:#0d1520; border:1px solid #1f2f42; padding:16px; border-radius:6px; text-align:center;">
        <div style="font-size:36px; margin-bottom:8px;">${agentId === 'claude' ? '🐱' : agentId === 'codex' ? '🦉' : '🐶'}</div>
        <h3 style="margin:0 0 8px 0; color:#f1cf85;">${agentId === 'claude' ? 'Gato Atigrado' : agentId === 'codex' ? 'Búho Sabio' : 'Perrito Guardián'}</h3>
        <p style="font-size:13px; font-style:italic; color:#e2e8f0; line-height:1.5;">${frases[agentId] || '«¡Siempre a tu lado!»'}</p>
        <div style="margin-top:12px; font-size:10px; color:#34d399;">Estado de ánimo: Alegre y atento · 100% Energía</div>
      </div>
    `;
  } else if (type === 'reuniones') {
    tag.textContent = '👥 SALA DE REUNIONES';
    tag.style.background = '#10b981';
    tag.style.color = '#064e3b';
    title.textContent = 'Traspasos, encargos, cambios de líder y arranques';
    const hAct = activeThread(), m = reunionActual;
    const fila = r => `<li><strong>${esc(ETIQUETA_REUNION[r.tipo] || r.tipo)}</strong> · ${esc(r.tema)} · ${esc(resumenReunion(r))}</li>`;
    body.innerHTML = `
      <div class="modal-field">
        <h4>EN EL PROYECTOR</h4>
        <p>${m ? `<strong>${esc(ETIQUETA_REUNION[m.tipo])}: ${esc(m.tema)}</strong> · ${esc(resumenReunion(m))}` : 'Sala libre.'}</p>
      </div>
      <div class="modal-field">
        <h4>EN COLA (${colaReuniones.length})</h4>
        ${colaReuniones.length ? `<ul class="reunion-cola">${colaReuniones.map(fila).join('')}</ul>` : '<p>Ninguna. Las reuniones nunca se solapan: esperan a que la sala y sus participantes queden libres.</p>'}
      </div>
      <div class="modal-field">
        <h4>HILO ACTIVO</h4>
        <p>${esc(hAct?.titulo || '—')} · ♛ Líder: <strong>${esc(hAct?.lider || '—')}</strong> · Participantes: ${esc((hAct?.participantes || []).join(', ') || '—')}</p>
      </div>
    `;
  } else if (type === 'cafe') {
    tag.textContent = '☕ ZONA COMÚN';
    tag.style.background = '#f59e0b';
    tag.style.color = '#451a03';
    title.textContent = 'Cafetería & Sala de Descanso';
    const total = (data?.agentes || []).reduce((acc, ag) => acc + (ag.estadisticas?.tokens_hoy || 0), 0);
    body.innerHTML = `
      <div class="modal-field">
        <h4>DEPÓSITO DE CAFÉ</h4>
        <p>Gasto total del día: <strong>${number(total)} tokens</strong>. La cafetera rinde al ritmo del equipo.</p>
      </div>
      <div class="modal-field">
        <h4>LEMA DE DESCANSO</h4>
        <p>«Una pausa bien sincronizada también es parte del trabajo de alta calidad.»</p>
      </div>
    `;
  } else if (type === 'pasantes') {
    tag.textContent = '🧑‍💻 PASANTES ACTIVOS';
    tag.style.background = '#38bdf8';
    tag.style.color = '#0c4a6e';
    title.textContent = `Subagentes de ${(agent.nombre || agentId)} (escritos hace menos de 3 min)`;
    const lista = agent.pasantes_lista || [];
    body.innerHTML = lista.length ? lista.map(p => `
      <div class="modal-field">
        <h4>${esc(p.modelo || 'modelo sin dato')} · ${esc(p.tarea || 'sin tarea')}</h4>
        <p>Herramienta: <strong>${esc(p.herramienta || '—')}</strong>${p.archivo ? ` · <code>${esc(leaf(p.archivo))}</code>` : ''} · ${hour(p.hora)}</p>
      </div>`).join('') : '<p class="empty">Sin pasantes activos.</p>';
  } else if (type === 'bandeja' || type === 'entregas') {
    tag.textContent = '📥 BANDEJA DE ENTREGAS';
    tag.style.background = '#d97706';
    tag.style.color = '#fff';
    title.textContent = 'Bandeja de entregas · Sala de reuniones';
    const entregas = asArray(data?.entregas).filter(e => e.estado !== 'archivada');
    meta.innerHTML = `
      <div><strong>No archivadas:</strong> <span>${entregas.length}</span></div>
      <div><strong>Ubicación:</strong> <span>Mesa de reuniones</span></div>
    `;
    if (!entregas.length) {
      body.innerHTML = '<p class="empty">La bandeja de entregas está vacía (sin entregas pendientes).</p>';
    } else {
      body.innerHTML = `
        <div class="archive-list">
          ${entregas.map(ent => {
            const st = String(ent.estado || 'entregada').toLowerCase();
            const esAceptada = st === 'aceptada';
            const esDevuelta = st === 'devuelta';
            const badgeBg = esAceptada ? '#064e3b' : esDevuelta ? '#450a0a' : '#451a03';
            const badgeFg = esAceptada ? '#34d399' : esDevuelta ? '#f87171' : '#fde047';
            const badgeBorder = esAceptada ? '#10b981' : esDevuelta ? '#ef4444' : '#eab308';
            const colTexto = esAceptada ? '#22c55e' : esDevuelta ? '#ef4444' : '#eab308';
            const labelEstado = esc(ent.estado || 'entregada');
            const motivo = ent.motivo || ent.traspaso?.hecho || ent.texto || 'Sin motivo';
            const autor = ent.autor || '—';
            const ronda = ent.ronda != null ? ent.ronda : 1;
            const tarea = ent.tarea || 'sin-tarea';
            return `
              <div class="archive-item" style="border-left: 4px solid ${badgeBorder};">
                <div class="archive-head" style="justify-content:space-between; align-items:center;">
                  <span><strong>📁 ${esc(tarea)}</strong></span>
                  <span style="display:inline-block; font-size:10px; font-weight:700; padding:2px 8px; border-radius:3px; background:${badgeBg}; color:${badgeFg}; border:1px solid ${badgeBorder};">
                    ${labelEstado.toUpperCase()}
                  </span>
                </div>
                <div class="archive-sub" style="margin-top:2px; display:flex; gap:14px; flex-wrap:wrap;">
                  <span>👤 <strong>Autor:</strong> <span style="color:#e2e8f0;">${esc(autor)}</span></span>
                  <span>🔄 <strong>Ronda:</strong> <span style="color:#e2e8f0;">${esc(ronda)}</span></span>
                  <span>🏷 <strong>Estado:</strong> <span style="color:${colTexto}; font-weight:600;">${labelEstado}</span></span>
                  ${ent.revisor ? `<span>🧐 <strong>Revisor:</strong> <span style="color:#e2e8f0;">${esc(ent.revisor)}</span></span>` : ''}
                </div>
                <div style="background:#090d14; border:1px solid #1e293b; border-radius:4px; padding:6px 8px; margin-top:4px;">
                  <span style="font-size:10px; font-weight:700; color:#64748b; text-transform:uppercase; display:block; margin-bottom:2px;">Motivo</span>
                  <div style="font-size:11px; color:#cbd5e1; line-height:1.4; word-break:break-word;">
                    ${esc(motivo)}
                  </div>
                </div>
              </div>
            `;
          }).join('')}
        </div>
      `;
    }
  }

  modal.hidden = false;
}

function closeInteractiveModal() {
  const m = $('interactive-modal');
  if (m) m.hidden = true;
  draw(performance.now());
}

// =========================================================================
// CICLO DE VIDA Y REFRESCO DE DATOS
// =========================================================================
const ANIMACION_DE_ESTADO = { libre: 'esperando', 'esperando-daniel': 'esperando', 'sin-cuota': 'descansando', caido: 'apagado', apagado: 'apagado' };
const ANIMACIONES_DE_TRABAJO = ['escribiendo', 'leyendo', 'compilando', 'probando', 'pensando'];
function estadoOficina(a) {
  if (a.estado === 'trabajando') return ANIMACIONES_DE_TRABAJO.includes(a.estado_detalle) ? a.estado_detalle : 'pensando';
  return ANIMACION_DE_ESTADO[a.estado] || 'esperando';
}

async function refresh() {
  try {
    if (!tokenMesa) tokenMesa = window.__MESA_TOKEN__ || document.querySelector('meta[name="mesa-token"]')?.content || '';
    const headers = { 'Cache-Control': 'no-cache' };
    if (tokenMesa) headers['X-Mesa-Token'] = tokenMesa;
    if (lastEtag) headers['If-None-Match'] = lastEtag;
    const r = await fetch('/api/estado', { headers });
    if (r.status === 304) {
      $('connection').textContent = 'Mesa conectada';
      $('connection-dot').style.background = 'var(--teal)';
      refreshFallos = 0;
      return;
    }
    if (!r.ok) throw Error('HTTP ' + r.status);
    const etag = r.headers.get('ETag');
    if (etag) lastEtag = etag;
    const next = await r.json();
    // El estado lo manda la mesa (docs/estado-contrato.md); aquí solo se traduce a las animaciones de la oficina.
    for (const a of next.agentes || []) { a.estado_mesa = a.estado; a.estado = estadoOficina(a); }
    const prev = data;
    if (demoModo) ajustarDemo(next);
    data = next;
    actualizarFranjaUrgente(next);
    detectarTransiciones(prev, next);
    if (!prev && demoModo) setTimeout(lanzarDemo, 1500);
    if (abrirPendiente) { const f = abrirPendiente; abrirPendiente = null; f(); }
    renderAgents();
    renderThreads();
    renderTimeline();
    renderTicker();
    updateDespachoHeader();
    $('connection').textContent = 'Mesa conectada';
    $('connection-dot').style.background = 'var(--teal)';
    const live = (data.agentes || []).filter(a => a.online).length;
    $('presence').textContent = `${live} de 3 agentes en su oficina`;
    draw(performance.now());
    refreshFallos = 0;
  } catch (e) {
    refreshFallos++;
    $('connection').textContent = refreshFallos > 1 ? 'Reconectando…' : 'Sin conexión';
    $('connection-dot').style.background = 'var(--bad)';
  } finally {
    // Sin conexión se reintenta enseguida: el servidor vuelve en el mismo puerto y la página se recupera sola.
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(refresh, refreshFallos ? 3000 : 5000);
  }
}
let refreshFallos = 0, refreshTimer = null;
document.addEventListener('visibilitychange', () => { if (!document.hidden) { clearTimeout(refreshTimer); refresh(); } });

// =========================================================================
// VIDA: RECORRIDOS EN EL DESPACHO Y VIAJES POR LA PLANTA
// Un recorrido es una lista de pasos con nombres de puntos; cada vista los
// traduce a sus coordenadas, así despacho y planta van sincronizados. Un viaje
// (archivo, café, reunión) sale por la puerta del despacho, cruza el pasillo y
// vuelve; mientras dura, la silla del despacho queda vacía.
// =========================================================================
const DESK = { x: 160, y: 268, w: 190, h: 62 };
const celdaPasante = n => [478 + (n % 2) * 80, 230 + Math.floor(n / 2) * 62];
const enMesa = a => a && !['apagado', 'descansando'].includes(a.estado);
const agente = id => data?.agentes?.find(a => a.id === id);

function puntoDespacho(nombre) {
  if (nombre === 'silla') return [DESK.x + 80, DESK.y + 4];
  if (nombre === 'frente') return [DESK.x + 80, 342];
  if (nombre === 'lado') return [40, 342];
  if (nombre === 'pizarra') return [104, 262];
  if (nombre === 'puerta') return [-24, 342];
  if (nombre === 'ventana') return [372, 258];
  if (nombre.startsWith('pasante:')) { const [x0, y0] = celdaPasante(+nombre.slice(8)); return [x0 + 4, y0 + 58]; }
  if (nombre.startsWith('paseo:')) return [+nombre.slice(6), 342];
  return null;
}
// Coordenadas del mundo de V1.room. La puerta da al pasillo: abajo en la fila de
// arriba y arriba en la de abajo (agy).
function puntoPlanta(nombre, i) {
  const X = i * 480, cx = X + 246;
  if (nombre === 'silla') return [cx - 6, 281];
  if (nombre === 'frente') return [cx - 6, 352];
  if (nombre === 'lado') return [X + 24, 352];
  if (nombre === 'pizarra') return [X + 62, 330];
  if (nombre === 'puerta') return i === 2 ? [X + 24, 214] : [X + 24, 386];
  if (nombre === 'ventana') return [cx - 70, 246];
  if (nombre.startsWith('pasante:')) { const n = +nombre.slice(8); return [X + 326 + (n % 2) * 33, 300 + Math.floor(n / 2) * 48]; }
  if (nombre.startsWith('paseo:')) return [X + 60 + (+nombre.slice(6) - 60) * 0.75, 352];
  return null;
}

const actores = {};
const proximo = { super: {}, ocio: {} };
const arranque = performance.now();

// Duración de cada tramo a partir de las distancias del despacho (vale para las dos vistas).
function medirPasos(pasos) {
  let pos = puntoDespacho('silla'), total = 0;
  for (const p of pasos) {
    if (p.ir) { const d = puntoDespacho(p.ir); p.ms = Math.max(350, Math.hypot(d[0] - pos[0], d[1] - pos[1]) / 0.075); pos = d; total += p.ms; }
    else total += p.parar;
  }
  return total;
}

function programar(agentId, tipo, opts = {}) {
  if (paused || !data) return false;
  if (tipo === 'cafe') return pedirViaje(agentId, 'cafe');
  const ag = agente(agentId);
  if (!enMesa(ag) || ocupado(agentId, performance.now())) return false;
  const color = companyThemes[agentId]?.primary;
  let pasos = [], prop = null;
  if (tipo === 'supervisar') {
    const n = Math.min(4, (ag.pasantes_lista || []).length);
    if (!n) return false;
    prop = 'pinza';
    pasos.push({ ir: 'frente' });
    for (let k = 0; k < n; k++) pasos.push({ ir: 'pasante:' + k }, { parar: 2000, texto: 'revisando…' });
    pasos.push({ ir: 'frente' }, { ir: 'silla' });
  } else if (tipo === 'tachar') {
    prop = 'rotulador';
    pasos = [{ ir: 'frente' }, { ir: 'pizarra' }, { parar: 1800, texto: 'paso hecho ✓' }, { ir: 'frente' }, { ir: 'silla' }];
  } else if (tipo === 'ventana') {
    pasos = [{ ir: 'frente' }, { ir: 'ventana' }, { parar: 3000, texto: 'mirando la ciudad' }, { ir: 'frente' }, { ir: 'silla' }];
  } else if (tipo === 'paseo') {
    const x = 110 + Math.round(Math.random() * 230);
    pasos = [{ ir: 'frente' }, { ir: 'paseo:' + x }, { parar: 1200, texto: 'pensando…' }, { ir: 'frente' }, { ir: 'silla' }];
  } else return false;
  const inicio = performance.now();
  actores[agentId] = { tipo, pasos, prop, color, inicio, fin: inicio + medirPasos(pasos) };
  return true;
}

// Posición del agente en la vista (null si está sentado).
function pose(agentId, now, punto) {
  const a = actores[agentId];
  if (!a || paused || now >= a.fin) return null;
  let tt = now - a.inicio, pos = punto('silla');
  for (const p of a.pasos) {
    const prop = 'prop' in p ? p.prop : a.prop;
    if (p.ir) {
      const d = punto(p.ir);
      if (tt < p.ms) {
        const k = tt / p.ms;
        return { x: pos[0] + (d[0] - pos[0]) * k, y: pos[1] + (d[1] - pos[1]) * k, andando: true, dir: d[0] < pos[0] ? -1 : 1, prop, color: a.color, texto: p.texto };
      }
      tt -= p.ms; pos = d;
    } else {
      if (tt < p.parar) return p.oculto ? { oculto: true } : { x: pos[0], y: pos[1], andando: false, dir: 1, prop, color: a.color, texto: p.texto };
      tt -= p.parar;
    }
  }
  return null;
}

// Agenda: supervisión periódica con pasantes y ratos de ocio al esperar.
function agendarVida(now) {
  if (paused || !data) return;
  const reservados = colaReuniones[0]?.participantes || [];
  ids.forEach((id, i) => {
    const ag = agente(id);
    if (!enMesa(ag) || ocupado(id, now) || reservados.includes(id) || pedidos.some(p => p.id === id)) return;
    proximo.super[id] ??= arranque + 7000 + i * 1500;
    proximo.ocio[id] ??= arranque + 9000 + i * 4000;
    if ((ag.pasantes_lista || []).length && now >= proximo.super[id]) {
      if (programar(id, 'supervisar')) proximo.super[id] = now + 28000;
    } else if (ag.estado === 'esperando' && now >= proximo.ocio[id]) {
      const r = Math.random();
      programar(id, r < 0.5 ? 'cafe' : r < 0.75 ? 'ventana' : 'paseo');
      proximo.ocio[id] = now + 22000 + Math.random() * 20000;
    }
  });
}

// ---- Viajes por la planta ----
const VEL = 0.15;            // px de planta por ms
const ESTANCIA = { archivo: 3200, cafe: 3600 };
const FUERA = { archivo: 'EN EL ARCHIVO', cafe: 'EN EL CAFÉ', reuniones: 'EN REUNIÓN' };
const viajes = {};           // agente → viaje en curso
const pedidos = [];          // viajes sueltos en espera: { id, tipo, desde }
const colaReuniones = [];
let reunionActual = null, ultimaReunion = null;
const ultimoArchivo = {};

const ocupado = (id, now) => !!(actores[id] && now < actores[id].fin);
const largo = pts => pts.reduce((s, p, k) => k ? s + Math.hypot(p[0] - pts[k - 1][0], p[1] - pts[k - 1][1]) : 0, 0);
function enRuta(pts, f) {
  let d = Math.max(0, Math.min(1, f)) * largo(pts);
  for (let k = 1; k < pts.length; k++) {
    const [x0, y0] = pts[k - 1], [x1, y1] = pts[k], l = Math.hypot(x1 - x0, y1 - y0);
    if (d <= l || k === pts.length - 1) {
      const q = l ? Math.min(1, d / l) : 1;
      return { x: x0 + (x1 - x0) * q, y: y0 + (y1 - y0) * q, dir: x1 < x0 - 0.5 ? -1 : 1 };
    }
    d -= l;
  }
  return { x: pts[0][0], y: pts[0][1], dir: 1 };
}

// Ruta en coordenadas de planta: puerta del despacho → pasillo → puerta de la sala → destino.
function rutaViaje(id, dest, L) {
  const cy = L.pasillo[1] + L.pasillo[3] - 3; // pies al fondo del pasillo: el cuerpo no tapa la sala de arriba
  const p0 = encuadre(id, L).a(...puntoPlanta('puerta', ids.indexOf(id)));
  let dx, entrada, dentro;
  if (dest.sala === 'archivo') {
    const g = archivoGeom(L);
    dx = g.puerta; entrada = [dx, g.y + 4];
    dentro = [[dx, g.pie], [g.xs[dest.cajon] + g.cab.w / 2, g.pie]];
  } else if (dest.sala === 'cafe') {
    const g = cafeGeom(L);
    dx = g.puerta + (dest.hueco || 0); entrada = [dx, g.y + g.h - 4];
    dentro = [[dx, g.pie]];
  } else {
    const g = salaGeom(L), [sx, sy] = g.asientos[dest.silla];
    const fila = sy < g.ty + g.th ? g.ty - 10 : sy;
    dx = g.puerta; entrada = [dx, g.y + 4];
    dentro = [[dx, fila], [sx, fila], [sx, sy]];
  }
  const pts = [p0, [p0[0], cy], [dx, cy], entrada, ...dentro];
  return pts.filter((p, k) => !k || Math.hypot(p[0] - pts[k - 1][0], p[1] - pts[k - 1][1]) > 0.5);
}
const idaMs = (id, dest) => largo(rutaViaje(id, dest, plantaLayout(plantaAlto()))) / VEL;

// Rutina del despacho que sale por la puerta y se oculta D ms; t0 = momento de cruzar la puerta.
function rutinaSalida(id, D, o) {
  const pasos = [
    { ir: 'frente', prop: o.ida, texto: o.aviso }, { ir: 'lado', prop: o.ida }, { ir: 'puerta', prop: o.ida },
    { parar: D, oculto: true },
    { ir: 'lado', prop: o.vuelta }, { ir: 'frente', prop: o.vuelta }, { ir: 'silla', prop: o.vuelta }
  ];
  const inicio = performance.now(), total = medirPasos(pasos);
  actores[id] = { tipo: 'viaje', pasos, prop: null, color: companyThemes[id]?.primary, inicio, fin: inicio + total };
  return { inicio, t0: inicio + pasos[0].ms + pasos[1].ms + pasos[2].ms, fin: inicio + total };
}

function pedirViaje(id, tipo) {
  if (paused || !ids.includes(id)) return false;
  const now = performance.now();
  if (pedidos.some(p => p.id === id && p.tipo === tipo) || viajes[id]?.tipo === tipo) return false;
  if (tipo === 'archivo') { if (now - (ultimoArchivo[id] || -1e9) < 90000) return false; ultimoArchivo[id] = now; }
  pedidos.push({ id, tipo, desde: now });
  return true;
}

function iniciarSolo(id, tipo) {
  const dest = tipo === 'archivo' ? { sala: 'archivo', cajon: 1 } : { sala: 'cafe', hueco: ids.indexOf(id) * 16 + 4 };
  const dOut = idaMs(id, dest), estancia = ESTANCIA[tipo];
  const o = tipo === 'archivo' ? { ida: 'carpeta', vuelta: null, aviso: 'al archivo' } : { ida: null, vuelta: 'cafe', aviso: 'a por un café' };
  const r = rutinaSalida(id, 2 * dOut + estancia, o);
  viajes[id] = { id, tipo, dest, t0: r.t0, inicio: r.inicio, fin: r.fin, dOut, estancia, D: 2 * dOut + estancia, ida: o.ida, vuelta: o.vuelta, pasantes: [] };
}

const ETIQUETA_REUNION = { traspaso: 'Traspaso', encargo: 'Encargo', lider: 'Nuevo líder', arranque: 'Arranque', revision: 'Revisión' };
function encolarReunion(m) {
  if (paused) return false;
  const clave = m.tipo + '|' + m.participantes.join(',') + '|' + m.tema;
  if ([reunionActual, ...colaReuniones].some(x => x && x.clave === clave) || colaReuniones.length >= 6) return false;
  colaReuniones.push({ intercambios: [], ...m, clave, desde: performance.now() });
  return true;
}

// Asientos: el primero arriba y el segundo enfrente, para que la carpeta cruce la mesa.
function iniciarReunion(m, quienes) {
  const sillas = {}, pas = [];
  quienes.forEach((id, k) => { sillas[id] = k; });
  if (m.pasantes) {
    const jefe = quienes[0];
    (agente(jefe)?.pasantes_lista || []).slice(0, 4).forEach((p, j) => {
      const dest = { sala: 'reuniones', silla: quienes.length + j };
      sillas['p:' + j] = dest.silla;
      pas.push({ p, dest, retraso: 450 * (j + 1), dOut: idaMs(jefe, dest) });
    });
    m.intercambios = pas.map((_, j) => ({ de: jefe, para: 'p:' + j }));
  }
  m.intercambios = m.intercambios.filter(x => x.de in sillas).map(x => ({ ...x, para: x.para in sillas ? x.para : null }));
  const dOut = Object.fromEntries(quienes.map(id => [id, idaMs(id, { sala: 'reuniones', silla: sillas[id] })]));
  const llegada = Math.max(...Object.values(dOut), ...pas.map(x => x.retraso + x.dOut));
  const sit = 2400 + 1800 * Math.max(1, m.intercambios.length) + 900;
  let fin = 0, tSentado = 0;
  for (const id of quienes) {
    const da = m.intercambios.some(x => x.de === id), recibe = m.intercambios.some(x => x.para === id);
    const o = { ida: da ? 'carpeta' : null, vuelta: recibe ? 'carpeta' : null, aviso: 'a la sala' };
    const estancia = llegada + sit - dOut[id];
    const propios = id === quienes[0] ? pas : [];
    const vuelta = Math.max(dOut[id], ...propios.map(x => x.dOut));
    const D = dOut[id] + estancia + vuelta;
    const r = rutinaSalida(id, D, o);
    viajes[id] = { id, tipo: 'reunion', dest: { sala: 'reuniones', silla: sillas[id] }, t0: r.t0, inicio: r.inicio, fin: r.fin, dOut: dOut[id], estancia, D, ida: o.ida, vuelta: o.vuelta, pasantes: propios, reunion: m };
    fin = Math.max(fin, r.fin); tSentado = r.t0 + llegada;
  }
  Object.assign(m, { quienes, sillas, tSentado, sit, fin, inicio: performance.now() });
  reunionActual = m;
}

function gestionarViajes(now) {
  for (const id of Object.keys(viajes)) if (now >= viajes[id].fin) delete viajes[id];
  if (reunionActual && now >= reunionActual.fin) { ultimaReunion = reunionActual; reunionActual = null; }
  if (paused || !data) return;
  const m = colaReuniones[0];
  if (!reunionActual && m) {
    const presentes = m.participantes.filter(id => enMesa(agente(id)));
    const listos = presentes.filter(id => !ocupado(id, now));
    if (!presentes.length) colaReuniones.shift();
    else if (listos.length === presentes.length || now - m.desde > 45000) {
      colaReuniones.shift();
      if (listos.length) iniciarReunion(m, listos);
    }
  }
  const reservados = colaReuniones[0]?.participantes || [];
  for (let k = 0; k < pedidos.length; k++) {
    const p = pedidos[k];
    if (!enMesa(agente(p.id)) || now - p.desde > 120000) { pedidos.splice(k--, 1); continue; }
    if (!ocupado(p.id, now) && !reservados.includes(p.id)) { pedidos.splice(k--, 1); iniciarSolo(p.id, p.tipo); }
  }
}

// Dónde está el viajero en la planta: ida, estancia (k = ms en destino) o vuelta.
function posViaje(v, now, L, dest = v.dest, retraso = 0, dOut = v.dOut) {
  const e = now - v.t0 - retraso;
  if (paused || e < 0) return null;
  const pts = rutaViaje(v.id, dest, L), salida = v.dOut + v.estancia - retraso;
  if (e < dOut) return { ...enRuta(pts, e / dOut), andando: true, fase: 'ida' };
  if (e < salida) { const p = pts[pts.length - 1]; return { x: p[0], y: p[1], dir: 1, andando: false, fase: 'estancia', k: e - dOut }; }
  const eb = e - salida;
  if (eb < dOut) { const p = enRuta(pts, 1 - eb / dOut); return { ...p, dir: -p.dir, andando: true, fase: 'vuelta' }; }
  return null;
}

// Fuera del despacho: devuelve el cartel para la mesa (o null).
function fueraDe(id, now = performance.now()) {
  const v = viajes[id];
  if (!v || paused) return null;
  const e = now - v.t0;
  return e >= 0 && e < v.D ? FUERA[v.dest.sala] : null;
}
const pasantesFuera = (id, now = performance.now()) => !paused && !!viajes[id]?.pasantes.length && now >= viajes[id].inicio && now < viajes[id].fin;

// Transiciones: se deducen comparando el estado nuevo con el anterior.
const vistos = { mensajes: new Set(), noticias: new Set(), pasantes: new Set() };
let primeraLectura = true;
function detectarTransiciones(prev, next) {
  const hechos = a => (a?.pasos_plan || []).filter(p => p.completado).length;
  for (const a of next.agentes || []) {
    const p = prev?.agentes?.find(x => x.id === a.id);
    if (p && hechos(a) > hechos(p)) { programar(a.id, 'tachar'); pedirViaje(a.id, 'archivo'); }
    const lista = (a.pasantes_lista || []).map(x => a.id + ':' + (x.id || x.tarea));
    const nuevos = lista.filter(k => !vistos.pasantes.has(k));
    lista.forEach(k => vistos.pasantes.add(k));
    if (!primeraLectura && nuevos.length && lista.length >= 2)
      encolarReunion({ tipo: 'arranque', participantes: [a.id], pasantes: true, tema: `${lista.length} pasantes de ${a.nombre || a.id}` });
  }
  for (const h of next.hilos || []) {
    const ph = prev?.hilos?.find(x => x.id === h.id);
    const viejo = norm(ph?.lider), nuevo = norm(h.lider);
    if (ph && ids.includes(viejo) && ids.includes(nuevo) && viejo !== nuevo) {
      const resto = (h.participantes || []).map(norm).filter(id => ids.includes(id) && id !== viejo && id !== nuevo);
      encolarReunion({ tipo: 'lider', participantes: [viejo, nuevo, ...new Set(resto)], corona: { de: viejo, para: nuevo }, tema: h.titulo || h.id });
    }
    for (const m of h.mensajes || []) {
      const k = h.id + '#' + (m.n ?? m.fecha);
      if (vistos.mensajes.has(k)) continue;
      vistos.mensajes.add(k);
      const de = norm(m.autor), para = norm(m.para);
      if (primeraLectura || !ids.includes(de) || !ids.includes(para) || de === para) continue;
      const tipo = m.tipo === 'encargo' && norm(h.lider) === de ? 'encargo' : m.traspaso ? 'traspaso' : null;
      if (tipo) encolarReunion({ tipo, participantes: [de, para], intercambios: [{ de, para }], tema: h.titulo || h.id });
    }
  }
  for (const n of next.noticias || []) {
    const k = n.hora + '|' + n.texto;
    if (vistos.noticias.has(k)) continue;
    vistos.noticias.add(k);
    const t = /^(\S+) terminó tarea/i.exec(n.texto || '');
    if (!primeraLectura && t) pedirViaje(norm(t[1]), 'archivo');
  }
  primeraLectura = false;
}

// ?demo=reunion|archivo|cafe: fuerza lo necesario en los datos para ver la animación ya.
const demoModo = hashParams().get('demo');
function ajustarDemo(next) {
  if (!['reunion', 'arranque', 'archivo', 'cafe', 'traspaso'].includes(demoModo)) return;
  for (const a of next.agentes || []) {
    if (demoModo === 'cafe' && a.id === 'claude') a.estado = 'esperando';
    else if (!enMesa(a) && (['reunion', 'traspaso'].includes(demoModo) || a.id === 'claude')) a.estado = 'esperando';
    if (['reunion', 'arranque'].includes(demoModo) && a.id === 'claude' && (a.pasantes_lista || []).length < 2)
      a.pasantes_lista = [...(a.pasantes_lista || []), { id: 'demo-1', modelo: 'claude-haiku-4-5', tarea: 'demostración' }, { id: 'demo-2', modelo: 'claude-sonnet-4-5', tarea: 'demostración' }].slice(0, 2);
  }
}
function lanzarDemo() {
  const lejos = performance.now() + 120000;
  ids.forEach(id => { delete actores[id]; proximo.super[id] = proximo.ocio[id] = lejos; });
  currentVisitor = null; nextVisitorTime = Infinity;
  if (demoModo === 'arranque') encolarReunion({ tipo: 'arranque', participantes: ['claude'], pasantes: true, tema: 'Arranque con los pasantes' });
  else if (demoModo === 'reunion' || demoModo === 'traspaso') {
    encolarReunion({ tipo: 'traspaso', participantes: ['claude', 'codex'], intercambios: [{ de: 'claude', para: 'codex' }], tema: activeThread()?.titulo || 'Traspaso' });
    encolarReunion({ tipo: 'encargo', participantes: ['claude', 'agy'], intercambios: [{ de: 'claude', para: 'agy' }], tema: 'Encargo nuevo para agy' });
    encolarReunion({ tipo: 'arranque', participantes: ['claude'], pasantes: true, tema: 'Arranque con los pasantes' });
  } else if (demoModo === 'archivo' || demoModo === 'cafe') pedirViaje('claude', demoModo);
}

// Objetos que el agente lleva en la mano (coordenadas de la escena).
function dibujarProp(x, y, tipo, color, s = 0.6) {
  if (!tipo) return;
  ctx.save();
  ctx.translate(x, y); ctx.scale(s, s);
  if (tipo === 'pinza') { R(14, -22, 14, 18, '#8a5a32'); R(16, -19, 10, 14, '#f8fafc'); R(18, -24, 6, 3, '#94a3b8'); R(18, -15, 6, 1, '#94a3b8'); R(18, -11, 5, 1, '#94a3b8'); }
  else if (tipo === 'carpeta') { R(14, -20, 16, 13, color || '#f59e0b'); R(14, -23, 7, 4, color || '#f59e0b'); R(17, -15, 9, 2, '#ffffff'); }
  else if (tipo === 'rotulador') { R(18, -44, 3, 22, '#e2e8f0'); R(18, -48, 3, 5, '#ef4444'); }
  else if (tipo === 'cafe') { R(16, -12, 8, 8, '#ece3cf'); R(24, -10, 3, 4, '#ece3cf'); R(17, -11, 6, 2, '#6f4e37'); if (!paused) R(19, -18 - Math.floor(performance.now() / 300) % 3, 2, 4, 'rgba(220,230,235,0.6)'); }
  ctx.restore();
}

// Dibuja a un agente de pie o andando (pose) con su objeto y su bocadillo.
function dibujarPose(agentObj, ps, t, escala, caja) {
  ctx.save();
  ctx.translate(ps.x, ps.y);
  ctx.scale(ps.dir < 0 ? -escala : escala, escala);
  V1.person(0, 0, { ...agentObj, estado: 'andando', energia: { semanal: 100 } }, t, ps.andando);
  ctx.restore();
  dibujarProp(ps.x, ps.y, ps.prop, ps.color, escala);
  if (ps.texto && caja) bocadillo(ps.texto, ps.x, ps.y - 62 * escala, caja, escala >= 0.9 ? 8 : escala <= 0.55 ? 7 : 4.6);
}

// =========================================================================
// VISITAS SORPRESA DE MODELOS CONOCIDOS (ITEM 15)
// =========================================================================
function updateVisitors(t) {
  if (paused) return;

  if (!currentVisitor && t > nextVisitorTime) {
    // Solo visita a un agente que está «esperando», y siempre alguien de su familia.
    const candidatos = ids.filter(id => agente(id)?.estado === 'esperando' && !ocupado(id, performance.now()));
    if (candidatos.length > 0) {
      const targetAgent = candidatos[Math.floor(Math.random() * candidatos.length)];
      const host = data.agentes.find(a => a.id === targetAgent);
      const pool = (realModelCatalog[targetAgent] || []).filter(m => !String(host?.modelo || '').toLowerCase().includes(m.type));
      const pick = pool[Math.floor(Math.random() * pool.length)];
      if (pick) currentVisitor = { ...pick, target: targetAgent, startTime: t, duration: 8500 };
    }
    // Siguiente visita cada 6 a 12 minutos (§4)
    nextVisitorTime = t + (360 + Math.random() * 360) * 1000;
  }

  if (currentVisitor && t - currentVisitor.startTime > currentVisitor.duration) currentVisitor = null;
}

// Progreso de la visita: entra (0→1), se queda y sale (1→0).
function visitaProgreso(v, t) {
  const e = t - v.startTime, d = v.duration;
  if (e < 2000) return { k: e / 2000, andando: true, dir: 1, habla: false };
  if (e > d - 2000) return { k: Math.max(0, 1 - (e - (d - 2000)) / 2000), andando: true, dir: -1, habla: false };
  return { k: 1, andando: false, dir: 1, habla: e >= 1800 && e <= d - 1800 };
}
const visitaObj = v => ({ id: v.target, nombre: v.name, estado: 'andando', personaje: { ropa: v.ropa, color: v.color, accesorio: v.accesorio, velocidad: 1.2 }, energia: { semanal: 100 } });

// En el despacho (640 × 360): entra por la izquierda y habla dentro de la sala.
function drawVisitorInOffice(v, t) {
  if (!v) return;
  const p = visitaProgreso(v, t);
  const x = -40 + (150 - -40) * p.k, y = 342;
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(p.dir < 0 ? -0.6 : 0.6, 0.6);
  V1.person(0, 0, visitaObj(v), t, p.andando, false);
  ctx.restore();
  if (p.habla) bocadillo(`${v.name}: «${v.quote}»`, x, y - 38, [4, 222, DESK.x - 6], 5, '#f8fafc', '#1e293b', 150);
}

// =========================================================================
// DIBUJO PIXEL ART: MASCOTAS Y BOCADILLOS PEGADOS (ITEM 3 Y 11)
// =========================================================================
function drawPetWithBubble(x, y, id, t, conBocadillo = true) {
  ctx.save();
  ctx.translate(x, y);
  const b = Math.round(Math.sin(t / 600));

  if (id === 'claude') {
    R(-12, -14 + b, 23, 17, '#caa285');
    R(-13, -24 + b, 19, 15, '#d8b496');
    R(-13, -29 + b, 5, 8, '#d8b496');
    R(1, -29 + b, 5, 8, '#d8b496');
    R(-9, -20 + b, 3, 3, '#365452');
    R(0, -20 + b, 3, 3, '#365452');
    R(10, -12, 13, 4, '#caa285');
    R(20, -20 + b, 4, 10, '#caa285');
  } else if (id === 'codex') {
    R(-12, -24 + b, 24, 27, '#9b8573');
    R(-10, -28 + b, 6, 6, '#a89580');
    R(5, -28 + b, 6, 6, '#a89580');
    R(-10, -21 + b, 9, 11, '#ddd0a7');
    R(2, -21 + b, 9, 11, '#ddd0a7');
    R(-7, -18 + b, 4, 4, '#223c43');
    R(4, -18 + b, 4, 4, '#223c43');
    R(-1, -10 + b, 4, 5, '#e3b877');
  } else if (id === 'agy') {
    R(-16, -13 + b, 28, 16, '#b99471');
    R(-14, -26 + b, 23, 19, '#d1ad86');
    R(-18, -26 + b, 6, 19, '#796454');
    R(4, -26 + b, 6, 19, '#796454');
    R(-10, -22 + b, 4, 4, '#1b2c34');
    R(0, -22 + b, 4, 4, '#1b2c34');
    R(-5, -16 + b, 6, 4, '#e17777');
    R(11, -23 + Math.round(Math.sin(t / 120) * 3), 4, 12, '#997453');
  }
  hit('mascota:' + id, 'Mascota del despacho (clic para hablar)', -20, -32, 46, 38, () => openInteractiveModal('mascota', { agentId: id }));
  ctx.restore();

  // Bocadillo medido: nunca pasa del borde izquierdo de la mesa (portátil incluido).
  if (conBocadillo) bocadillo(mascotPhrases[id] || '…', x, y - 34 + b, [4, 222, DESK.x - 6], 5.4, '#e2ecf5', '#182433', 130);
}


// =========================================================================
// DIBUJO PIXEL ART: VENTANAS SUPERIORES PERSONALIZADAS (ITEM 12)
// =========================================================================
function drawPersonalizedWindow(x, y, w, h, agentId, t) {
  ctx.save();
  // Marco de la ventana
  R(x, y, w, h, '#172230');
  R(x + 2, y + 2, w - 4, h - 4, '#090e15');

  if (agentId === 'claude') {
    // Vista de montaña al atardecer (sunset gradient + mountain silhouettes)
    const grad = ctx.createLinearGradient(x, y, x, y + h);
    grad.addColorStop(0, '#582c35');
    grad.addColorStop(0.5, '#ab563b');
    grad.addColorStop(1, '#e3945a');
    ctx.fillStyle = grad;
    ctx.fillRect(x + 2, y + 2, w - 4, h - 4);

    // Sol poniente
    R(x + w * 0.45, y + 10, 16, 16, '#fae092');

    // Cordillera de montañas (capas superpuestas)
    for (let i = 0; i < 4; i++) {
      const mx = x + 10 + i * (w / 3.8);
      const my = y + h - 22;
      ctx.fillStyle = i % 2 ? '#2b1b22' : '#3d252f';
      ctx.beginPath();
      ctx.moveTo(mx, y + h);
      ctx.lineTo(mx + 30, my);
      ctx.lineTo(mx + 60, y + h);
      ctx.fill();
    }
  } else if (agentId === 'codex') {
    // Ciudad iluminada de noche (deep blue + skyscraper grid + blinking red beacon)
    const grad = ctx.createLinearGradient(x, y, x, y + h);
    grad.addColorStop(0, '#0a101d');
    grad.addColorStop(1, '#1b283d');
    ctx.fillStyle = grad;
    ctx.fillRect(x + 2, y + 2, w - 4, h - 4);

    // Rascacielos con ventanitas pixel
    for (let bi = 0; bi < 10; bi++) {
      const bx = x + 6 + bi * ((w - 12) / 10);
      const bh = 18 + (bi * 13) % (h - 22);
      const by = y + h - bh;
      R(bx, by, (w - 12) / 10 - 2, bh, '#121e2d');
      for (let wy = by + 3; wy < y + h - 4; wy += 5) {
        if ((bi + wy) % 2 === 0) {
          R(bx + 2, wy, 2, 2, (bi + wy) % 3 === 0 ? '#fae896' : '#6494a8');
        }
      }
    }
    // Baliza roja parpadeante
    const blink = Math.floor(t / 400) % 2 === 0;
    R(x + w * 0.7, y + 8, 2, 2, blink ? '#ef4444' : '#7f1d1d');
  } else if (agentId === 'agy') {
    // Cielo despejado con globos aerostáticos flotando
    const grad = ctx.createLinearGradient(x, y, x, y + h);
    grad.addColorStop(0, '#38bdf8');
    grad.addColorStop(1, '#bae6fd');
    ctx.fillStyle = grad;
    ctx.fillRect(x + 2, y + 2, w - 4, h - 4);

    // Nubes pixel
    R(x + 20, y + 14, 28, 6, 'rgba(255,255,255,0.7)');
    R(x + 26, y + 10, 16, 4, 'rgba(255,255,255,0.7)');
    R(x + w - 40, y + 20, 24, 5, 'rgba(255,255,255,0.6)');

    // Globos aerostáticos con bobbing
    const balloons = [
      { x: x + 45, y: y + 16, col: '#ef4444', alt: '#fbbf24' },
      { x: x + w * 0.65, y: y + 10, col: '#3b82f6', alt: '#10b981' }
    ];
    balloons.forEach((bl, idx) => {
      const by = bl.y + Math.sin((t + idx * 800) / 700) * 3;
      R(bl.x, by, 8, 9, bl.col);
      R(bl.x + 2, by, 4, 9, bl.alt);
      R(bl.x + 2, by + 11, 4, 3, '#78350f'); // cesta
      R(bl.x + 3, by + 9, 2, 2, '#4b5563'); // cuerdas
    });
  }

  // Cuarterones de la ventana
  R(x + w / 2, y + 2, 2, h - 4, '#172230');
  R(x + 2, y + h / 2, w - 4, 2, '#172230');

  ctx.restore();
}

// =========================================================================
// DIBUJO PIXEL ART: SEGUNDO MUEBLE Y ESPACIO LIBRE (ITEM 11)
// =========================================================================
function drawSecondFurniture(x, y, agentId, t, stats) {
  ctx.save();
  ctx.translate(x, y);

  if (agentId === 'claude') {
    // Butaca de lectura lujosa con libros y lamparilla
    // Alfombra redonda bajo la butaca
    R(-26, 8, 52, 10, '#5a2d24');
    // Butaca orejera aterciopelada
    R(-16, -26, 32, 34, '#873d2d');
    R(-14, -24, 28, 30, '#a24937');
    R(-18, -12, 6, 20, '#6d3023'); // apoyabrazos izq
    R(12, -12, 6, 20, '#6d3023');  // apoyabrazos der
    R(-10, -6, 20, 10, '#c35b45');  // cojín
    // Mesa auxiliar con libros apilados
    R(24, -4, 18, 14, '#4a2c1b');
    R(26, -10, 14, 3, '#10b981'); // libro verde
    R(27, -13, 12, 3, '#d97706'); // libro ámbar
    R(25, -16, 15, 3, '#2563eb'); // libro azul
    // Lámpara de pie de latón
    R(-24, -36, 2, 44, '#d4af37');
    R(-30, -44, 14, 8, '#fef08a');
  } else if (agentId === 'codex') {
    // Rack de servidores con LEDs que parpadean según actividad real
    R(-16, -50, 32, 58, '#0f1722');
    R(-14, -48, 28, 54, '#172535');
    // Servidores en unidades de rack
    for (let u = 0; u < 5; u++) {
      const uy = -45 + u * 10;
      R(-12, uy, 24, 8, '#213346');
      R(-10, uy + 2, 8, 2, '#475569'); // ventilación
      // LEDs parpadeantes según actividad
      const ledTick = Math.floor(t / (120 + u * 40)) % 2 === 0;
      R(4, uy + 3, 2, 2, ledTick ? '#22c55e' : '#14532d');
      R(8, uy + 3, 2, 2, (t + u * 100) % 300 < 150 ? '#38bdf8' : '#0369a1');
    }
    // Ventilador de extracción superior
    R(-4, -53, 8, 3, '#475569');
  } else if (agentId === 'agy') {
    // Cinta de correr moderna o pizarra de ideas
    // Pizarra de ideas con post-its y esquemas
    R(-22, -42, 44, 32, '#d4be98');
    R(-20, -40, 40, 28, '#1e293b');
    // Post-its de colores Google
    R(-16, -36, 8, 8, '#fbbf24'); // amarillo
    R(-6, -36, 8, 8, '#38bdf8');  // azul
    R(4, -36, 8, 8, '#f87171');   // rojo
    R(-10, -24, 18, 2, '#94a3b8'); // flecha de flujo
    R(2, -26, 6, 6, '#34d399');   // verde
    // Patas de soporte
    R(-18, -10, 4, 18, '#475569');
    R(14, -10, 4, 18, '#475569');
  }


  ctx.restore();
}


// Archivador del despacho: cuatro cajones con etiqueta; abre el archivo de hilos.
function drawArchivadorDespacho(x, y, agentId) {
  const w = 30, h = 80;
  R(x - 1, y + h, w + 2, 3, 'rgba(0,0,0,0.35)');
  R(x, y, w, h, '#3b4757'); R(x + 2, y + 2, w - 4, h - 4, '#2b3542');
  R(x, y, w, 3, '#566476');
  for (let d = 0; d < 4; d++) {
    const dy = y + 5 + d * 18.5;
    R(x + 3, dy, w - 6, 16, '#475569'); R(x + 3, dy, w - 6, 2, '#5d6e84');
    R(x + 8, dy + 4, w - 16, 5, '#e2e8f0');
    R(x + 10, dy + 11, w - 20, 2, '#cbd5e1');
  }
  R(x + 4, y - 4, 9, 4, '#f59e0b'); R(x + 15, y - 3, 9, 3, '#3b82f6');
  hit('archivador:' + agentId, 'Archivador (hilos concluidos)', x - 2, y - 5, w + 4, h + 8, () => openInteractiveModal('archivador', { agentId }));
}


// =========================================================================
// DIBUJO PIXEL ART: PÓSTER DINÁMICO SEGÚN DATOS (ITEM 13)
// =========================================================================
function drawDynamicPoster(x, y, w, h, poster) {
  if (!poster) return;
  ctx.save();
  // Marco de madera / dorado
  R(x - 2, y - 2, w + 4, h + 4, '#503522');
  R(x, y, w, h, '#0f1724');
  R(x + 2, y + 2, w - 4, h - 4, '#162233');

  // Franja decorativa de color del agente
  R(x + 4, y + 4, w - 8, 3, poster.color || '#f1cf85');

  // Icono del póster
  const icx = x + w / 2, icy = y + 20;
  if (poster.icono === 'ajedrez') {
    // Corona / rey de ajedrez
    R(icx - 6, icy - 6, 12, 12, '#f1cf85');
    R(icx - 4, icy - 8, 8, 3, '#f1cf85');
    R(icx - 1, icy - 10, 2, 3, '#fff');
  } else if (poster.icono === 'terminal') {
    // Pantalla de terminal verde
    R(icx - 8, icy - 6, 16, 12, '#22c55e');
    R(icx - 6, icy - 4, 12, 8, '#052e16');
    dText('>', icx - 2, icy, 6, '#22c55e', 'center');
  } else {
    // Cohete
    R(icx - 3, icy - 8, 6, 12, '#38bdf8');
    R(icx - 5, icy - 2, 2, 6, '#ef4444');
    R(icx + 3, icy - 2, 2, 6, '#ef4444');
    R(icx - 2, icy + 4, 4, 3, '#f59e0b');
  }

  // Lema dinámico en píxeles
  ctx.beginPath(); ctx.rect(x + 2, y + 2, w - 4, h - 4); ctx.clip();
  const ajustar = (s, max, bold) => {
    let size = max;
    ctx.font = `${bold ? 'bold ' : ''}${size}px Consolas, monospace`;
    while (size > 3 && ctx.measureText(s).width > w - 8) { size -= 0.2; ctx.font = `${bold ? 'bold ' : ''}${size}px Consolas, monospace`; }
    return size;
  };
  const lema = poster.lema || 'Trabajo en equipo', sub = poster.sublema || 'Mesa de agentes';
  dText(lema, icx, y + 36, ajustar(lema, 6.2, true), '#f8fafc', 'center', true);
  dText(sub, icx, y + 46, ajustar(sub, 4.6, false), '#94a3b8', 'center');

  ctx.restore();
}

// =========================================================================
// DIBUJO PIXEL ART: PIZARRA CON TACHADO NO INVASIVO Y MULTILÍNEA (ITEM 8)
// =========================================================================
function drawChalkboard(x, y, w, h, pasos, agentId) {
  ctx.save();
  R(x - 3, y - 3, w + 6, h + 6, '#5a3d28');
  R(x - 1, y - 1, w + 2, h + 2, '#7c5539');
  R(x, y, w, h, '#14251b');
  for (let ty = y + 14; ty < y + h - 10; ty += 20) R(x + 8, ty, w - 16, 1, 'rgba(255,255,255,0.025)');
  R(x - 4, y + h, w + 8, 4, '#442d1e');
  R(x + 12, y + h - 2, 7, 2, '#fff4cf');
  R(x + 23, y + h - 2, 7, 2, '#f87171');
  R(x + 34, y + h - 2, 7, 2, '#fbbf24');

  fitText(`✦ PLAN · ${(agentId || 'AGENTE').toUpperCase()}`, x + 10, y + 12, w - 20, 6.5, '#e2f0d9', 'left', true);
  R(x + 10, y + 18, w - 20, 1, '#375745');
  hit('pizarra:' + agentId, 'Pizarra del plan (árbol de pasos)', x - 3, y - 3, w + 6, h + 6, () => openInteractiveModal('pizarra', { agentId }));

  const listaPasos = asArray(pasos);
  if (listaPasos.length === 0) {
    const bx = x + 8, by = y + 26, bw = w - 16, bh = h - 36;
    R(bx, by, bw, bh, '#1a1816');
    R(bx + 2, by + 2, bw - 4, bh - 4, '#261b18');
    for (let ax = bx + 4; ax < bx + bw - 6; ax += 12) { R(ax, by + 2, 6, 3, '#f59e0b'); R(ax, by + bh - 5, 6, 3, '#f59e0b'); }
    fitText('⚠ SIN PLAN ACTIVO', bx + bw / 2, by + 22, bw - 10, 6.5, '#f59e0b', 'center', true);
    fitText('escribe un encargo o traspaso', bx + bw / 2, by + 37, bw - 10, 5.2, '#fef08a', 'center');
    fitText('para fijar rumbo.', bx + bw / 2, by + 49, bw - 10, 4.8, '#d6d3d1', 'center');
    ctx.restore();
    return;
  }

  // Pasos en varias líneas medidas; el tachado mide lo mismo que su texto.
  let curY = y + 28;
  const maxW = w - 36;
  for (const p of listaPasos.slice(0, 6)) {
    if (curY > y + h - 12) break;
    const isDone = !!p.completado;
    dText(isDone ? '[✓]' : '[ ]', x + 10, curY, 6.2, isDone ? '#4ade80' : '#fef08a', 'left', true);
    const lines = wrapLines(p.texto || '', maxW, 5.8, false, 2);
    lines.forEach((l, i) => {
      const ly = curY + i * 11;
      if (ly > y + h - 8) return;
      dText(l, x + 26, ly, 5.8, isDone ? '#9ca3af' : '#ffffff', 'left', false, maxW);
      if (isDone) {
        ctx.font = fuente(5.8, false);
        ctx.fillStyle = 'rgba(244, 63, 94, 0.45)';
        ctx.fillRect(x + 25, ly - 0.5, Math.min(maxW, ctx.measureText(l).width + 2), 1.2);
      }
    });
    curY += Math.max(16, lines.length * 11 + 5);
  }
  ctx.restore();
}

// Corcho: cada nota muestra el «hecho» del traspaso o, si no lo hay, el título del hilo.
function drawCorkboard(x, y, w, h, folders, agentId) {
  ctx.save();
  R(x - 3, y - 3, w + 6, h + 6, '#7c5332');
  R(x - 1, y - 1, w + 2, h + 2, '#99673e');
  R(x, y, w, h, '#b38253');
  for (let i = 0; i < 40; i++) R(x + (i * 29) % (w - 6) + 3, y + (i * 37) % (h - 6) + 3, 2, 2, i % 2 ? '#9c6f44' : '#c69564');
  dText('TRASPASOS', x + w / 2, y + 10, 6, '#fef08a', 'center', true, w - 8);
  const folderList = asArray(folders);
  hit('corcho:' + agentId, 'Corcho de traspasos', x - 3, y - 3, w + 6, h + 6, () => openCorkModal(folderList[0]));

  const notes = folderList.slice(0, 4);
  const noteH = (h - 22) / Math.max(3, notes.length);
  notes.forEach((f, idx) => {
    const ny = y + 18 + idx * noteH, nw = w - 16, nx = x + 8, nh = noteH - 4;
    const isIncidencia = f.tipo === 'incidencia';
    R(nx, ny, nw, nh, isIncidencia ? '#ef4444' : '#e2b340');
    R(nx + 1, ny + 1, nw - 2, nh - 2, isIncidencia ? '#fecaca' : (idx % 2 ? '#fef08a' : '#fed7aa'));
    const pinCol = isIncidencia ? '#dc2626' : (idx === 0 ? '#ef4444' : idx === 1 ? '#3b82f6' : '#10b981');
    R(nx + nw / 2 - 2, ny - 2, 4, 4, pinCol);
    fitText(isIncidencia ? '⚠ INCIDENCIA' : `DE: ${String(f.de || '').toUpperCase()}`, nx + 4, ny + 5.5, nw - 30, 4.6, isIncidencia ? '#991b1b' : '#334155', 'left', true);
    dText('⤢ ver', nx + nw - 3, ny + 5.5, 4, '#64748b', 'right', false, 22);
    const texto = String(f.resumen || f.titulo || f.hilo || '').replace(/\s+/g, ' ');
    const filas = nh >= 22 ? 2 : 1;
    wrapLines(texto, nw - 8, 4.6, false, filas).forEach((l, i) => dText(l, nx + 4, ny + 12.5 + i * 6, 4.6, '#1e293b', 'left', false, nw - 8));
    hit('nota:' + agentId + ':' + idx, 'Traspaso de ' + (f.de || '—'), nx, ny, nw, nh, () => openCorkModal(f));
  });
  ctx.restore();
}


// =========================================================================
// DIBUJO PIXEL ART: MONITOR DE TELEMETRÍA (ITEM 1: 3 VISTAS ALTERNABLES)
// =========================================================================
function drawTelemetryMonitor(x, y, w, h, agent, t) {
  ctx.save();
  // Marco del monitor moderno
  R(x - 3, y - 3, w + 6, h + 6, '#182433');
  R(x, y, w, h, '#0a0f16');
  R(x + 2, y + 2, w - 4, h - 4, '#0f1724');

  const viewMode = agent.monitorView || 0;
  const calib = agent.calibracion || defaultCalibracion[agent.id] || defaultCalibracion.claude;
  const stats = agent.estadisticas || {};

  // Barra de título del monitor
  R(x + 2, y + 2, w - 4, 14, '#152436');

  if (viewMode === 0) {
    // VISTA 1: ENERGÍA Y TOKENS
    fitText('✦ MONITOR: ENERGÍA Y TOKENS', x + 8, y + 9, w - 70, 6.2, '#38bdf8', 'left', true);
    fitText(`[${agent.energia?.calidad || 'sin dato'}]`, x + w - 8, y + 9, 56, 5.5, '#6ee7b7', 'right');

    const ult = agent.ultima;
    const toolName = ult ? ult.herramienta : (agent.operacion_animada || 'esperando');
    const fileName = ult && ult.archivo ? leaf(ult.archivo) : 'sin archivo activo';
    R(x + 8, y + 18, w - 16, 12, '#131e2d');
    fitText(`ACTIVO: [${toolName}] ${fileName}`, x + 12, y + 24, w - 24, 4.8, '#fef08a');

    const q = agent.energia || {};
    fitText(`TOKENS HOY: ${number(stats.tokens_hoy || 0)}`, x + 10, y + 36, 110, 5.8, '#ffffff', 'left', true);
    const cincoTxt = agent.estado === 'descansando' && agent.vuelve ? '5 h agotada · vuelve ' + horaCorta(agent.vuelve) : '5 h: ' + (q.cinco_h == null ? '—' : number(q.cinco_h) + '%');
    fitText(`semana ${q.semanal == null ? '—' : number(q.semanal) + '%'} · ${cincoTxt}`, x + w - 10, y + 36, w - 130, 4.6, agent.estado === 'descansando' ? '#fca5a5' : '#a7f3d0', 'right');

    const barY = y + 43, barH = 13;
    const hourly = agent.tokens_por_hora || new Array(24).fill(0);
    const maxHourly = Math.max(1, ...hourly);
    const barW = (w - 24) / 24;
    for (let hi = 0; hi < 24; hi++) {
      const hPx = Math.max(1, ((hourly[hi] || 0) / maxHourly) * barH);
      R(x + 10 + hi * barW, barY + barH - hPx, Math.max(1, barW - 1), hPx, hi >= 18 ? '#38bdf8' : '#22c55e');
    }

    const statsY = y + 63;
    fitText(`✓ ${stats.hechas_hoy ?? stats.hoy ?? 0} hechas · ✗ ${stats.fallidas_hoy ?? 0} fallidas · ⏱ ${agent.tiempo_trabajado_hoy || '—'}`, x + 10, statsY, w - 20, 5.0, '#a7f3d0');

    // Últimos archivos: una sola columna con el nombre completo (medido).
    const filesY = statsY + 9;
    dText('ÚLTIMOS ARCHIVOS TOCADOS:', x + 10, filesY, 4.6, '#94a3b8', 'left', false, w - 20);
    asArray(agent.ultimos_archivos).slice(0, 6).forEach((rf, rIdx) => {
      const op = rf.operacion === 'escritura' ? '✍' : '👁';
      fitText(`${op} ${rf.hora ? hour(rf.hora) : '—'}  ${leaf(rf.valor || rf.archivo || 'archivo')}`, x + 10, filesY + 7 + rIdx * 6, w - 20, 4.4, '#e2e8f0');
    });

    R(x + 4, y + h - 10, w - 8, 9, '#101a26');
    fitText('▸ [Vista 1/3] Clic para la gráfica de 7 días', x + w / 2, y + h - 5.5, w - 16, 4.6, '#38bdf8', 'center');

  } else if (viewMode === 1) {
    // VISTA 2: GRÁFICA SEMANAL DE 7 DÍAS
    dText('✦ CONSUMO SEMANAL (7 DÍAS)', x + 8, y + 9, 6.2, '#38bdf8', 'left', true);
    dText(`Total: ${number(stats.tokens_7d || 13800000)} tok`, x + w - 8, y + 9, 5.2, '#fef08a', 'right');

    const dias = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
    const hist = agent.tokens_7d_hist || [1.8, 2.4, 1.2, 3.1, 2.8, 0.9, 1.6];
    const maxVal = Math.max(1, ...hist);
    const chartX = x + 14, chartY = y + 24, chartW = w - 28, chartH = h - 42;
    const colW = chartW / 7;

    // Línea de consumo promedio
    const avgVal = hist.reduce((a, b) => a + b, 0) / 7;
    const avgY = chartY + chartH - 12 - (avgVal / maxVal) * (chartH - 22);
    for (let lx = chartX; lx < chartX + chartW; lx += 6) {
      R(lx, avgY, 3, 1, '#f59e0b');
    }
    dText(`media: ${avgVal.toFixed(1)}M`, chartX + chartW - 2, avgY - 2, 4.2, '#f59e0b', 'right');

    dias.forEach((d, i) => {
      const val = hist[i] || 0;
      const bH = Math.max(3, (val / maxVal) * (chartH - 22));
      const bx = chartX + i * colW + 4;
      const by = chartY + chartH - 12 - bH;
      const isToday = i === 6;

      R(bx, by, colW - 8, bH, isToday ? '#10b981' : '#3b82f6');
      R(bx, by, colW - 8, 1, isToday ? '#6ee7b7' : '#93c5fd');
      dText(`${val.toFixed(1)}M`, bx + (colW - 8) / 2, by - 3, 4.2, '#c9d8e6', 'center');
      dText(d, bx + (colW - 8) / 2, chartY + chartH - 3, 4.5, isToday ? '#10b981' : '#94a3b8', 'center', isToday);
    });

    R(x + 4, y + h - 12, w - 8, 10, '#101a26');
    dText('▸ [Vista 2/3] Clic en monitor para Calibración WLS', x + w / 2, y + h - 5, 4.8, '#38bdf8', 'center');

  } else if (viewMode === 2) {
    // VISTA 3: CALIBRACIÓN CON c̄ ± Δc, n y R entre r_min y r_max
    dText('✦ CALIBRADOR DE TOKENS & CUOTA WLS', x + 8, y + 9, 6.2, '#fbbf24', 'left', true);
    dText(`[${(calib.calidad || 'OFICIAL').toUpperCase()}]`, x + w - 8, y + 9, 5.2, '#34d399', 'right');

    const c_medio = calib.coste_medio || 45200;
    const c_margen = calib.margen || 3200;
    const n_muestras = calib.n || 14;
    const r_est = calib.tareas_restantes || 18;
    const r_min = calib.r_min || 15;
    const r_max = calib.r_max || 22;

    // Fórmula en píxeles
    R(x + 10, y + 18, w - 20, 14, '#131e2b');
    dText(`FÓRMULA WLS: c̄ ± Δc = ${number(c_medio)} ± ${number(c_margen)} tok/tarea`, x + 14, y + 25, 4.8, '#fde047', 'left', true);

    // Muestras n y tareas restantes R
    R(x + 10, y + 36, (w - 24) / 2, 22, '#142232');
    dText('MUESTRAS REGISTRADAS', x + 14, y + 43, 4.4, '#94a3b8');
    dText(`n = ${n_muestras} tareas`, x + 14, y + 52, 5.8, '#38bdf8', 'left', true);

    R(x + 14 + (w - 24) / 2, y + 36, (w - 24) / 2, 22, '#142232');
    dText('TAREAS RESTANTES (R)', x + 18 + (w - 24) / 2, y + 43, 4.4, '#94a3b8');
    dText(`R = ${r_est} [${r_min} .. ${r_max}]`, x + 18 + (w - 24) / 2, y + 52, 5.8, '#34d399', 'left', true);

    // Barra de rango visual de confianza de R
    const barY = y + 66;
    dText(`Intervalo de confianza: [r_min: ${r_min}] ◄── R: ${r_est} ──► [r_max: ${r_max}]`, x + 12, barY, 4.5, '#cbd5e1');
    R(x + 10, barY + 4, w - 20, 9, '#101c2a');
    R(x + 24, barY + 6, w - 48, 5, '#1e384d');
    R(x + 36, barY + 6, w - 72, 5, '#0891b2');

    const rPos = x + 36 + ((r_est - r_min) / Math.max(1, (r_max - r_min))) * (w - 72);
    R(rPos - 2, barY + 4, 4, 9, '#fef08a');
    R(rPos - 1, barY + 5, 2, 7, '#ffffff');

    dText('Ajuste continuo WLS ponderado tras cada traspaso.', x + 12, barY + 20, 4.4, '#64748b');

    R(x + 4, y + h - 12, w - 8, 10, '#101a26');
    dText('▸ [Vista 3/3] Clic en monitor para volver a Energía & Tokens', x + w / 2, y + h - 5, 4.8, '#38bdf8', 'center');
  }

  ctx.restore();
}

const etiquetaEstado = e => ({ escribiendo: 'escribiendo', leyendo: 'leyendo', compilando: 'compilando', probando: 'probando', pensando: 'pensando', esperando: 'esperando', descansando: 'descansando', apagado: 'apagado' }[e] || e || '');

function engranaje(x, y, ang, col = '#94a3b8') {
  R(x - 2, y - 2, 4, 4, col);
  for (let i = 0; i < 6; i++) {
    const a = ang + i * Math.PI / 3;
    R(x + Math.cos(a) * 3.6 - 1, y + Math.sin(a) * 3.6 - 1, 2, 2, col);
  }
  R(x - 0.5, y - 0.5, 1, 1, '#0b1622');
}

// Líneas de código genéricas (pixel art, sin contenido real) que se desplazan.
function lineasCodigo(ix, ay, iw, ah, t, vel, paso = 3.4) {
  const pos = paused ? 0 : t / vel, off = Math.floor(pos), frac = pos - off;
  const colores = ['#93c5fd', '#a7f3d0', '#fcd34d', '#c4b5fd', '#f9a8d4'];
  for (let n = 0; n <= Math.ceil(ah / paso); n++) {
    const k = off + n, ind = ((k * 7) % 4) * 3, len = 6 + ((k * 13) % Math.max(8, iw - 10 - ind));
    R(ix + ind, ay + (n - frac) * paso, len, 1.4, colores[k % colores.length]);
  }
}

// Pantalla grande de la mesa: herramienta, archivo, actividad y el hilo en que trabaja.
function drawDeskMonitor(x, y, w, h, agent, t, on) {
  R(x + w / 2 - 4, y + h, 8, 6, '#263d49'); R(x + w / 2 - 14, y + h + 5, 28, 3, '#2a414e');
  R(x, y, w, h, '#182735'); R(x + 2, y + 2, w - 4, h - 4, on ? '#0b1622' : '#0a0f16');
  const ix = x + 5, iw = w - 10;
  if (!on) {
    const msg = agent.estado === 'descansando' && agent.vuelve ? 'vuelve a las ' + horaCorta(agent.vuelve) : agent.estado === 'apagado' ? 'pantalla apagada' : (fueraDe(agent.id) || 'en reunión').toLowerCase();
    fitText(msg, x + w / 2, y + h / 2, iw, 4.6, '#475569', 'center');
    return;
  }
  const u = agent.ultima || {}, est = agent.estado;
  R(x + 2, y + 2, w - 4, 9, '#152436');
  fitText(u.herramienta || 'sin herramienta', ix, y + 6.5, iw * 0.56, 4.6, '#38bdf8', 'left', true);
  fitText(etiquetaEstado(est), x + w - 5, y + 6.5, iw * 0.4, 4, '#94a3b8', 'right');
  fitText(u.archivo ? leaf(u.archivo) : 'sin archivo abierto', ix, y + 15.5, iw, 4.6, '#fef08a', 'left', true);
  const ay = y + 21, ah = h - 31;
  ctx.save(); ctx.beginPath(); ctx.rect(ix, ay, iw, ah); ctx.clip();
  if (est === 'compilando' || est === 'probando') {
    const k = paused ? 0.6 : ((t / 45) % 100) / 100;
    engranaje(ix + 5, ay + 5, paused ? 0 : t / 260); engranaje(ix + 13, ay + 8, paused ? 0 : -t / 260 + 0.5, '#64748b');
    fitText(est === 'probando' ? 'pruebas…' : 'compilando…', ix + 20, ay + 6, iw - 20, 4.2, '#cbd5e1');
    R(ix, ay + ah - 5, iw, 4, '#1e293b'); R(ix, ay + ah - 5, iw * k, 4, est === 'probando' ? '#a3e635' : '#38bdf8');
  } else if (est === 'leyendo') {
    lineasCodigo(ix, ay, iw, ah, t, 700);
    R(ix, ay + ((paused ? 0 : t / 60) % ah), iw, 2.5, 'rgba(254,240,138,0.25)');
  } else {
    lineasCodigo(ix, ay, iw, ah, t, est === 'escribiendo' ? 110 : 1800);
    if (est === 'escribiendo' && Math.floor(t / 400) % 2) R(ix + 2, ay + ah - 3, 3, 1.6, '#f8fafc');
  }
  ctx.restore();
  fitText('hilo: ' + (agent.hilo_actual || 'sin hilo'), ix, y + h - 5.5, iw, 4, '#a7f3d0');
}

// Cartel sobre la mesa cuando el agente no está («Vuelvo pronto», «En reunión»…).
function cartelMesa(cx, y, texto, w = 54, size = 5, alarma = false) {
  const h = size + 8;
  R(cx - w / 2 + 6, y + h - 1, 2, 5, '#5a3d28'); R(cx + w / 2 - 8, y + h - 1, 2, 5, '#5a3d28');
  R(cx - w / 2 - 1, y - 1, w + 2, h + 2, alarma ? '#7f1d1d' : '#78350f');
  R(cx - w / 2, y, w, h, alarma ? '#fecaca' : '#fef3c7');
  fitText(texto, cx, y + h / 2 + 0.3, w - 6, size, alarma ? '#7f1d1d' : '#7c2d12', 'center', true, size * 0.75);
}

// Pasantes: mesita auxiliar con su personaje (ropa de su modelo), monitor y tarea legible.
function drawPasantesDespacho(agent, t, fuera = false) {
  const lista = asArray(agent.pasantes_lista).slice(0, 4);
  lista.forEach((p, n) => {
    const [x0, y0] = celdaPasante(n), cw = 76;
    const lines = wrapLines(`${modeloCorto(p.modelo)} · ${p.tarea || 'subagente'}`, cw - 6, 4.3, false, 2);
    R(x0, y0, cw, lines.length * 5.6 + 3, 'rgba(15,23,42,0.88)');
    lines.forEach((l, i) => dText(l, x0 + 3, y0 + 4.3 + i * 5.6, 4.3, i === 0 ? '#fef08a' : '#e2e8f0', 'left', false, cw - 6));
    const estado = p.accion || (/read|grep|glob|view|search/i.test(p.herramienta || '') ? 'leyendo' : 'escribiendo');
    if (!fuera) {
      ctx.save();
      ctx.translate(x0 + 28, y0 + 46); ctx.scale(0.36, 0.36);
      V1.person(0, 0, { id: agent.id, personaje: personajeDe(p.modelo, agent.id), estado, energia: { semanal: 100 } }, paused ? 0 : t + n * 170);
      ctx.restore();
    }
    R(x0 + 44, y0 + 27, 22, 15, '#182735'); R(x0 + 45, y0 + 28, 20, 12, '#0b1622');
    ctx.save(); ctx.beginPath(); ctx.rect(x0 + 46, y0 + 29, 18, 10); ctx.clip();
    lineasCodigo(x0 + 46, y0 + 29, 18, 10, t + n * 300, estado === 'escribiendo' ? 140 : 900, 2.4);
    ctx.restore();
    R(x0 + 53, y0 + 42, 4, 1, '#263d49');
    R(x0 + 6, y0 + 43, 64, 5, '#8a6a4a'); R(x0 + 6, y0 + 43, 64, 1, '#b08b62');
    R(x0 + 9, y0 + 48, 3, 10, '#5a4532'); R(x0 + 64, y0 + 48, 3, 10, '#5a4532');
    hit(`pasante:${agent.id}:${n}`, `Pasante ${modeloCorto(p.modelo)}: ${p.tarea || 'subagente'}`, x0, y0, cw, 58, () => openInteractiveModal('pasantes', { agentId: agent.id }));
  });
}

// =========================================================================
// VISTA DETALLADA: DESPACHO INDIVIDUAL (640 × 360 VIRTUAL)
// =========================================================================
function drawSingleDespacho(agentId, offsetX, t, now) {
  const agent = data?.agentes?.find(a => a.id === agentId) || { id: agentId, nombre: agentId, estado: 'apagado', personaje: {}, energia: {}, estadisticas: {} };
  const theme = companyThemes[agentId] || companyThemes.agy;
  const nombre = (agent.nombre || agentId).toUpperCase();

  ctx.save();
  ctx.translate(offsetX, 0);
  R(0, 0, 640, 360, '#0a0f16');
  R(0, 42, 640, 176, theme.dark || '#162233');
  R(0, 218, 640, 6, '#475569');
  R(0, 224, 640, 136, theme.carpet || '#1a2736');
  for (let sy = 228; sy < 360; sy += 8) R(0, sy, 640, 1, 'rgba(255,255,255,0.03)');

  drawPersonalizedWindow(195, 38, 250, 40, agentId, t);
  hit('ventana:' + agentId, 'Ventana (hora y reinicio de cuota)', 195, 38, 250, 40, () => openInteractiveModal('ventana', { agentId }));
  drawChalkboard(14, 82, 175, 134, agent.pasos_plan, agentId);
  drawCorkboard(195, 82, 120, 134, agent.carpetas, agentId);
  drawDynamicPoster(322, 82, 75, 60, agent.poster);
  drawTelemetryMonitor(404, 82, 222, 134, agent, t);
  hit('monitor:' + agentId, `Monitor (vista ${(agent.monitorView || 0) + 1}/3, clic alterna)`, 401, 79, 228, 140, () => {
    agent.monitorView = ((agent.monitorView || 0) + 1) % 3;
    openInteractiveModal('monitor', { agentId, initialTab: agent.monitorView });
  });

  // Estante de méritos bajo el póster: cada decoración en su hueco, sin solaparse.
  const decos = asArray((agent.despacho || defaultDespachos[agentId] || {}).decoraciones);
  R(326, 191, 68, 3, '#7c5539'); R(330, 194, 2, 5, '#5a3d28'); R(388, 194, 2, 5, '#5a3d28');
  decos.slice(0, 2).forEach((dec, k) => {
    const sx = 343 + k * 34, sy = 175;
    V1.drawDecoracion(dec.tipo, sx, sy, t);
    hit(`deco:${agentId}:${k}`, 'Mérito: ' + String(dec.id || dec.tipo).replace(/_/g, ' '), sx - 17, sy - 18, 34, 34, () => openInteractiveModal('decoracion', { decoracion: dec, agentId }));
  });

  const dx = DESK.x, dy = DESK.y;
  R(dx - 34, 262, DESK.w + 68, 92, theme.rug || '#2c4055');
  R(dx - 30, 266, DESK.w + 60, 84, 'rgba(0,0,0,0.18)');

  drawSecondFurniture(398, 300, agentId, t, agent.estadisticas || {});
  drawArchivadorDespacho(440, 252, agentId);

  const lugar = fueraDe(agentId, now);
  const presente = enMesa(agent) && !lugar;
  const ps = presente ? pose(agentId, now, puntoDespacho) : null;
  const persona = { personaje: {}, energia: {}, ...agent, id: agentId };
  const caja = [4, 224, 636];

  R(dx + 66, dy - 30, 28, 28, '#1a2937');
  R(dx + 68, dy - 33, 24, 7, '#263e4d');
  if (presente && !ps) {
    ctx.save();
    ctx.translate(dx + 80, dy + 4);
    ctx.scale(0.6, 0.6);
    V1.person(0, 0, persona, paused ? 0 : t);
    ctx.restore();
    if (!agent.pasos_plan || agent.pasos_plan.length === 0) {
      if (t % 10000 < 2800) {
        const qx = dx + 80, qy = dy - 38 + Math.round(Math.sin(t / 200) * 2);
        R(qx - 7, qy - 10, 14, 14, '#1e293b'); R(qx - 6, qy - 9, 12, 12, '#fbbf24');
        dText('?', qx, qy + 1, 8.5, '#0f172a', 'center', true);
      }
    }
    // Más pasantes, más estrés: humo sobre la cabeza.
    const np = (agent.pasantes_lista || []).length;
    if (np >= 3 && !paused) for (let k = 0; k < np - 1; k++) {
      const f = ((t / 900) + k / (np - 1)) % 1;
      ctx.globalAlpha = 0.45 * (1 - f);
      R(dx + 74 + Math.sin(f * 6 + k) * 6, dy - 40 - f * 22, 6 + f * 6, 4 + f * 3, '#94a3b8');
      ctx.globalAlpha = 1;
    }
  }
  if (ps && !ps.oculto && ps.y < dy) dibujarPose(persona, ps, t, 0.6, caja);

  V1.plant(24, 342);
  R(dx, dy, DESK.w, DESK.h, '#452a1a');
  R(dx + 2, dy + 2, DESK.w - 4, 12, '#5e3a24');
  R(dx + 10, dy + 14, 24, 46, '#352013');
  R(dx + DESK.w - 34, dy + 14, 24, 46, '#352013');
  R(dx + 48, dy + 48, 94, 12, '#caa460');
  R(dx + 50, dy + 49, 90, 10, '#fef08a');
  fitText(`ESTRELLA · ${nombre}`, dx + 95, dy + 54, 84, 5.2, '#1e293b', 'center', true);

  // Portátil a la izquierda; papeles que crecen con los pasantes; taza.
  R(dx + 6, dy - 15, 40, 17, '#0f172a'); R(dx + 8, dy - 13, 36, 13, presente ? '#1f4f6b' : '#111827');
  if (presente) lineasCodigo(dx + 10, dy - 11, 30, 8, t, 900, 2.6);
  R(dx + 2, dy + 2, 48, 4, '#334155');
  const np = (agent.pasantes_lista || []).length;
  for (let k = 0; k < np * 2; k++) R(dx + 150 - (k % 2) * 2, dy + 3 - k * 2, 16, 2, k % 2 ? '#e2e8f0' : '#f8fafc');
  R(dx + 56, dy + 3, 8, 8, '#f8fafc');
  if (!paused) R(dx + 58, dy - 3 + Math.sin(t / 200) * 2, 2, 4, 'rgba(255,255,255,0.4)');

  drawDeskMonitor(dx + 104, dy - 52, 80, 48, agent, t, presente);
  hit('pantalla:' + agentId, 'Pantalla: archivo, herramienta e hilo', dx + 102, dy - 54, 84, 58, () => openInteractiveModal('monitor', { agentId, initialTab: 0 }));

  // Un cartel por estado de la mesa: en reunión, sin cuota con la hora, o caído en rojo. Apagado no lleva cartel.
  const cartel = lugar || (agent.estado_mesa === 'sin-cuota' ? 'SIN CUOTA' + (agent.vuelve ? ' · ' + horaCorta(agent.vuelve) : '') : agent.estado_mesa === 'caido' ? 'CAÍDO · reabre su panel' : null);
  if (cartel) cartelMesa(dx + 80, dy - 16, cartel, 58, 5, agent.estado_mesa === 'caido');

  drawPasantesDespacho(agent, t, pasantesFuera(agentId, now));
  if (!(agent.pasantes_lista || []).length) V1.plant(612, 342, true);

  const visita = currentVisitor && currentVisitor.target === agentId;
  drawPetWithBubble(96, 342, agentId, t, !visita || !visitaProgreso(currentVisitor, t).habla);
  if (visita) drawVisitorInOffice(currentVisitor, t);

  if (ps && !ps.oculto && ps.y >= dy) dibujarPose(persona, ps, t, 0.6, caja);
  ctx.restore();
}

// =========================================================================
// VISTA PLANTA GENERAL: 1440 de ancho y el alto que pida la ventana
// =========================================================================
const plantaAlto = () => Math.round(Math.max(640, Math.min(1100, 1440 * cv.height / Math.max(1, cv.width))));
// Arriba: Claude, café y Codex. Abajo: archivo (franja estrecha), sala de reuniones y agy.
function plantaLayout(PH) {
  const m = 6, pas = 26, h1 = Math.floor((PH - 2 * m - pas) / 2), y2 = m + h1 + pas, h2 = PH - m - y2;
  const wd = 494, wa = 170, wc = 1440 - 4 * m - 2 * wd, wr = 1440 - 4 * m - wa - wd;
  return {
    claude: [m, m, wd, h1], cafe: [2 * m + wd, m, wc, h1], codex: [3 * m + wd + wc, m, wd, h1],
    archivo: [m, y2, wa, h2], reuniones: [2 * m + wa, y2, wr, h2], agy: [3 * m + wa + wr, y2, wd, h2],
    pasillo: [0, m + h1, 1440, pas]
  };
}

// Encuadre de un despacho en su celda: recorta los márgenes del mundo de V1.room (480 × 370).
const MUNDO = { x0: 14, w: 452, y0: 44, h: 370 };
function encuadre(id, L) {
  const [rx, ry, rw, rh] = L[id], i = ids.indexOf(id);
  const s = Math.min((rw - 4) / MUNDO.w, (rh - 4) / MUNDO.h);
  const ox = rx + (rw - MUNDO.w * s) / 2, oy = ry + (rh - MUNDO.h * s) / 2;
  return { s, ox, oy, i, a: (wx, wy) => [ox + (wx - i * 480 - MUNDO.x0) * s, oy + (wy - MUNDO.y0) * s] };
}
function salaGeom(L) {
  const [x, y, w, h] = L.reuniones;
  const fy = y + 30 + Math.round(h * 0.3) + 5;
  const tw = Math.min(460, w - 300), th = 30, tx = Math.round(x + (w - tw) / 2);
  const ty = Math.round(fy + (y + h - fy) / 2 - 24);
  const arriba = ty + 8, abajo = ty + th + 30;
  const sx = k => Math.round(tx + (k + 0.5) * tw / 4);
  const asientos = [[sx(1), arriba], [sx(1), abajo], [sx(2), arriba], [sx(2), abajo], [sx(0), abajo], [sx(3), abajo], [sx(0), arriba], [sx(3), arriba]];
  return { x, y, w, h, fy, tx, ty, tw, th, puerta: x + 30, asientos };
}
function archivoGeom(L) {
  const [x, y, w, h] = L.archivo;
  const cab = { y: y + 62, h: 136, w: 42 };
  return { x, y, w, h, cab, xs: [x + 8, x + 54, x + 100], puerta: x + w - 15, pie: cab.y + cab.h + 34 };
}
function cafeGeom(L) {
  const [x, y, w, h] = L.cafe;
  const suelo = y + 30 + Math.round(h * 0.3) + 5, cx = x + 20, cy = suelo + 6;
  return { x, y, w, h, suelo, cx, cy, puerta: cx + 45, pie: Math.min(y + h - 16, cy + 170) };
}
// Hueco de puerta en la pared que da al pasillo.
function puertaPared(x, ry, rh, abajo) {
  const y = abajo ? ry + rh - 4 : ry - 2;
  R(x - 11, y, 22, 6, '#121c28');
  R(x - 13, y - 1, 2, 8, '#a07a52'); R(x + 11, y - 1, 2, 8, '#a07a52');
}

function drawPlanta(t, now, PH) {
  const L = plantaLayout(PH);
  R(0, 0, 1440, PH, '#090e15');
  const [, py, , ph] = L.pasillo;
  R(0, py, 1440, ph, '#121c28');
  for (let x = 8; x < 1440; x += 24) R(x, py + ph - 5, 12, 1, '#1f2d3d');
  ids.forEach(id => drawPlantaRoom(id, L, t, now));
  drawCommonArea(L, t, now);
  drawMeetingRoom(L, t, now);
  drawArchiveRoom(L, t, now);
  drawCorridorSigns(L);
  dibujarViajes(L, t, now);
}

function drawPlantaRoom(agentId, L, t, now) {
  const [rx, ry, rw, rh] = L[agentId];
  const agent = agente(agentId) || { id: agentId, nombre: agentId, estado: 'apagado', estadisticas: {} };
  const theme = companyThemes[agentId] || companyThemes.agy;
  const E = encuadre(agentId, L), i = E.i;
  const nombre = agentId === 'agy' ? 'agy' : agentId[0].toUpperCase() + agentId.slice(1);
  hit('planta:' + agentId, 'Despacho de ' + nombre, rx, ry, rw, rh, () => setView('despacho', agentId));

  ctx.save();
  R(rx, ry, rw, rh, '#1b2a3a');
  const lugar = fueraDe(agentId, now);
  const a = {
    estado: 'apagado', personaje: {}, energia: {}, ...agent, nombre, id: agentId, enReunion: !!lugar, fuera: lugar,
    pose: enMesa(agent) && !lugar ? pose(agentId, now, n => puntoPlanta(n, i)) : null,
    personajesPasantes: (agent.pasantes_lista || []).map(p => personajeDe(p.modelo, agentId)),
    ...(pasantesFuera(agentId, now) ? { pasantes: 0 } : {})
  };
  ctx.beginPath(); ctx.rect(rx + 2, ry + 2, rw - 4, rh - 4); ctx.clip();
  ctx.translate(E.ox, E.oy);
  ctx.scale(E.s, E.s);
  ctx.translate(-i * 480 - MUNDO.x0, -MUNDO.y0);
  V1.city(paused ? 0 : t);
  V1.room(a, i, paused ? 0 : t, now);

  // La visita entra por la puerta del despacho y habla dentro de él.
  let punta = null;
  if (currentVisitor && currentVisitor.target === agentId) {
    const pv = visitaProgreso(currentVisitor, t);
    const vx = i * 480 + 30 + 100 * pv.k, vy = 352;
    ctx.save(); ctx.translate(vx, vy); ctx.scale(pv.dir < 0 ? -0.75 : 0.75, 0.75);
    V1.person(0, 0, visitaObj(currentVisitor), t, pv.andando);
    ctx.restore();
    if (pv.habla) punta = ctx.getTransform().transformPoint(new DOMPoint(vx, vy - 48));
  }
  ctx.restore();

  ctx.save();
  puertaPared(E.a(i * 480 + 24, 0)[0], ry, rh, i !== 2);
  R(rx + 8, ry + 8, 150, 16, 'rgba(0,0,0,0.55)');
  fitText(`DESPACHO · ${nombre.toUpperCase()}`, rx + 14, ry + 16, 140, 7, theme.primary, 'left', true);
  if (punta) {
    const p = ctx.getTransform().inverse().transformPoint(punta);
    bocadillo(`${currentVisitor.name}: «${currentVisitor.quote}»`, p.x, p.y, [rx, ry + 26, rx + rw], 7, '#f8fafc', '#1e293b', 260);
  }
  ctx.restore();
}

// Ventanal con la ciudad de la v1, suelo con trama y plantas.
function decorarSala(x, y, w, h, t, vista = 480) {
  const vy = y + 30, vh = Math.round(h * 0.3);
  ctx.save();
  ctx.beginPath(); ctx.rect(x + 8, vy, w - 16, vh); ctx.clip();
  const s = (w - 16) / 480;
  ctx.translate(x + 8 - vista * s, vy - 44 * s);
  ctx.scale(s, Math.max(s, vh / 160));
  V1.city(paused ? 0 : t);
  ctx.restore();
  R(x + 6, vy - 3, w - 12, 3, '#68808a');
  R(x + 6, vy + vh, w - 12, 5, '#172d3c');
  const fy = vy + vh + 5;
  R(x + 2, fy, w - 4, y + h - 2 - fy, '#26363f');
  for (let yy = fy + 6; yy < y + h - 4; yy += 9) for (let xx = x + 8; xx < x + w - 8; xx += 12) R(xx, yy, 3, 1, '#34474f');
  R(x + 2, fy, w - 4, 2, '#849087');
  V1.plant(x + 24, y + h - 14, true);
  V1.plant(x + w - 24, y + h - 14, true);
}

const personaObj = id => ({ personaje: {}, ...(agente(id) || {}), id });
const pasanteObj = (jefe, p) => ({ id: jefe, nombre: modeloCorto(p.modelo), personaje: personajeDe(p.modelo, jefe), energia: { semanal: 100 } });
const nombreDe = k => k?.startsWith('p:') ? 'pasante' : k === 'agy' ? 'agy' : k ? k[0].toUpperCase() + k.slice(1) : 'la mesa';
function resumenReunion(m) {
  if (m.tipo === 'arranque') return `${nombreDe(m.quienes?.[0] || m.participantes[0])} + ${(m.intercambios || []).length || 'sus'} pasantes`;
  if (m.corona) return `♛ ${nombreDe(m.corona.de)} → ${nombreDe(m.corona.para)}`;
  const x = (m.intercambios || [])[0];
  return x ? `${nombreDe(x.de)} → ${nombreDe(x.para)}` : (m.quienes || m.participantes).map(nombreDe).join(' · ');
}
function carpetaMesa(x, y, col) { R(x - 10, y - 7, 20, 14, '#0b1120'); R(x - 9, y - 6, 18, 12, col); R(x - 9, y - 9, 8, 4, col); R(x - 6, y - 2, 12, 1, '#ffffff'); R(x - 6, y + 1, 9, 1, '#ffffff'); }

// SALA DE REUNIONES: proyector con el tema, mesa larga y cola de reuniones.
function drawMeetingRoom(L, t, now) {
  const g = salaGeom(L), { x, y, w, h } = g;
  hit('planta:reuniones', 'Sala de reuniones', x, y, w, h, () => openInteractiveModal('reuniones'));
  ctx.save();
  R(x, y, w, h, '#1e293b');
  R(x + 2, y + 2, w - 4, h - 4, '#15202e');
  decorarSala(x, y, w, h, t, 480);
  puertaPared(g.puerta, y, h, false);
  R(x + w / 2 - 110, y + 8, 220, 18, '#0f172a');
  fitText('SALA DE REUNIONES', x + w / 2, y + 17, 208, 7.5, '#6ee7b7', 'center', true);

  const m = reunionActual, pw = 380, px = x + w / 2 - pw / 2, py = y + 32;
  R(px - 4, py, pw + 8, 62, '#0f172a');
  R(px, py + 4, pw, 54, m ? '#1e3a4a' : '#1a2736');
  R(x + w / 2 - 2, py - 4, 4, 4, '#475569');
  if (m) {
    if (!paused) { ctx.globalAlpha = 0.08 + 0.05 * Math.sin(t / 300); R(px, py + 4, pw, 54, '#fef08a'); ctx.globalAlpha = 1; }
    fitText(`${ETIQUETA_REUNION[m.tipo] || 'Reunión'}: ${m.tema}`, x + w / 2, py + 17, pw - 16, 7.5, '#fef08a', 'center', true);
    fitText(resumenReunion(m), x + w / 2, py + 32, pw - 16, 6.5, '#e2e8f0', 'center');
    fitText(colaReuniones.length ? `En cola: ${colaReuniones.map(c => ETIQUETA_REUNION[c.tipo]).join(' · ')}` : 'Sin reuniones en cola', x + w / 2, py + 46, pw - 16, 6, '#94a3b8', 'center');
  } else {
    const hAct = activeThread();
    fitText(hAct ? 'SIN REUNIÓN' : 'SALA LIBRE', x + w / 2, py + 17, pw - 16, 7.5, '#6ee7b7', 'center', true);
    fitText(ultimaReunion ? `Última: ${ETIQUETA_REUNION[ultimaReunion.tipo]} · ${ultimaReunion.tema}` : `Hilo activo: ${hAct?.titulo || '—'}`, x + w / 2, py + 32, pw - 16, 6.5, '#fef08a', 'center');
    fitText(`♛ Líder: ${hAct?.lider || '—'} · ${hAct?.conteo_mensajes ?? (hAct?.mensajes || []).length} mensajes`, x + w / 2, py + 46, pw - 16, 6, '#94a3b8', 'center');
  }

  // Quién está sentado (los que aún andan se dibujan encima de la planta).
  const sentados = {};
  if (m) for (const v of Object.values(viajes)) {
    if (v.reunion !== m) continue;
    const p = posViaje(v, now, L);
    if (p?.fase === 'estancia') sentados[v.id] = { ...p, obj: personaObj(v.id), esc: 0.6 };
    v.pasantes.forEach((q, j) => {
      const pp = posViaje(v, now, L, q.dest, q.retraso, q.dOut);
      if (pp?.fase === 'estancia') sentados['p:' + j] = { ...pp, obj: pasanteObj(v.id, q.p), esc: 0.48 };
    });
  }
  const sentar = s => { ctx.save(); ctx.translate(s.x, s.y); ctx.scale(s.esc, s.esc); V1.person(0, 0, { ...s.obj, estado: 'esperando', energia: { semanal: 100 } }, paused ? 0 : t); ctx.restore(); };
  const arriba = ([, sy]) => sy < g.ty + g.th;
  g.asientos.forEach(s => { if (arriba(s)) { R(s[0] - 10, s[1] - 26, 20, 16, '#2c3a4d'); R(s[0] - 10, s[1] - 26, 20, 3, '#3d4f66'); } });
  Object.values(sentados).filter(s => arriba([s.x, s.y])).forEach(sentar);

  R(g.tx - 4, g.ty - 2, g.tw + 8, g.th + 6, '#4a2d1b');
  R(g.tx, g.ty, g.tw, g.th, '#855232');
  R(g.tx, g.ty, g.tw, 3, '#a8703f');
  R(g.tx + 10, g.ty + g.th + 4, 6, 10, '#3b2416'); R(g.tx + g.tw - 16, g.ty + g.th + 4, 6, 10, '#3b2416');
  R(g.tx + g.tw / 2 - 12, g.ty + 10, 24, 10, '#1f2937'); R(g.tx + g.tw / 2 - 10, g.ty + 11, 20, 7, m ? '#6ee7b7' : '#334155');

  // Bandeja física de entregas en la mesa de reuniones (contrato #23)
  const entregasNoArchivadas = asArray(data?.entregas).filter(e => e.estado !== 'archivada');
  const bx = g.tx + 24, by = g.ty + 4, bw = 100, bh = Math.max(18, g.th - 8);
  R(bx - 1, by - 1, bw + 2, bh + 2, '#2e1c10');
  R(bx, by, bw, bh, '#3d2516');
  R(bx + 1, by + 1, bw - 2, bh - 2, '#52341f');
  fitText('BANDEJA ENTREGAS', bx + bw / 2, by + 4, bw - 4, 3.8, '#d4c5a9', 'center', true);
  hit('planta:bandeja', `Bandeja de entregas (${entregasNoArchivadas.length} no archivadas)`, bx, by, bw, bh, () => openInteractiveModal('bandeja'));
  if (!entregasNoArchivadas.length) {
    fitText('(vacía)', bx + bw / 2, by + bh / 2 + 1, bw - 4, 4.0, '#8c755b', 'center');
  } else {
    entregasNoArchivadas.slice(0, 5).forEach((ent, idx) => {
      const cx = bx + 12 + idx * 17, cy = by + 11;
      const col = ent.estado === 'aceptada' ? '#22c55e' : ent.estado === 'devuelta' ? '#ef4444' : '#eab308';
      R(cx - 7, cy - 4, 14, 9, '#0f172a');
      R(cx - 6, cy - 3, 12, 7, col);
      R(cx - 6, cy - 5, 5, 2, col);
      const aut = String(ent.autor || ent.tarea || '').slice(0, 3).toUpperCase();
      dText(aut, cx, cy + 2, 3.2, '#0f172a', 'center', true);
      hit('entrega:' + (ent.tarea || idx), `Entrega: ${ent.tarea} (${ent.estado}) de ${ent.autor}`, cx - 7, cy - 5, 14, 10, () => openInteractiveModal('bandeja'));
    });
  }

  // Carpetas (o la corona) que pasan de un asiento a otro por encima de la mesa.
  if (m && now >= m.tSentado && !paused) {
    const borde = k => { const s = g.asientos[m.sillas[k]]; return s ? [s[0], arriba(s) ? g.ty + 9 : g.ty + g.th - 7] : [g.tx + g.tw / 2, g.ty + g.th / 2]; };
    const vuelo = (de, para, t0) => {
      const [x0, y0] = borde(de), [x1, y1] = para ? borde(para) : [g.tx + g.tw / 2 + 30, g.ty + g.th / 2];
      const f = Math.max(0, Math.min(1, (now - t0) / 1300));
      return [x0 + (x1 - x0) * f, y0 + (y1 - y0) * f - Math.sin(Math.PI * f) * 26, f];
    };
    if (m.corona) {
      const [cx, cy] = vuelo(m.corona.de, m.corona.para, m.tSentado + 1600);
      V1.crownShape(cx, cy - 34);
    }
    (m.intercambios || []).forEach((xc, j) => {
      const [fx, fy, f] = vuelo(xc.de, xc.para, m.tSentado + 1600 + j * 1800);
      carpetaMesa(fx, fy, companyThemes[xc.de]?.primary || '#f59e0b');
      if (f > 0 && f < 1) {
        const s = sentados[xc.de];
        if (s) bocadillo(`carpeta → ${nombreDe(xc.para)}`, s.x, s.y - 30, [x + 4, y + 96, x + w - 4], 6.5);
      }
    });
  } else if (m) {
    const lid = norm(activeThread()?.lider);
    if (sentados[lid]) V1.crownShape(sentados[lid].x, sentados[lid].y - 34);
  }

  g.asientos.forEach(s => { if (!arriba(s)) R(s[0] - 10, s[1] - 6, 20, 6, '#334459'); });
  Object.values(sentados).filter(s => !arriba([s.x, s.y])).forEach(s => { sentar(s); R(s.x - 10, s.y - 8, 20, 9, '#2c3a4d'); R(s.x - 10, s.y - 8, 20, 2, '#3d4f66'); });
  fitText(m ? `EN REUNIÓN · ${ETIQUETA_REUNION[m.tipo] || ''}` : colaReuniones.length ? `${colaReuniones.length} reunión(es) esperando` : 'Traspasos, encargos, líderes y arranques',
    x + w / 2, y + h - 12, w - 140, 6.5, m ? '#6ee7b7' : '#94a3b8', 'center', !!m);
  ctx.restore();
}

// ZONA COMÚN: café, agua y sofá; quien está apagado o descansando duerme aquí.
function drawCommonArea(L, t, now) {
  const g = cafeGeom(L), { x, y, w, h, cx, cy } = g;
  hit('planta:cafe', 'Zona común y café', x, y, w, h, () => openInteractiveModal('cafe'));
  ctx.save();
  R(x, y, w, h, '#1b2a3a');
  R(x + 2, y + 2, w - 4, h - 4, '#131e2b');
  decorarSala(x, y, w, h, t, 960);
  puertaPared(g.puerta, y, h, true);
  R(x + 14, y + 8, 190, 18, '#0f172a');
  fitText('ZONA COMÚN · CAFÉ Y DESCANSO', x + 20, y + 17, 178, 7, '#f1cf85', 'left', true);

  // Quién se está sirviendo: k = ms delante de la cafetera.
  let k = null;
  for (const v of Object.values(viajes)) if (v.dest.sala === 'cafe') { const p = posViaje(v, now, L); if (p?.fase === 'estancia') k = p.k; }
  const total = (data?.agentes || []).reduce((acc, ag) => acc + (ag.estadisticas?.tokens_hoy || 0), 0);
  const lleno = Math.max(0.1, Math.min(1, 1 - total / 20000000));
  R(cx - 4, cy + 104, 98, 6, '#0b1219');
  R(cx, cy, 90, 106, '#3a424c'); R(cx + 3, cy + 3, 84, 100, '#2b333c');
  R(cx + 3, cy + 3, 84, 4, '#56606b');
  for (let c = 0; c < 3; c++) R(cx + 8 + c * 11, cy - 7, 8, 7, '#ece3cf');
  R(cx + 14, cy + 12, 62, 40, '#1b242d'); R(cx + 16, cy + 14 + 36 * (1 - lleno), 58, 36 * lleno, '#6f4e37');
  R(cx + 16, cy + 14 + 36 * (1 - lleno), 58, 2, '#9a7052');
  R(cx + 14, cy + 12, 3, 40, 'rgba(255,255,255,0.08)');
  R(cx + 38, cy + 58, 14, 6, '#8d97a1'); R(cx + 43, cy + 64, 4, 4, '#6b7580');
  R(cx + 30, cy + 94, 30, 4, '#56606b');
  if (k != null && k < 2600) {
    if (k < 1300) R(cx + 44, cy + 68, 2, 12 + (k / 120) % 4, '#6f4e37');
    R(cx + 35, cy + 78, 20, 16, '#ece3cf'); R(cx + 55, cy + 81, 5, 8, '#ece3cf');
    R(cx + 37, cy + 80 + 10 * (1 - Math.min(1, k / 1300)), 16, 3, '#6f4e37');
    if (k > 900 && !paused) { const v = Math.floor(t / 250) % 3; R(cx + 41 + v, cy + 66, 2, 6, 'rgba(220,230,235,0.6)'); R(cx + 48 - v, cy + 63, 2, 7, 'rgba(220,230,235,0.45)'); }
  }
  R(cx + 70, cy + 60, 6, 6, k != null ? '#fbbf24' : lleno > 0.25 ? '#4ade80' : '#f87171');
  fitText(`${number(total)} tok hoy`, cx + 45, cy + 115, 96, 5.2, '#f1cf85', 'center');

  const fx = x + 124, fy = g.suelo + 10;
  R(fx - 2, fy + 98, 44, 5, '#0b1219');
  R(fx, fy + 40, 40, 60, '#cfd6dc'); R(fx + 3, fy + 43, 34, 54, '#e3e8ec');
  R(fx + 6, fy, 28, 42, '#7cc4e8'); R(fx + 10, fy - 4, 20, 5, '#4b9cc8'); R(fx + 8, fy + 3, 4, 34, 'rgba(255,255,255,0.35)');
  if (!paused) { const b = (t / 70) % 34; R(fx + 20, fy + 36 - b, 3, 3, '#e0f2fe'); R(fx + 15, fy + 36 - (b + 15) % 34, 2, 2, '#e0f2fe'); }
  R(fx + 11, fy + 56, 6, 6, '#3b82f6'); R(fx + 23, fy + 56, 6, 6, '#ef4444');

  const ax = x + 172, ay = g.suelo + 34;
  R(ax, ay + 70, 250, 80, '#3a2f3f'); R(ax + 6, ay + 76, 238, 68, '#463848');
  for (let q = 0; q < 238; q += 16) R(ax + 6 + q, ay + 108, 8, 2, '#5a4a5c');
  R(ax + 15, ay, 220, 30, '#4b5d70'); R(ax + 15, ay, 220, 4, '#66798c');
  R(ax + 5, ay + 18, 24, 50, '#43546a'); R(ax + 221, ay + 18, 24, 50, '#43546a');
  R(ax + 5, ay + 18, 24, 4, '#5d7088'); R(ax + 221, ay + 18, 24, 4, '#5d7088');
  const cojines = [companyThemes.claude.primary, companyThemes.codex.primary, companyThemes.agy.primary];
  cojines.forEach((c, q) => { R(ax + 33 + q * 64, ay + 28, 58, 32, c); R(ax + 33 + q * 64, ay + 28, 58, 4, 'rgba(255,255,255,0.18)'); R(ax + 33 + q * 64, ay + 56, 58, 4, 'rgba(0,0,0,0.2)'); });
  R(ax + 29, ay + 60, 192, 10, '#3a4a5d');
  R(ax + 11, ay + 68, 6, 8, '#2a1d14'); R(ax + 233, ay + 68, 6, 8, '#2a1d14');

  // Descansan en el sofá, cada uno en su cojín, con su hora de vuelta si la hay.
  ids.forEach((id, q) => {
    const ag = agente(id);
    if (!ag || enMesa(ag)) return;
    const px = ax + 62 + q * 64, py = ay + 52;
    ctx.save(); ctx.translate(px, py); ctx.scale(0.5, 0.5);
    V1.person(0, 0, { ...ag, estado: 'apagado', energia: { semanal: 5 } }, paused ? 0 : t);
    ctx.restore();
    const sub = ag.estado === 'descansando' && ag.vuelve ? 'vuelve ' + horaCorta(ag.vuelve) : 'apagado';
    R(px - 30, ay - 22, 60, 18, 'rgba(15,23,42,0.85)');
    fitText(nombreDe(id), px, ay - 17, 56, 5.6, cojines[q], 'center', true);
    fitText(sub, px, ay - 9.5, 56, 5, '#cbd5e1', 'center');
  });

  const mx = ax + 55, my = ay + 96;
  R(mx, my, 140, 12, '#7a5236'); R(mx, my, 140, 3, '#9a6c48'); R(mx + 6, my + 12, 6, 14, '#5a3b26'); R(mx + 128, my + 12, 6, 14, '#5a3b26');
  R(mx + 14, my - 6, 30, 7, '#f3efe4'); R(mx + 16, my - 5, 26, 2, '#c9a24a');
  R(mx + 64, my - 8, 9, 9, '#ece3cf'); R(mx + 73, my - 6, 3, 5, '#ece3cf');
  R(mx + 96, my - 8, 9, 9, '#ece3cf'); R(mx + 105, my - 6, 3, 5, '#ece3cf');
  V1.plant(mx + 124, my - 2);
  if (my + 40 < y + h - 18) fitText('«Una pausa también es trabajo»', ax + 125, y + h - 14, 230, 6.5, '#94a3b8', 'center');
  ctx.restore();
}

// Lo que guarda el archivo, por cajón: hilos cerrados, encargos hechos y alertas.
function hiloCerrado(h) {
  if (['cerrado', 'hecho', 'concluido', 'archivado'].includes(String(h.estado || '').toLowerCase())) return true;
  const u = h.ultimo_mensaje || (h.mensajes || []).at(-1);
  return !!u && u.tipo === 'respuesta' && ['hecho', 'fallo'].includes(u.estado);
}
const fechaCorta = v => { const d = new Date(v); return isNaN(d) ? '—' : d.toLocaleString('es-CO', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }); };
function archivoDatos() {
  const hilos = (data?.hilos || []).filter(hiloCerrado).map(h => {
    const u = h.ultimo_mensaje || (h.mensajes || []).at(-1);
    return { tag: (u?.estado || h.estado || 'cerrado').toUpperCase(), titulo: h.titulo || h.id, sub: `Líder: ${h.lider || '—'} · ${fechaCorta(h.actualizado || u?.fecha)} · ${h.conteo_mensajes ?? (h.mensajes || []).length} mensajes`, orden: Date.parse(h.actualizado || u?.fecha || '') || 0 };
  });
  const vistosE = new Set(), encargos = [];
  for (const a of data?.agentes || []) for (const x of a.archivados || []) {
    const k = (x.hilo || x.titulo) + '|' + x.autor + '|' + x.hora;
    if (vistosE.has(k)) continue;
    vistosE.add(k);
    encargos.push({ tag: 'HECHO', titulo: x.titulo || x.hilo || 'tarea', sub: `Entregó: ${x.autor || '—'} · ${fechaCorta(x.hora)}`, orden: Date.parse(x.hora || '') || 0 });
  }
  const alertas = (data?.alertas || []).map(x => ({ tag: String(x.nivel || 'alerta').toUpperCase(), titulo: x.motivo || 'alerta', sub: `${x.agente || '—'} · ${fechaCorta(x.hora)} · ${x.revisada ? 'revisada' : 'sin revisar'}`, orden: Date.parse(x.hora || '') || 0 }));
  const ord = l => l.sort((a, b) => b.orden - a.orden);
  return [
    { nombre: 'Hilos', fuente: 'hilos con la última respuesta entregada', filas: ord(hilos), vacio: 'Ningún hilo cerrado todavía.' },
    { nombre: 'Encargos', fuente: 'tareas hechas del registro de cada agente', filas: ord(encargos), vacio: 'Aún no hay tareas hechas.' },
    { nombre: 'Alertas', fuente: 'motivo y nivel del vigía (sin el comando)', filas: ord(alertas).slice(0, 80), vacio: 'Sin alertas.' }
  ];
}

// ARCHIVO COMÚN: franja estrecha con tres archivadores (Hilos, Encargos, Alertas).
function drawArchiveRoom(L, t, now) {
  const g = archivoGeom(L), { x, y, w, h, cab, xs } = g;
  const cats = archivoDatos();
  hit('planta:archivo', 'Archivo común', x, y, w, h, () => openInteractiveModal('archivador', { cajon: 0 }));
  ctx.save();
  R(x, y, w, h, '#1b2a3a');
  R(x + 2, y + 2, w - 4, h - 4, '#1a2531');
  const fy = cab.y + cab.h - 22;
  for (let yy = y + 34; yy < fy; yy += 14) R(x + 2, yy, w - 4, 1, '#202e3c');
  R(x + 2, fy, w - 4, y + h - 2 - fy, '#26363f');
  for (let yy = fy + 6; yy < y + h - 4; yy += 9) for (let xx = x + 8; xx < x + w - 8; xx += 12) R(xx, yy, 3, 1, '#34474f');
  R(x + 2, fy, w - 4, 2, '#849087');
  puertaPared(g.puerta, y, h, false);
  R(x + 8, y + 8, w - 40, 18, '#0f172a');
  fitText('ARCHIVO COMÚN', x + 14, y + 17, w - 52, 7, '#f1cf85', 'left', true);

  // Lámpara colgada y su luz.
  const lx = x + 70;
  R(lx - 1, y + 2, 2, 30, '#475569'); R(lx - 16, y + 32, 32, 8, '#166534'); R(lx - 17, y + 39, 34, 2, '#f8fafc'); R(lx - 5, y + 41, 10, 5, '#fef08a');
  if (!paused) {
    const grad = ctx.createLinearGradient(0, y + 41, 0, cab.y + cab.h);
    grad.addColorStop(0, 'rgba(254, 240, 138, 0.14)'); grad.addColorStop(1, 'rgba(254, 240, 138, 0)');
    ctx.fillStyle = grad;
    ctx.beginPath(); ctx.moveTo(lx - 16, y + 41); ctx.lineTo(lx + 16, y + 41); ctx.lineTo(lx + 70, cab.y + cab.h); ctx.lineTo(lx - 70, cab.y + cab.h); ctx.closePath(); ctx.fill();
  }

  // Cajón que se abre cuando alguien guarda una carpeta (k = ms delante del archivador).
  let abierto = null;
  for (const v of Object.values(viajes)) if (v.dest.sala === 'archivo') { const p = posViaje(v, now, L); if (p?.fase === 'estancia') abierto = { c: v.dest.cajon, k: p.k, p, col: companyThemes[v.id]?.primary }; }
  const colores = ['#f59e0b', '#3b82f6', '#10b981', '#ec4899', '#8b5cf6'];
  cats.forEach((cat, c) => {
    const cx = xs[c], n = cat.filas.length;
    R(cx - 1, cab.y - 1, cab.w + 2, cab.h + 2, '#0f172a');
    R(cx, cab.y, cab.w, cab.h, '#334155');
    R(cx + 2, cab.y + 2, cab.w - 4, cab.h - 4, '#263445');
    for (let f = 0; f < Math.min(4, Math.ceil(n / 4)); f++) { R(cx + 4 + f * 9, cab.y - 6, 7, 6, colores[(c + f) % 5]); R(cx + 5 + f * 9, cab.y - 8, 5, 2, colores[(c + f) % 5]); }
    R(cx + 3, cab.y + 3, cab.w - 6, 9, '#f8fafc');
    fitText(cat.nombre.toUpperCase(), cx + cab.w / 2, cab.y + 7.5, cab.w - 8, 5, '#0f172a', 'center', true);
    for (let d = 0; d < 4; d++) {
      const dy = cab.y + 15 + d * 30;
      let o = 0;
      if (abierto && abierto.c === c && d === 0) { const k = abierto.k; o = k < 700 ? k / 700 : k < 2300 ? 1 : k < 3000 ? 1 - (k - 2300) / 700 : 0; }
      if (o > 0) {
        R(cx + 3, dy, cab.w - 6, 27, '#0b1219');
        for (let f = 0; f < 4; f++) R(cx + 7 + f * 8, dy + 2, 6, 6 + o * 6, colores[(f + 2) % 5]);
      }
      const oy = Math.round(o * 12);
      R(cx + 3, dy + oy, cab.w - 6, 27, '#475569');
      R(cx + 5, dy + oy + 2, cab.w - 10, 23, '#384656');
      R(cx + 5, dy + oy + 2, cab.w - 10, 2, '#556578');
      R(cx + 13, dy + oy + 18, 16, 3, '#cbd5e1');
      R(cx + 9, dy + oy + 6, cab.w - 18, 9, '#f8fafc');
      if (d === 0) fitText(String(n), cx + cab.w / 2, dy + oy + 10.5, cab.w - 20, 5.6, '#0f172a', 'center', true);
      else R(cx + 12, dy + oy + 10, cab.w - 24, 1, '#94a3b8');
    }
    hit('archivo:' + c, `Archivador de ${cat.nombre} (${n})`, cx, cab.y - 8, cab.w, cab.h + 8, () => openInteractiveModal('archivador', { cajon: c }));
  });
  // La carpeta cae de la mano al cajón abierto.
  if (abierto && abierto.k >= 700 && abierto.k < 1500 && !paused) {
    const f = (abierto.k - 700) / 800, tx = xs[abierto.c] + cab.w / 2, ty = cab.y + 22;
    const sx = abierto.p.x + 8, sy = abierto.p.y - 16;
    carpetaMesa(sx + (tx - sx) * f, sy + (ty - sy) * f - Math.sin(Math.PI * f) * 14, abierto.col || '#f59e0b');
  }

  // Cajas y planta solo si sobra suelo bajo la línea donde se para quien archiva.
  const libreY = g.pie + 8, fondo = y + h - 30;
  if (fondo - libreY >= 26) {
    for (let b = 0; b < Math.min(2, Math.floor((fondo - libreY) / 24)); b++) {
      const by = fondo - 22 - b * 22, bx = x + 12 + b * 4;
      R(bx, by, 44, 20, '#92400e'); R(bx + 2, by + 2, 40, 16, '#b45309'); R(bx - 1, by - 2, 46, 5, '#78350f'); R(bx + 6, by + 6, 9, 7, '#ffffff');
    }
    V1.plant(x + w - 22, fondo, false);
  }
  fitText(`${cats[0].filas.length} hilos cerrados`, x + w / 2, y + h - 21, w - 16, 6, '#cbd5e1', 'center');
  fitText(`${cats[1].filas.length} encargos · ${cats[2].filas.length} alertas`, x + w / 2, y + h - 11, w - 16, 6, '#94a3b8', 'center');
  ctx.restore();
}

// Señalética del pasillo, medida contra su placa.
function drawCorridorSigns(L) {
  const [, py] = L.pasillo, sy = py + 3, sh = 12;
  const col = id => L[id][0] + L[id][2] / 2;
  [['Claude ↑ · Archivo ↙', col('claude'), '#d27e67'], ['Café ↑ · Reuniones ↓', col('cafe'), '#6ee7b7'], ['Codex ↑ · agy ↓', col('codex'), '#5ed3a1']].forEach(([txt, cx, c]) => {
    R(cx - 80, sy, 160, sh, '#0f172a');
    fitText(txt, cx, sy + sh / 2, 152, 6.4, c, 'center', true);
  });
}

// Viajeros sobre la planta: ida, estancia (salvo los sentados en la sala) y vuelta.
function dibujarViajes(L, t, now) {
  if (paused) return;
  for (const v of Object.values(viajes)) {
    const lista = [{ obj: personaObj(v.id), esc: 0.6, pos: posViaje(v, now, L), jefe: true }];
    v.pasantes.forEach(q => lista.push({ obj: pasanteObj(v.id, q.p), esc: 0.46, pos: posViaje(v, now, L, q.dest, q.retraso, q.dOut) }));
    for (const it of lista) {
      const p = it.pos;
      if (!p || (p.fase === 'estancia' && v.dest.sala === 'reuniones')) continue;
      let prop = null, texto = null;
      if (it.jefe) {
        prop = p.fase === 'ida' ? v.ida : p.fase === 'vuelta' ? v.vuelta : null;
        if (p.fase === 'estancia' && v.tipo === 'archivo') { prop = p.k < 700 ? 'carpeta' : null; texto = 'guardando la carpeta'; }
        if (p.fase === 'estancia' && v.tipo === 'cafe') { prop = p.k > 2600 ? 'cafe' : null; texto = p.k < 2600 ? 'sirviendo un café' : 'listo, a trabajar'; }
      }
      dibujarPose(it.obj, { x: p.x, y: p.y, andando: p.andando, dir: p.dir, prop, color: companyThemes[v.id]?.primary }, t, it.esc, null);
      if (texto) {
        const [rx, ry, rw] = L[v.dest.sala];
        bocadillo(texto, p.x, p.y - 30, [rx, ry + 28, rx + rw], 6.2, '#f8fafc', '#1e293b', 120);
      }
    }
  }
}

// Resalte del objeto bajo el ratón: usa el rectángulo registrado al dibujarlo.
function dibujarResalte() {
  const h = hoverId && hits.find(x => x.id === hoverId);
  if (!h) return;
  const [x, y, w, ht] = h.box;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.strokeStyle = '#f1cf85'; ctx.lineWidth = 2;
  ctx.strokeRect(Math.round(x) + 0.5, Math.round(y) + 0.5, Math.round(w), Math.round(ht));
  ctx.font = fuente(12, true);
  const tw = Math.min(cv.width - 16, ctx.measureText(h.title).width + 16);
  const bx = Math.max(8, Math.min(cv.width - 8 - tw, x + w / 2 - tw / 2));
  const by = y - 24 >= 4 ? y - 24 : Math.min(cv.height - 24, y + ht + 4);
  R(bx, by, tw, 20, 'rgba(15, 23, 42, 0.95)');
  R(bx, by, tw, 2, '#f1cf85');
  fitText(h.title, bx + tw / 2, by + 11, tw - 12, 12, '#fef08a', 'center', true);
}

// =========================================================================
// BUCLE PRINCIPAL DE RENDERIZADO (60 FPS)
// =========================================================================
function draw(now) {
  // El búfer sigue al tamaño real del lienzo en cada fotograma: sin franjas al cambiar la ventana.
  if (cv.clientWidth && (cv.width !== Math.round(cv.clientWidth * DPR()) || cv.height !== Math.round(cv.clientHeight * DPR()))) { cv.width = Math.round(cv.clientWidth * DPR()); cv.height = Math.round(cv.clientHeight * DPR()); }
  if (!cv.width || !cv.height) return;
  const t = paused ? 0 : now;
  hits = [];
  if (depurar) textosFrame = [];
  gestionarViajes(now);
  agendarVida(now);
  updateVisitors(t);
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.imageSmoothingEnabled = false;
  R(0, 0, cv.width, cv.height, '#090e15');

  if (currentView === 'despacho') {
    const scale = Math.min(cv.width / 640, cv.height / 360);
    escalaCss = scale / DPR();
    const offsetX = (cv.width - 640 * scale) / 2;
    const offsetY = (cv.height - 360 * scale) / 2;
    if (!paused) {
      cameraX += (targetCameraX - cameraX) * 0.18;
      if (Math.abs(targetCameraX - cameraX) < 0.2) cameraX = targetCameraX;
    } else cameraX = targetCameraX;
    ctx.setTransform(scale, 0, 0, scale, offsetX, offsetY);
    ctx.translate(-cameraX, 0);
    drawSingleDespacho('claude', 0, t, now);
    drawSingleDespacho('codex', 640, t, now);
    drawSingleDespacho('agy', 1280, t, now);
  } else {
    const PH = plantaAlto();
    const scale = Math.min(cv.width / 1440, cv.height / PH);
    escalaCss = scale / DPR();
    ctx.setTransform(scale, 0, 0, scale, (cv.width - 1440 * scale) / 2, (cv.height - PH * scale) / 2);
    drawPlanta(t, now, PH);
  }
  dibujarResalte();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
}


let lastFrame = 0;
// Un solo reloj (performance.now) para dibujo y recorridos: el sello de rAF puede ir en otra base.
function frame() {
  const t = performance.now();
  if (!document.hidden && !paused && t - lastFrame >= 33) {
    draw(t);
    lastFrame = t;
  }
  requestAnimationFrame(frame);
}

// Franja urgente: los seis estados de la mesa y lo que espera a Daniel (mismo recuento que la vista Resumen).
function actualizarFranjaUrgente(d) {
  const f = $('franja-urgente');
  if (!f) return;
  const cuenta = { trabajando: 0, libre: 0, 'esperando-daniel': 0, 'sin-cuota': 0, caido: 0, apagado: 0 };
  for (const a of d?.agentes || []) if (a.estado_mesa in cuenta) cuenta[a.estado_mesa]++;
  const aprobaciones = (d?.pendientes || []).filter(p => p.texto && (p.texto.includes('ESCALADO') || p.texto.includes('aprobación'))).length;
  const necesito = aprobaciones + cuenta['esperando-daniel'] + cuenta.caido + (d?.alertas || []).filter(a => a.nivel === 'alto' && !a.revisada).length;
  const etiquetas = [['trabajando', 'Trabajando'], ['libre', 'Libre'], ['esperando-daniel', 'Esperando a Daniel'], ['sin-cuota', 'Sin cuota'], ['caido', 'Caído'], ['apagado', 'Apagado']];
  f.innerHTML = etiquetas.map(([k, t]) => `<span>${t}: ${cuenta[k]}</span>`).join('') + `<span class="necesito${necesito ? '' : ' cero'}">Te necesito: ${necesito}</span>`;
}

function clockTick() {
  const clockEl = $('clock');
  if (clockEl) {
    clockEl.textContent = new Date().toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit', hour12: false });
  }
  if (paused) draw(performance.now());
}

// =========================================================================
// EVENTOS Y ENLACES DE BOTONES
// =========================================================================
document.addEventListener('click', async e => {
  const btn = e.target.closest('button');
  if (btn) {
    if (btn.id === 'btn-toggle-view') {
      setView(currentView === 'planta' ? 'despacho' : 'planta');
      return;
    }
    if (btn.id === 'btn-tv-mode') {
      toggleTvMode();
      return;
    }
    if (btn.id === 'btn-toggle-timeline') {
      timelineOpen = !timelineOpen;
      $('timeline-drawer').hidden = !timelineOpen;
      btn.classList.toggle('active', timelineOpen);
      return;
    }
    if (btn.id === 'btn-close-timeline') {
      timelineOpen = false;
      $('timeline-drawer').hidden = true;
      $('btn-toggle-timeline')?.classList.remove('active');
      return;
    }
    if (btn.id === 'btn-toggle-hud') {
      hudAgentsOpen = !hudAgentsOpen;
      $('hud-agents-panel').hidden = !hudAgentsOpen;
      btn.classList.toggle('active', hudAgentsOpen);
      return;
    }
    if (btn.id === 'btn-close-hud') {
      hudAgentsOpen = false;
      $('hud-agents-panel').hidden = true;
      $('btn-toggle-hud')?.classList.remove('active');
      return;
    }
    if (btn.id === 'btn-toggle-threads') {
      hudThreadsOpen = !hudThreadsOpen;
      $('hud-threads-panel').hidden = !hudThreadsOpen;
      btn.classList.toggle('active', hudThreadsOpen);
      if (hudThreadsOpen && selected) cargarHilo(selected);
      return;
    }
    if (btn.id === 'btn-close-threads') {
      hudThreadsOpen = false;
      $('hud-threads-panel').hidden = true;
      $('btn-toggle-threads')?.classList.remove('active');
      return;
    }
    if (btn.id === 'motion') {
      paused = !paused;
      setMotion();
      return;
    }
    if (btn.id === 'btn-motion-despacho') {
      paused = !paused;
      setMotion();
      return;
    }
    if (btn.id === 'btn-back-planta') {
      setView('planta');
      return;
    }
    if (btn.id === 'btn-prev-despacho') {
      nextDespacho(-1);
      return;
    }
    if (btn.id === 'btn-next-despacho') {
      nextDespacho(1);
      return;
    }
    if (btn.classList.contains('agent-tab')) {
      setView('despacho', btn.dataset.agent);
      return;
    }
    if (btn.classList.contains('btn-enter-room')) {
      setView('despacho', btn.dataset.agent);
      return;
    }
    if (btn.dataset.thread) {
      selected = btn.dataset.thread;
      cargarHilo(selected);
      renderThreads();
      const h = data?.hilos?.find(x => x.id === selected);
      const quienes = [...new Set((h?.participantes || []).map(norm).filter(id => ids.includes(id)))];
      if (h && quienes.length >= 2) encolarReunion({ tipo: 'revision', participantes: quienes, tema: h.titulo || h.id });
      draw(performance.now());
      return;
    }
    if (btn.id === 'btn-close-modal' || btn.id === 'btn-modal-dismiss') {
      closeCorkModal();
      return;
    }
    if (btn.id === 'btn-close-interactive-modal' || btn.id === 'btn-interactive-modal-dismiss') {
      closeInteractiveModal();
      return;
    }
  }

  // Clic fuera del modal para cerrarlo
  if (e.target === $('corcho-modal')) {
    closeCorkModal();
    return;
  }
  if (e.target === $('interactive-modal')) {
    closeInteractiveModal();
    return;
  }

  // Clic en el lienzo: el objeto de arriba bajo el puntero.
  if (e.target === cv) {
    const rect = cv.getBoundingClientRect();
    const h = hitEn(e.clientX - rect.left, e.clientY - rect.top);
    if (h?.accion) h.accion();
  }
});

// Teclado (Esc o clic fuera cierra)
window.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    if (!$('interactive-modal')?.hidden) {
      closeInteractiveModal();
      return;
    }
    if (!$('corcho-modal')?.hidden) {
      closeCorkModal();
      return;
    }
    if (timelineOpen) {
      $('btn-close-timeline')?.click();
      return;
    }
    if (hudAgentsOpen) {
      $('btn-close-hud')?.click();
      return;
    }
    if (currentView === 'despacho') {
      setView('planta');
    }
  } else if (currentView === 'despacho') {
    if (e.key === 'ArrowLeft') { e.preventDefault(); nextDespacho(-1); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); nextDespacho(1); }
  }
});

// Ratón: el resalte y el cursor usan los rectángulos registrados al dibujar.
cv.addEventListener('mousemove', e => {
  const rect = cv.getBoundingClientRect();
  const h = hitEn(e.clientX - rect.left, e.clientY - rect.top);
  const id = h?.id || null;
  cv.style.cursor = h ? 'pointer' : 'default';
  if (id !== hoverId) { hoverId = id; if (paused) draw(performance.now()); }
});

cv.addEventListener('mouseleave', () => {
  hoverId = null;
  cv.style.cursor = 'default';
  if (paused) draw(performance.now());
});

// Inicialización
window.addEventListener('resize', fit);
new ResizeObserver(fit).observe(cv);
setMotion();
fit();

// Enlace directo y parámetros URL: #claude, #codex, #agy, #planta y soporte para ?abrir=<objeto> y ?visita=1
const abrirDesdeHash = () => {
  const h = location.hash.slice(1);
  if (!h) return;
  const [routePart] = h.split('?');
  if (ids.includes(routePart)) setView('despacho', routePart);
  else if (routePart === 'planta') setView('planta');
  cameraX = targetCameraX; // al entrar por enlace no hay paneo
  const params = hashParams();
  if (params.get('resaltar')) hoverId = params.get('resaltar');
  const agentId = ids.includes(routePart) ? routePart : undefined;
  const abrir = params.get('abrir');
  if (abrir) {
    const f = () => openInteractiveModal(abrir, { agentId });
    if (data) f(); else abrirPendiente = f;
  }
  if (params.get('visita')) {
    const target = agentId || 'claude';
    const pick = (realModelCatalog[target] || realModelCatalog.claude)[0];
    currentVisitor = { ...pick, target, startTime: performance.now(), duration: 9000 };
  }
  // ?demo=supervisar|tachar|ventana|paseo: esa rutina del despacho a los 8 s. reunion, archivo y cafe van por lanzarDemo.
  const demo = params.get('demo');
  if (['supervisar', 'tachar', 'ventana', 'paseo'].includes(demo)) setTimeout(() => {
    if (!data) return;
    const id = agentId || 'claude';
    delete actores[id];
    proximo.super[id] = proximo.ocio[id] = performance.now() + 60000;
    programar(id, demo);
  }, 8000);
};

window.addEventListener('hashchange', abrirDesdeHash);
abrirDesdeHash();
clockTick();
setInterval(clockTick, 30000);
requestAnimationFrame(frame);
refresh();

// ?depurar=1: tras 13 s deja en el DOM los textos que no caben, los que se pisan y las zonas clicables.
const errores = [];
if (depurar) window.addEventListener('error', e => errores.push(String(e.message) + ' @' + e.lineno));
if (depurar) setTimeout(() => {
  draw(performance.now()); // sin pestaña visible (--dump-dom) no hay fotogramas: se dibuja uno para medir
  const T = textosFrame, solapes = [];
  for (let i = 0; i < T.length; i++) for (let j = i + 1; j < T.length; j++) {
    const a = T[i].box, b = T[j].box;
    const ix = Math.min(a[0] + a[2], b[0] + b[2]) - Math.max(a[0], b[0]);
    const iy = Math.min(a[1] + a[3], b[1] + b[3]) - Math.max(a[1], b[1]);
    const visible = r => r[0] + r[2] > 0 && r[0] < cv.width && r[1] + r[3] > 0 && r[1] < cv.height;
    if (ix > 1.5 && iy > 1.5 && visible(a) && visible(b)) solapes.push(`${T[i].txt} ⟷ ${T[j].txt}`);
  }
  const pre = document.createElement('pre');
  pre.id = 'depuracion'; pre.hidden = true;
  pre.textContent = JSON.stringify({ lienzo: [cv.width, cv.height, innerWidth, innerHeight], errores, actores: Object.fromEntries(Object.entries(actores).map(([k, v]) => [k, v.tipo + ' ' + Math.round(v.inicio) + '-' + Math.round(v.fin)])), ahora: Math.round(performance.now()), poses: ids.map(id => JSON.stringify(pose(id, performance.now(), puntoDespacho))), pausa: paused, ultima: ultimaReunion?.tipo, reunion: reunionActual && { tipo: reunionActual.tipo, sentados: Math.round(reunionActual.tSentado), fin: Math.round(reunionActual.fin) }, cola: colaReuniones.map(c => c.tipo), viajes: Object.values(viajes).map(v => `${v.id} ${v.tipo} ${Math.round(v.t0)}+${Math.round(v.dOut)}/${Math.round(v.estancia)}`), textos: T.length, desbordes: [...desbordes], solapes, zonas: hits.map(h => h.id) });
  document.body.appendChild(pre);
}, (+hashParams().get("depurar_s") || 13) * 1000);
