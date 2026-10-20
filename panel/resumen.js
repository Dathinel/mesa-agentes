/**
 * Mesa de Agentes · Vista Resumen
 * Script de renderizado reactivo y accesible según docs\estado-contrato.md
 */

(() => {
  'use strict';

  // Configuración y estado global
  const REFRESH_INTERVAL_MS = 5000;
  let datosActuales = null;
  let timerActualizacion = null;

  // Recordar preferencia de vista
  try {
    localStorage.setItem('mesa_vista_preferida', 'resumen');
  } catch (_) {}

  // Contrato de los 6 estados oficiales
  const ESTADOS_CONTRATO = {
    'trabajando': {
      etiqueta: 'Trabajando',
      icono: '⚙️',
      clase: 'estado-trabajando'
    },
    'libre': {
      etiqueta: 'Libre',
      icono: '🟢',
      clase: 'estado-libre'
    },
    'esperando-daniel': {
      etiqueta: 'Esperando a Daniel',
      icono: '👤',
      clase: 'estado-esperando-daniel'
    },
    'sin-cuota': {
      etiqueta: 'Sin cuota',
      icono: '⏳',
      clase: 'estado-sin-cuota'
    },
    'caido': {
      etiqueta: 'Caído',
      icono: '🔴',
      clase: 'estado-caido'
    },
    'apagado': {
      etiqueta: 'Apagado',
      icono: '⚪',
      clase: 'estado-apagado'
    }
  };

  // Elementos del DOM
  const dom = {
    puntoFrescura: document.getElementById('punto-frescura'),
    textoFrescura: document.getElementById('texto-frescura'),
    alertaTrabajador: document.getElementById('alerta-trabajador'),
    btnCambiarVista: document.getElementById('btn-cambiar-vista'),
    btnTema: document.getElementById('btn-tema'),
    iconoTema: document.getElementById('icono-tema'),
    textoTema: document.getElementById('texto-tema'),
    relojVivo: document.getElementById('reloj-vivo'),
    cuadriculaAgentes: document.getElementById('cuadricula-agentes'),
    seccionTeNecesito: document.getElementById('seccion-te-necesito'),
    listaTeNecesito: document.getElementById('lista-te-necesito'),
    contadorTeNecesito: document.getElementById('contador-te-necesito'),
    listaHilos: document.getElementById('lista-hilos'),
    btnToggleDetalles: document.getElementById('btn-toggle-detalles'),
    panelDetalles: document.getElementById('panel-detalles-tecnicos'),
    cuerpoTablaMetricas: document.getElementById('cuerpo-tabla-metricas'),
    pistasTiempo: document.getElementById('pistas-tiempo'),
    listaReclamos: document.getElementById('lista-reclamos'),
    modalHilo: document.getElementById('modal-hilo'),
    modalHiloTitulo: document.getElementById('modal-hilo-titulo'),
    modalHiloSubtitulo: document.getElementById('modal-hilo-subtitulo'),
    modalHiloMensajes: document.getElementById('modal-hilo-mensajes'),
    btnCerrarModal: document.getElementById('btn-cerrar-modal'),
    btnCerrarModalPie: document.getElementById('btn-cerrar-modal-pie'),
    tostada: document.getElementById('tostada-aviso')
  };

  // =========================================================================
  // Inicialización
  // =========================================================================
  function inicializar() {
    configurarTema();
    configurarEventos();
    iniciarReloj();
    cargarDatos();
    timerActualizacion = setInterval(cargarDatos, REFRESH_INTERVAL_MS);
  }

  function configurarEventos() {
    // Alternar vista a Oficina y guardar preferencia
    dom.btnCambiarVista.addEventListener('click', () => {
      try {
        localStorage.setItem('mesa_vista_preferida', 'oficina');
      } catch (_) {}
      window.location.href = 'index.html';
    });

    // Alternar detalles técnicos
    dom.btnToggleDetalles.addEventListener('click', () => {
      const estaOculto = dom.panelDetalles.hidden;
      dom.panelDetalles.hidden = !estaOculto;
      dom.btnToggleDetalles.setAttribute('aria-expanded', String(estaOculto));
      const texto = dom.btnToggleDetalles.querySelector('span:last-child');
      if (texto) {
        texto.textContent = estaOculto
          ? 'Ocultar detalles técnicos'
          : 'Mostrar detalles técnicos (tokens, modelos, caché y telemetría)';
      }
    });

    // Modal de hilo
    dom.btnCerrarModal.addEventListener('click', cerrarModalHilo);
    dom.btnCerrarModalPie.addEventListener('click', cerrarModalHilo);
    dom.modalHilo.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') cerrarModalHilo();
    });

    // Tema
    dom.btnTema.addEventListener('click', alternarTema);
  }

  // =========================================================================
  // Gestión de Temas (Claro / Oscuro)
  // =========================================================================
  function configurarTema() {
    let temaGuardado = 'oscuro';
    try {
      temaGuardado = localStorage.getItem('mesa_tema') || 'oscuro';
    } catch (_) {}
    aplicarTema(temaGuardado);
  }

  function aplicarTema(tema) {
    document.documentElement.setAttribute('data-tema', tema);
    try {
      localStorage.setItem('mesa_tema', tema);
    } catch (_) {}

    if (tema === 'claro') {
      dom.iconoTema.textContent = '🌙';
      dom.textoTema.textContent = 'Tema Oscuro';
    } else {
      dom.iconoTema.textContent = '☀️';
      dom.textoTema.textContent = 'Tema Claro';
    }
  }

  function alternarTema() {
    const temaActual = document.documentElement.getAttribute('data-tema') || 'oscuro';
    aplicarTema(temaActual === 'oscuro' ? 'claro' : 'oscuro');
  }

  // =========================================================================
  // Reloj en tiempo real
  // =========================================================================
  function iniciarReloj() {
    function actualizarReloj() {
      const ahora = new Date();
      dom.relojVivo.textContent = ahora.toLocaleTimeString('es-ES', { hour12: false });
      dom.relojVivo.title = ahora.toISOString();
      if (datosActuales) {
        actualizarFranjaFrescura(datosActuales);
      }
    }
    actualizarReloj();
    setInterval(actualizarReloj, 1000);
  }

  // =========================================================================
  // Carga de Datos Resiliente
  // =========================================================================
  async function cargarDatos() {
    const params = new URLSearchParams(window.location.search);
    const forzarEjemplo = params.get('fuente') === 'ejemplo' || params.get('mock') === '1' || window.location.protocol === 'file:';

    let datos = null;

    if (!forzarEjemplo) {
      try {
        const token = params.get('token') || (typeof window.__MESA_TOKEN__ !== 'undefined' ? window.__MESA_TOKEN__ : null) || localStorage.getItem('mesa_token');
        const headers = { 'Cache-Control': 'no-cache' };
        if (token) {
          headers['X-Mesa-Token'] = token;
        }
        const resp = await fetch('/api/estado', { headers });
        if (resp.ok) {
          datos = await resp.json();
        }
      } catch (err) {
        // En caso de fallo o si el servidor no está en ejecución, se usa resumen-ejemplo.json
      }
    }

    if (!datos) {
      try {
        const respMock = await fetch('resumen-ejemplo.json', { cache: 'no-cache' });
        if (respMock.ok) {
          datos = await respMock.json();
        }
      } catch (errMock) {
        console.error('No se pudo cargar resumen-ejemplo.json:', errMock);
      }
    }

    if (datos) {
      datosActuales = datos;
      renderizarVista(datos);
    } else {
      dom.textoFrescura.textContent = 'Sin datos disponibles';
      dom.puntoFrescura.className = 'punto-frescura frescura-rojo';
    }
  }

  // =========================================================================
  // Renderizado Principal
  // =========================================================================
  function renderizarVista(datos) {
    actualizarFranjaFrescura(datos);
    renderizarTarjetasAgentes(datos);
    renderizarTeNecesito(datos);
    renderizarHilos(datos);
    renderizarDetallesTecnicos(datos);
    ejecutarDiagnosticoAccesibilidad();
  }

  // =========================================================================
  // Diagnóstico automático de Accesibilidad y Dimensiones
  // =========================================================================
  function ejecutarDiagnosticoAccesibilidad() {
    try {
      const docEl = document.documentElement;
      const scrollWidth = docEl.scrollWidth;
      const clientWidth = docEl.clientWidth;
      const tieneScrollHorizontal = scrollWidth > clientWidth;

      let minFontSize = 999;
      const elementos = document.querySelectorAll('body, body *');
      elementos.forEach(el => {
        if (el.offsetParent !== null && el.childNodes.length > 0) {
          const tieneTexto = Array.from(el.childNodes).some(n => n.nodeType === 3 && n.textContent.trim().length > 0);
          if (tieneTexto) {
            const fs = parseFloat(window.getComputedStyle(el).fontSize);
            if (!isNaN(fs) && fs > 0 && fs < minFontSize) {
              minFontSize = fs;
            }
          }
        }
      });

      document.body.dataset.clientWidth = clientWidth;
      document.body.dataset.scrollWidth = scrollWidth;
      document.body.dataset.hasHscroll = tieneScrollHorizontal ? 'true' : 'false';
      document.body.dataset.minFontSize = minFontSize < 999 ? minFontSize : 14;
    } catch (_) {}
  }

  // =========================================================================
  // Franja Superior de Frescura
  // =========================================================================
  function actualizarFranjaFrescura(datos) {
    const timestampStr = datos.generado || datos.actualizado;
    if (!timestampStr) {
      dom.textoFrescura.textContent = 'Datos disponibles (sin fecha)';
      dom.puntoFrescura.className = 'punto-frescura';
      return;
    }

    const fechaGen = new Date(timestampStr);
    const ahora = new Date();
    const difSegundos = Math.max(0, Math.floor((ahora - fechaGen) / 1000));

    let texto = `Datos de hace ${difSegundos} s`;
    if (difSegundos >= 60) {
      const min = Math.floor(difSegundos / 60);
      texto = `Datos de hace ${min} min`;
    }

    dom.textoFrescura.textContent = texto;
    dom.textoFrescura.title = `Generado el ${fechaGen.toLocaleString('es-ES')}`;

    // Regla de color: ámbar pasado 1 min (>60s), rojo pasados 3 min (>180s)
    dom.puntoFrescura.className = 'punto-frescura';
    if (difSegundos > 180) {
      dom.puntoFrescura.classList.add('frescura-rojo');
    } else if (difSegundos > 60) {
      dom.puntoFrescura.classList.add('frescura-ambar');
    }

    // Error del trabajador
    if (datos.error_trabajador) {
      dom.alertaTrabajador.hidden = false;
      dom.alertaTrabajador.textContent = `⚠️ Error del trabajador: ${datos.error_trabajador}`;
    } else {
      dom.alertaTrabajador.hidden = true;
      dom.alertaTrabajador.textContent = '';
    }
  }

  // =========================================================================
  // Tarjetas de Agentes (Claude, Codex, agy)
  // =========================================================================
  function renderizarTarjetasAgentes(datos) {
    const agentesList = normalizarListaAgentes(datos);
    const hilosAbiertos = (datos.hilos || []).filter(h => h.estado === 'abierto');

    dom.cuadriculaAgentes.innerHTML = '';

    agentesList.forEach(agente => {
      const id = (agente.agente || agente.id || agente.nombre || '').toLowerCase();
      const nombre = agente.nombre || capitalize(id) || '—';
      const estadoClave = (agente.estado || '').toLowerCase().trim();
      const configEstado = ESTADOS_CONTRATO[estadoClave] || {
        etiqueta: estadoClave || 'Desconocido',
        icono: '❓',
        clase: 'estado-apagado'
      };

      const motivo = agente.motivo || agente.plan || '—';
      const esLider = hilosAbiertos.some(h => (h.lider || '').toLowerCase() === id);

      // Tarjeta HTML
      const tarjeta = document.createElement('article');
      tarjeta.className = 'tarjeta-agente';
      tarjeta.id = `tarjeta-${id}`;

      // Cabecera de tarjeta
      const cabecera = document.createElement('div');
      cabecera.className = 'tarjeta-cabecera';

      const identidad = document.createElement('div');
      identidad.className = 'tarjeta-identidad';

      const avatar = document.createElement('div');
      avatar.className = `avatar-agente avatar-${id}`;
      avatar.textContent = nombre.charAt(0).toUpperCase();
      avatar.setAttribute('aria-hidden', 'true');

      const tituloNombre = document.createElement('h3');
      tituloNombre.className = 'nombre-agente';
      tituloNombre.textContent = nombre;

      identidad.appendChild(avatar);
      identidad.appendChild(tituloNombre);
      cabecera.appendChild(identidad);

      if (esLider) {
        const badgeLider = document.createElement('span');
        badgeLider.className = 'insignia-lider';
        badgeLider.textContent = '👑 Líder';
        badgeLider.title = 'Este agente es líder en al menos un hilo abierto';
        cabecera.appendChild(badgeLider);
      }

      // Cuerpo de tarjeta
      const cuerpo = document.createElement('div');
      cuerpo.className = 'tarjeta-cuerpo';

      // Badge de estado: icono + texto + clase de color (nunca solo color)
      const badgeEstado = document.createElement('div');
      badgeEstado.className = `badge-estado ${configEstado.clase}`;
      badgeEstado.innerHTML = `<span class="icono-estado" aria-hidden="true">${configEstado.icono}</span> <span>${configEstado.etiqueta}</span>`;
      cuerpo.appendChild(badgeEstado);

      // Motivo
      const campoMotivo = document.createElement('div');
      campoMotivo.className = 'campo-motivo';
      const labelMotivo = document.createElement('span');
      labelMotivo.className = 'motivo-etiqueta';
      labelMotivo.textContent = 'Motivo:';
      const textoMotivo = document.createElement('span');
      textoMotivo.className = 'motivo-texto';
      textoMotivo.textContent = ` ${motivo}`;
      campoMotivo.appendChild(labelMotivo);
      campoMotivo.appendChild(textoMotivo);
      cuerpo.appendChild(campoMotivo);

      // Alerta visible si la tiene
      if (agente.alerta) {
        const alertaDiv = document.createElement('div');
        alertaDiv.className = 'alerta-tarjeta';
        const tipoAlerta = agente.alerta.tipo || 'alerta';
        const textoAlerta = agente.alerta.texto || JSON.stringify(agente.alerta);
        alertaDiv.innerHTML = `<span aria-hidden="true">⚠️</span> <span>[${escaparHtml(tipoAlerta)}] ${escaparHtml(textoAlerta)}</span>`;
        cuerpo.appendChild(alertaDiv);
      }

      // Pie de tarjeta con tiempos y latidos
      const pie = document.createElement('div');
      pie.className = 'tarjeta-pie';

      let textoTiempo = '—';
      let titleTiempo = '';

      if (estadoClave === 'sin-cuota' && agente.hasta) {
        const hastaFecha = new Date(agente.hasta);
        textoTiempo = `Vuelve: ${horaCorta(hastaFecha)}`;
        titleTiempo = `Sin cuota hasta ${hastaFecha.toLocaleString('es-ES')}`;
      } else if (agente.desde) {
        const desdeFecha = new Date(agente.desde);
        textoTiempo = `Desde ${tiempoRelativo(desdeFecha)}`;
        titleTiempo = `Inicio del estado: ${desdeFecha.toLocaleString('es-ES')}`;
      } else if (agente.actualizado) {
        const actFecha = new Date(agente.actualizado);
        textoTiempo = `Act. ${tiempoRelativo(actFecha)}`;
        titleTiempo = `Última actualización: ${actFecha.toLocaleString('es-ES')}`;
      }

      const spanTiempo = document.createElement('span');
      spanTiempo.className = 'tiempo-estado';
      spanTiempo.textContent = textoTiempo;
      spanTiempo.title = titleTiempo;

      const spanLatido = document.createElement('span');
      if (agente.latido) {
        const latidoFecha = new Date(agente.latido);
        spanLatido.textContent = `Latido: ${tiempoRelativo(latidoFecha)}`;
        spanLatido.title = `Latido del proceso: ${latidoFecha.toLocaleString('es-ES')}`;
      } else {
        spanLatido.textContent = 'Latido: —';
      }

      pie.appendChild(spanTiempo);
      pie.appendChild(spanLatido);

      tarjeta.appendChild(cabecera);
      tarjeta.appendChild(cuerpo);
      tarjeta.appendChild(pie);

      dom.cuadriculaAgentes.appendChild(tarjeta);
    });
  }

  // =========================================================================
  // Sección: Te Necesito (3 Partes + Copiar orden exacta)
  // =========================================================================
  function renderizarTeNecesito(datos) {
    const agentesList = normalizarListaAgentes(datos);
    const incidencias = [];

    // 1. Incidencias explícitas en el json (si vienen provistas)
    if (Array.isArray(datos.te_necesito)) {
      datos.te_necesito.forEach(tn => incidencias.push(tn));
    }

    // 2. Agentes caídos o esperando a Daniel
    agentesList.forEach(ag => {
      const id = (ag.agente || ag.id || '').toLowerCase();
      const estado = (ag.estado || '').toLowerCase();
      if (estado === 'caido') {
        const yaExiste = incidencias.some(i => i.agente === id && i.tipo === 'caido');
        if (!yaExiste) {
          incidencias.push({
            id: `caido-${id}`,
            tipo: 'caido',
            agente: id,
            titulo: `Panel de ${capitalize(id)} caído`,
            paso: `El panel de ${capitalize(id)} no reporta latido reciente o su proceso no está activo.`,
            hizo: `El supervisor marcó el estado a 'caido' para evitar enviar nuevas tareas no atendidas.`,
            necesita: `Arrancar o continuar la sesión de ${capitalize(id)}.`,
            orden: `powershell -ExecutionPolicy Bypass -File .\\herramientas\\trabajador.ps1 -Agente ${id}`
          });
        }
      } else if (estado === 'esperando-daniel') {
        const yaExiste = incidencias.some(i => i.agente === id && i.tipo === 'esperando-daniel');
        if (!yaExiste) {
          incidencias.push({
            id: `esperando-${id}`,
            tipo: 'esperando-daniel',
            agente: id,
            titulo: `${capitalize(id)} requiere intervención de Daniel`,
            paso: ag.motivo || `El encargo se encuentra escalado tras agotar reintentos o necesita login.`,
            hizo: `El sistema detuvo el encargo y notificó a la mesa sin reintentar automáticamente.`,
            necesita: `Revisar el hilo activo y dar respuesta o nueva instrucción.`,
            orden: ag.hilo
              ? `powershell -ExecutionPolicy Bypass -File .\\herramientas\\mesa.ps1 leer -Hilo ${ag.hilo}`
              : `powershell -ExecutionPolicy Bypass -File .\\herramientas\\mesa.ps1 pendientes -Para ${id}`
          });
        }
      }
    });

    // 3. Alertas de seguridad altas sin revisar
    if (Array.isArray(datos.alertas)) {
      datos.alertas.filter(a => a.nivel === 'alto' && !a.revisada).forEach(al => {
        const yaExiste = incidencias.some(i => i.id === al.id);
        if (!yaExiste) {
          incidencias.push({
            id: al.id,
            tipo: 'alerta-alta',
            agente: al.agente || 'sistema',
            titulo: `Alerta alta sin revisar: ${al.motivo || 'Acción peligrosa'}`,
            paso: `El vigía detectó: ${al.motivo || 'comando no permitido'}.`,
            hizo: `Se bloqueó la ejecución de la orden sospechosa y se registró la alerta.`,
            necesita: `Revisar los argumentos y marcar la alerta en la mesa.`,
            orden: `powershell -ExecutionPolicy Bypass -File .\\herramientas\\mesa.ps1 revisar-alerta -Id ${al.id}`
          });
        }
      });
    }

    // 4. Aprobaciones / traspasos pendientes
    if (Array.isArray(datos.pendientes)) {
      datos.pendientes.forEach((p, idx) => {
        if (p.texto && (p.texto.includes('ESCALADO') || p.texto.includes('aprobación'))) {
          incidencias.push({
            id: `pend-${idx}`,
            tipo: 'aprobacion',
            agente: p.autor || 'sistema',
            titulo: `Aprobación pendiente de ${p.autor || 'agente'}`,
            paso: p.texto,
            hizo: `El agente está a la espera de confirmación.`,
            necesita: `Aprobar o rechazar el avance en el hilo.`,
            orden: `powershell -ExecutionPolicy Bypass -File .\\herramientas\\mesa.ps1 pendientes -Para daniel`
          });
        }
      });
    }

    // Actualizar contador y estilos de la sección
    dom.contadorTeNecesito.textContent = incidencias.length;
    if (incidencias.length === 0) {
      dom.contadorTeNecesito.className = 'contador-insignia cero';
      dom.seccionTeNecesito.classList.remove('tiene-incidencias');
      dom.listaTeNecesito.innerHTML = `
        <div class="panel-vacio" id="te-necesito-vacio">
          <span class="icono-ok" aria-hidden="true">✓</span>
          <p class="texto-vacio">Todo en orden. No hay bloqueos que requieran tu intervención.</p>
        </div>
      `;
      return;
    }

    dom.contadorTeNecesito.className = 'contador-insignia';
    dom.seccionTeNecesito.classList.add('tiene-incidencias');
    dom.listaTeNecesito.innerHTML = '';

    incidencias.forEach(inc => {
      const art = document.createElement('article');
      art.className = 'tarjeta-incidencia';

      // Cabecera de incidencia
      const cabecera = document.createElement('div');
      cabecera.className = 'incidencia-cabecera';
      cabecera.innerHTML = `
        <h3 class="incidencia-titulo">${escaparHtml(inc.titulo || 'Incidencia de Atención')}</h3>
        <span class="incidencia-agente-badge">${escaparHtml(capitalize(inc.agente || 'Mesa'))}</span>
      `;

      // Cuadrícula con las 3 partes obligatorias:
      // 1. Qué pasó | 2. Qué hizo el sistema | 3. Qué necesita
      const grid3 = document.createElement('div');
      grid3.className = 'incidencia-grid-3partes';
      grid3.innerHTML = `
        <div class="incidencia-parte">
          <span class="parte-etiqueta">1. Qué pasó</span>
          <span class="parte-valor">${escaparHtml(inc.paso || '—')}</span>
        </div>
        <div class="incidencia-parte">
          <span class="parte-etiqueta">2. Qué hizo el sistema</span>
          <span class="parte-valor">${escaparHtml(inc.hizo || '—')}</span>
        </div>
        <div class="incidencia-parte">
          <span class="parte-etiqueta">3. Qué necesita</span>
          <span class="parte-valor">${escaparHtml(inc.necesita || '—')}</span>
        </div>
      `;

      // Zona de acción con orden y botón Copiar
      const accion = document.createElement('div');
      accion.className = 'incidencia-accion';

      const codigoOrden = document.createElement('code');
      codigoOrden.className = 'incidencia-orden-codigo';
      codigoOrden.textContent = inc.orden || '—';

      const btnCopiar = document.createElement('button');
      btnCopiar.type = 'button';
      btnCopiar.className = 'btn-copiar';
      btnCopiar.innerHTML = `📋 Copiar orden`;
      btnCopiar.title = 'Copiar orden de resolución al portapapeles';

      btnCopiar.addEventListener('click', () => {
        if (inc.orden) {
          copiarAlPortapapeles(inc.orden, btnCopiar);
        }
      });

      accion.appendChild(codigoOrden);
      accion.appendChild(btnCopiar);

      art.appendChild(cabecera);
      art.appendChild(grid3);
      art.appendChild(accion);

      dom.listaTeNecesito.appendChild(art);
    });
  }

  // =========================================================================
  // Sección: Hilos Abiertos
  // =========================================================================
  function renderizarHilos(datos) {
    const hilos = Array.isArray(datos.hilos) ? datos.hilos : [];
    const abiertos = hilos.filter(h => h.estado === 'abierto');

    if (abiertos.length === 0) {
      dom.listaHilos.innerHTML = '<p class="texto-vacio">No hay hilos abiertos actualmente.</p>';
      return;
    }

    dom.listaHilos.innerHTML = '';

    abiertos.forEach(hilo => {
      const item = document.createElement('div');
      item.className = 'item-hilo';
      item.tabIndex = 0;
      item.setAttribute('role', 'button');
      item.setAttribute('aria-label', `Ver conversación del hilo ${hilo.titulo || hilo.id}`);

      const infoPrincipal = document.createElement('div');
      infoPrincipal.className = 'hilo-info-principal';

      const lineaTitulo = document.createElement('div');
      lineaTitulo.className = 'hilo-titulo-linea';

      const titulo = document.createElement('h3');
      titulo.className = 'hilo-titulo';
      titulo.textContent = hilo.titulo || hilo.id;

      const liderBadge = document.createElement('span');
      liderBadge.className = 'hilo-lider-badge';
      liderBadge.textContent = `Líder: ${capitalize(hilo.lider || '—')}`;

      lineaTitulo.appendChild(titulo);
      lineaTitulo.appendChild(liderBadge);

      // Última novedad en una frase
      const novedad = document.createElement('p');
      novedad.className = 'hilo-novedad';
      let textoNovedad = 'Sin mensajes registrados';
      if (hilo.ultimo_mensaje && hilo.ultimo_mensaje.texto) {
        const autorMsg = hilo.ultimo_mensaje.autor ? `${hilo.ultimo_mensaje.autor}: ` : '';
        textoNovedad = `${autorMsg}${hilo.ultimo_mensaje.texto}`;
      }
      novedad.textContent = textoNovedad;

      infoPrincipal.appendChild(lineaTitulo);
      infoPrincipal.appendChild(novedad);

      // Hace cuánto tiempo
      const tiempoMeta = document.createElement('div');
      tiempoMeta.className = 'hilo-tiempo-meta';

      const fechaActualizacion = hilo.ultimo_mensaje?.fecha || hilo.actualizado;
      if (fechaActualizacion) {
        const d = new Date(fechaActualizacion);
        const spanTiempo = document.createElement('span');
        spanTiempo.textContent = tiempoRelativo(d);
        spanTiempo.title = `Actualizado: ${d.toLocaleString('es-ES')}`;
        tiempoMeta.appendChild(spanTiempo);
      } else {
        const spanTiempo = document.createElement('span');
        spanTiempo.textContent = '—';
        tiempoMeta.appendChild(spanTiempo);
      }

      const flecha = document.createElement('span');
      flecha.textContent = '›';
      flecha.style.fontSize = '18px';
      flecha.setAttribute('aria-hidden', 'true');
      tiempoMeta.appendChild(flecha);

      item.appendChild(infoPrincipal);
      item.appendChild(tiempoMeta);

      const abrirDetalle = () => mostrarModalHilo(hilo);
      item.addEventListener('click', abrirDetalle);
      item.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          abrirDetalle();
        }
      });

      dom.listaHilos.appendChild(item);
    });
  }

  // =========================================================================
  // Modal de Detalle de Hilo
  // =========================================================================
  async function mostrarModalHilo(hilo) {
    dom.modalHiloTitulo.textContent = hilo.titulo || hilo.id;
    dom.modalHiloSubtitulo.textContent = `Líder: ${capitalize(hilo.lider || '—')} · Participantes: ${(hilo.participantes || []).join(', ') || '—'}`;
    dom.modalHiloMensajes.innerHTML = '<p>Cargando mensajes...</p>';
    dom.modalHilo.showModal();

    let mensajes = Array.isArray(hilo.mensajes) && hilo.mensajes.length > 0 ? hilo.mensajes : null;

    if (!mensajes) {
      try {
        const resp = await fetch(`/api/hilo?id=${encodeURIComponent(hilo.id)}`, { cache: 'no-cache' });
        if (resp.ok) {
          const datosHilo = await resp.json();
          if (Array.isArray(datosHilo.mensajes)) {
            mensajes = datosHilo.mensajes;
          }
        }
      } catch (_) {}
    }

    if (!mensajes || mensajes.length === 0) {
      if (hilo.ultimo_mensaje) {
        mensajes = [hilo.ultimo_mensaje];
      } else {
        dom.modalHiloMensajes.innerHTML = '<p>No hay mensajes guardados en este hilo.</p>';
        return;
      }
    }

    dom.modalHiloMensajes.innerHTML = '';
    mensajes.forEach((msg, idx) => {
      const msgDiv = document.createElement('div');
      msgDiv.className = 'modal-mensaje';

      const autor = msg.autor || msg.de || 'sistema';
      const fecha = msg.fecha ? new Date(msg.fecha).toLocaleString('es-ES') : '';
      const tipo = msg.tipo ? `[${msg.tipo}]` : '';

      msgDiv.innerHTML = `
        <div class="modal-mensaje-cabecera">
          <span>#${msg.n || idx + 1} · ${escaparHtml(capitalize(autor))} ${escaparHtml(tipo)}</span>
          <span title="${fecha}">${msg.fecha ? tiempoRelativo(new Date(msg.fecha)) : ''}</span>
        </div>
        <div class="modal-mensaje-texto">${escaparHtml(msg.texto || '—')}</div>
      `;

      dom.modalHiloMensajes.appendChild(msgDiv);
    });
  }

  function cerrarModalHilo() {
    dom.modalHilo.close();
  }

  // =========================================================================
  // Sección 4: Detalles Técnicos (Tokens, Modelos, Caché, Línea de Tiempo)
  // =========================================================================
  function renderizarDetallesTecnicos(datos) {
    const agentesList = normalizarListaAgentes(datos);

    // 1. Tabla de Métricas
    dom.cuerpoTablaMetricas.innerHTML = '';
    agentesList.forEach(ag => {
      const nombre = ag.nombre || capitalize(ag.agente || ag.id || '—');
      const modelo = ag.modelo || ag.modelo_exacto || '—';
      const fuente = ag.modelo_fuente ? ` (${ag.modelo_fuente})` : '';
      const st = ag.estadisticas || {};

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${escaparHtml(nombre)}</strong></td>
        <td><code>${escaparHtml(modelo + fuente)}</code></td>
        <td>${formatearNumero(st.tokens_hoy)}</td>
        <td>${formatearNumero(st.tokens_5h)}</td>
        <td>${formatearNumero(st.tokens_7d)}</td>
        <td>${formatearNumero(st.cache_read_hoy || st.cache_read_7d)}</td>
        <td>${st.tasa != null ? `${st.tasa}%` : '—'}</td>
      `;
      dom.cuerpoTablaMetricas.appendChild(tr);
    });

    // 2. Línea de tiempo diaria
    dom.pistasTiempo.innerHTML = '';
    const lt = Array.isArray(datos.linea_tiempo) ? datos.linea_tiempo : [];
    if (lt.length === 0) {
      dom.pistasTiempo.innerHTML = '<p class="texto-vacio">No hay datos de línea de tiempo disponibles.</p>';
    } else {
      lt.forEach(pista => {
        const divPista = document.createElement('div');
        divPista.className = 'pista-agente';

        const nombreSpan = document.createElement('span');
        nombreSpan.className = 'pista-nombre';
        nombreSpan.textContent = pista.nombre || capitalize(pista.id || '—');

        const carril = document.createElement('div');
        carril.className = 'pista-carril';

        const tramos = Array.isArray(pista.tramos) ? pista.tramos : [];
        tramos.forEach(tramo => {
          const bloque = document.createElement('div');
          bloque.className = 'tramo-activo';
          bloque.style.backgroundColor = pista.color || '#38bdf8';
          bloque.style.left = `${Math.max(0, Math.min(100, tramo.inicio_pct || 0))}%`;
          bloque.style.width = `${Math.max(1, Math.min(100, tramo.ancho_pct || 2))}%`;
          bloque.title = `${tramo.inicio || '00:00'} - ${tramo.fin || '24:00'}`;
          carril.appendChild(bloque);
        });

        divPista.appendChild(nombreSpan);
        divPista.appendChild(carril);
        dom.pistasTiempo.appendChild(divPista);
      });
    }

    // 3. Reclamos activos
    dom.listaReclamos.innerHTML = '';
    const reclamos = Array.isArray(datos.reclamos) ? datos.reclamos : [];
    if (reclamos.length === 0) {
      dom.listaReclamos.innerHTML = '<p class="texto-vacio">No hay reclamos de archivos activos.</p>';
    } else {
      reclamos.forEach(rec => {
        const recDiv = document.createElement('div');
        recDiv.className = 'item-reclamo';
        recDiv.innerHTML = `
          <div><strong>${escaparHtml(rec.tarea || 'tarea')}</strong> (${escaparHtml(rec.agente || '—')}): <code>${escaparHtml(rec.toca || '—')}</code></div>
          <div title="${escaparHtml(rec.fecha || '')}">${rec.fecha ? tiempoRelativo(new Date(rec.fecha)) : '—'}</div>
        `;
        dom.listaReclamos.appendChild(recDiv);
      });
    }
  }

  // =========================================================================
  // Utilidades y Helpers
  // =========================================================================
  function normalizarListaAgentes(datos) {
    if (!datos) return [];
    if (Array.isArray(datos.agentes)) {
      // Asegurar que contenga claude, codex y agy en orden estándar
      return datos.agentes;
    }
    return [];
  }

  function tiempoRelativo(fecha) {
    if (!fecha || isNaN(fecha.getTime())) return '—';
    const ahora = new Date();
    const difSegundos = Math.floor((ahora - fecha) / 1000);

    if (difSegundos < 5) return 'hace un momento';
    if (difSegundos < 60) return `hace ${difSegundos} s`;
    const min = Math.floor(difSegundos / 60);
    if (min < 60) return `hace ${min} min`;
    const horas = Math.floor(min / 60);
    if (horas < 24) return `hace ${horas} h`;
    const dias = Math.floor(horas / 24);
    return `hace ${dias} d`;
  }

  function horaCorta(fecha) {
    if (!fecha || isNaN(fecha.getTime())) return '—';
    return fecha.toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit', hour12: false });
  }

  function formatearNumero(num) {
    if (num == null || isNaN(num)) return '—';
    return Number(num).toLocaleString('es-ES');
  }

  function capitalize(str) {
    if (!str) return '';
    return str.charAt(0).toUpperCase() + str.slice(1);
  }

  function escaparHtml(str) {
    if (str == null) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function copiarAlPortapapeles(texto, boton) {
    if (!navigator.clipboard) {
      const ta = document.createElement('textarea');
      ta.value = texto;
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand('copy');
        mostrarAvisoCopiado(boton);
      } catch (_) {}
      document.body.removeChild(ta);
      return;
    }
    navigator.clipboard.writeText(texto).then(() => {
      mostrarAvisoCopiado(boton);
    }).catch(err => {
      console.error('Error al copiar al portapapeles:', err);
    });
  }

  function mostrarAvisoCopiado(boton) {
    const textoOriginal = boton.innerHTML;
    boton.innerHTML = '✓ ¡Copiado!';
    boton.style.borderColor = '#10b981';
    dom.tostada.hidden = false;

    setTimeout(() => {
      boton.innerHTML = textoOriginal;
      boton.style.borderColor = '';
    }, 2000);

    setTimeout(() => {
      dom.tostada.hidden = true;
    }, 2500);
  }

  // Arrancar en cuanto el DOM esté listo
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inicializar);
  } else {
    inicializar();
  }

  // Exportar para pruebas automatizadas
  window.__MesaResumen = {
    ESTADOS_CONTRATO,
    renderizarVista,
    tiempoRelativo,
    normalizarListaAgentes
  };
})();
