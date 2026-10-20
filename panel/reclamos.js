// Tarjeta «Quién lleva qué»: líder de cada hilo activo, reclamos por agente, choques de archivos y bandeja de entregas.
(() => {
  const AGENTES = ['claude', 'codex', 'agy'];
  const normalizar = (a) => {
    const s = String(a || '').toLowerCase();
    return AGENTES.find((x) => s.startsWith(x)) || s.split(/\s/)[0] || '?';
  };
  const el = (tag, cls, texto) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (texto != null) n.textContent = texto;
    return n;
  };
  const hora = (iso) => (iso ? String(iso).slice(11, 16) : '');

  const tarjeta = el('section', 'mesa-reclamos');
  tarjeta.setAttribute('aria-label', 'Coordinación: líderes y reclamos');
  const cabecera = el('button', 'mesa-reclamos-cab', '🧩 Quién lleva qué');
  cabecera.setAttribute('aria-expanded', 'true');
  const cuerpo = el('div', 'mesa-reclamos-cuerpo');
  tarjeta.append(cabecera, cuerpo);

  let plegada = true;
  try {
    const guardada = localStorage.getItem('mesa-reclamos-plegada');
    if (guardada !== null) plegada = guardada === '1';
  } catch {}
  const aplicarPliegue = () => {
    cuerpo.hidden = plegada;
    cabecera.setAttribute('aria-expanded', String(!plegada));
  };
  cabecera.addEventListener('click', () => {
    plegada = !plegada;
    try { localStorage.setItem('mesa-reclamos-plegada', plegada ? '1' : '0'); } catch {}
    aplicarPliegue();
  });

  const estilo = el('style', null, `
    .mesa-reclamos { position: fixed; left: 12px; bottom: 12px; z-index: 85; width: min(360px, calc(100vw - 24px));
      background: var(--panel-glass, rgba(14,22,33,.92)); border: 2px solid #283c50; border-radius: 6px;
      color: var(--text, #e6edf5); font: 12px/1.35 Segoe UI, system-ui, sans-serif; box-shadow: 0 8px 24px rgba(0,0,0,.6); }
    .mesa-reclamos-cab { all: unset; cursor: pointer; display: block; width: 100%; box-sizing: border-box;
      padding: 6px 10px; font-weight: 600; letter-spacing: .03em; }
    .mesa-reclamos-cab:focus-visible { outline: 2px solid var(--gold, #f1cf85); }
    .mesa-reclamos-cuerpo { padding: 0 10px 8px; max-height: 40vh; overflow: auto; }
    .mr-sec { color: var(--muted, #8d9eb0); font-size: 11px; margin: 6px 0 3px; text-transform: uppercase; }
    .mr-fila { display: flex; gap: 6px; align-items: baseline; padding: 2px 0; }
    .mr-chip { flex: none; padding: 0 6px; border-radius: 3px; color: #0b1018; font-weight: 700; font-size: 11px; }
    .mr-chip.claude { background: var(--claude, #d27e67); } .mr-chip.codex { background: var(--codex, #5ed3a1); }
    .mr-chip.agy { background: var(--agy, #4285f4); color: #fff; } .mr-chip.otro { background: #8d9eb0; }
    .mr-txt { min-width: 0; overflow-wrap: anywhere; }
    .mr-toca { color: var(--muted, #8d9eb0); font-size: 11px; }
    .mr-choque { color: var(--bad, #f87171); font-weight: 600; }
    .mr-vacio { color: var(--muted, #8d9eb0); }
    .mr-estado { padding: 0 5px; border-radius: 3px; font-size: 10px; font-weight: 700; color: #0b1018; }
    .mr-estado.entregada { background: var(--gold, #f1cf85); } .mr-estado.aceptada { background: var(--teal, #6ee7b7); }
    .mr-estado.devuelta { background: var(--bad, #f87171); }
  `);

  const chip = (agente) => el('span', 'mr-chip ' + (AGENTES.includes(agente) ? agente : 'otro'), agente);

  function pintar(estado) {
    cuerpo.replaceChildren();
    pintarBandeja(estado);
    const limite = Date.now() - 6 * 3600 * 1000;
    const activos = (estado.hilos || []).filter((h) => h.estado !== 'cerrado' && Date.parse(h.actualizado) > limite);
    cuerpo.append(el('div', 'mr-sec', 'Líder por hilo activo (6 h)'));
    if (!activos.length) cuerpo.append(el('div', 'mr-vacio', 'Sin hilos activos'));
    for (const h of activos.slice(0, 5)) {
      const f = el('div', 'mr-fila');
      f.append(chip(normalizar(h.lider)), el('span', 'mr-txt', `${h.titulo || h.id} · ${hora(h.actualizado)}`));
      cuerpo.append(f);
    }

    const reclamos = (estado.reclamos || []).filter((r) => r && r.tarea !== 'lider');
    // Mismo archivo reclamado por agentes distintos = choque.
    const duenos = new Map();
    for (const r of reclamos) {
      for (const a of String(r.toca || '').split(/[,;]/).map((s) => s.trim().toLowerCase().replace(/\s*\(.*$/, '').replace(/:.*$/, '')).filter(Boolean)) {
        if (!duenos.has(a)) duenos.set(a, new Set());
        duenos.get(a).add(normalizar(r.agente));
      }
    }
    const choques = [...duenos].filter(([, s]) => s.size > 1);

    cuerpo.append(el('div', 'mr-sec', `Reclamos (${reclamos.length})`));
    if (!reclamos.length) cuerpo.append(el('div', 'mr-vacio', 'Nadie tiene nada reclamado'));
    for (const r of reclamos) {
      const f = el('div', 'mr-fila');
      const txt = el('span', 'mr-txt', `${r.tarea} · ${hora(r.fecha)}`);
      if (r.toca) { txt.append(document.createElement('br'), el('span', 'mr-toca', r.toca)); }
      f.append(chip(normalizar(r.agente)), txt);
      cuerpo.append(f);
    }
    for (const [archivo, s] of choques) {
      cuerpo.append(el('div', 'mr-choque', `⚠ ${archivo}: ${[...s].join(' y ')}`));
    }
  }

  // Va primero: es lo único que espera una acción del líder (solo hilos abiertos).
  function pintarBandeja(estado) {
    const hilosAbiertos = new Set((estado.hilos || []).filter((h) => h.estado === 'abierto').map((h) => h.id));
    const entregas = (estado.entregas || []).filter((e) => e && e.estado !== 'archivada' && (!e.hilo || hilosAbiertos.has(e.hilo)));
    cuerpo.append(el('div', 'mr-sec', `📥 Bandeja de entregas (${entregas.length})`));
    if (!entregas.length) cuerpo.append(el('div', 'mr-vacio', 'Bandeja vacía'));
    const ETIQUETA = { entregada: 'por revisar', aceptada: 'aceptada', devuelta: 'devuelta' };
    for (const e of entregas) {
      const f = el('div', 'mr-fila');
      const txt = el('span', 'mr-txt', `${e.tarea} · ronda ${e.ronda || 1} · ${hora(e.fecha)} `);
      txt.append(el('span', 'mr-estado ' + e.estado, ETIQUETA[e.estado] || e.estado));
      if (e.motivo) { txt.append(document.createElement('br'), el('span', 'mr-toca', e.motivo)); }
      f.append(chip(normalizar(e.autor)), txt);
      cuerpo.append(f);
    }
  }

  let tokenReclamos = window.__MESA_TOKEN__ || document.querySelector('meta[name="mesa-token"]')?.content || '';
  let lastEtagReclamos = null;
  async function refrescar() {
    try {
      if (!tokenReclamos) {
        tokenReclamos = window.__MESA_TOKEN__ || document.querySelector('meta[name="mesa-token"]')?.content || '';
      }
      const headers = { 'Cache-Control': 'no-cache' };
      if (tokenReclamos) headers['X-Mesa-Token'] = tokenReclamos;
      if (lastEtagReclamos) headers['If-None-Match'] = lastEtagReclamos;
      const r = await fetch('/api/estado', { headers });
      if (r.status === 304) return;
      if (r.ok) {
        const etag = r.headers.get('ETag');
        if (etag) lastEtagReclamos = etag;
        pintar(await r.json());
      }
    } catch {}
  }

  document.head.append(estilo);
  document.body.append(tarjeta);
  aplicarPliegue();
  refrescar();
  setInterval(refrescar, 15000);
})();
