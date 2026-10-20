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
    tostada: document.getElementById('tostada-aviso'),
    badgeDemostracion: document.getElementById('badge-demostracion')
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
      window.location.href = '/oficina.html';
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
  let origenDatos = 'mesa';
  let ultimoDatoReal = null;

  try {
    const guardado = sessionStorage.getItem('mesa_ultimo_estado_real');
    if (guardado) {
      ultimoDatoReal = JSON.parse(guardado);
    }
  } catch (_) {}

  function mostrarAvisoDemostracion(mostrar) {
    if (dom.badgeDemostracion) {
      dom.badgeDemostracion.hidden = !mostrar;
    }
  }

  function renderizarSinConexion() {
    dom.textoFrescura.textContent = 'Sin conexión con la mesa';
    dom.puntoFrescura.className = 'punto-frescura frescura-rojo';
    dom.alertaTrabajador.hidden = true;

    dom.cuadriculaAgentes.innerHTML = `
      <div class="panel-vacio" style="grid-column: 1 / -1; padding: 2.5rem 1rem; text-align: center;">
        <span class="icono-atencion" aria-hidden="true" style="font-size: 28px; display: block; margin-bottom: 0.5rem;">⚠️</span>
        <h3 style="font-size: 18px; margin: 0 0 0.5rem 0; color: var(--texto-principal);">Sin conexión con la mesa</h3>
        <p class="texto-vacio" style="font-size: 14px; margin: 0;">No se reciben datos del servidor de la mesa ni hay registros previos en esta sesión.</p>
      </div>
    `;

    dom.contadorTeNecesito.textContent = '—';
    dom.contadorTeNecesito.className = 'contador-insignia cero';
    dom.seccionTeNecesito.classList.remove('tiene-incidencias');
    dom.listaTeNecesito.innerHTML = `
      <div class="panel-vacio">
        <p class="texto-vacio" style="font-size: 14px;">Sin conexión con la mesa.</p>
      </div>
    `;

    dom.listaHilos.innerHTML = '<p class="texto-vacio" style="font-size: 14px; padding: 1.5rem 0;">Sin conexión con la mesa.</p>';
    dom.cuerpoTablaMetricas.innerHTML = '';
    dom.pistasTiempo.innerHTML = '<p class="texto-vacio" style="font-size: 14px; padding: 1.5rem 0;">Sin conexión con la mesa.</p>';
    dom.listaReclamos.innerHTML = '<p class="texto-vacio" style="font-size: 14px; padding: 1.5rem 0;">Sin conexión con la mesa.</p>';

    ejecutarDiagnosticoAccesibilidad();
  }

  async function cargarDatos() {
    const params = new URLSearchParams(window.location.search);
    const soloEjemplo = params.get('ejemplo') === '1';

    if (soloEjemplo) {
      origenDatos = 'ejemplo';
      mostrarAvisoDemostracion(true);
      try {
        const respMock = await fetch('resumen-ejemplo.json', { cache: 'no-cache' });
        if (respMock.ok) {
          datosActuales = await respMock.json();
          renderizarVista(datosActuales);
          return;
        }
      } catch (errMock) {
        console.error('No se pudo cargar resumen-ejemplo.json:', errMock);
      }
      dom.textoFrescura.textContent = 'DEMOSTRACIÓN · Error cargando ejemplo';
      dom.puntoFrescura.className = 'punto-frescura frescura-rojo';
      return;
    }

    mostrarAvisoDemostracion(false);

    let datos = null;
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
      // Sin conexión con la mesa
    }

    if (datos) {
      origenDatos = 'mesa';
      ultimoDatoReal = datos;
      try {
        sessionStorage.setItem('mesa_ultimo_estado_real', JSON.stringify(datos));
      } catch (_) {}
      datosActuales = datos;
      renderizarVista(datos);
    } else if (ultimoDatoReal) {
      origenDatos = 'desconectado-con-cache';
      datosActuales = ultimoDatoReal;
      renderizarVista(ultimoDatoReal);
    } else {
      origenDatos = 'desconectado-sin-datos';
      datosActuales = null;
      renderizarSinConexion();
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
    if (origenDatos === 'ejemplo') {
      dom.textoFrescura.textContent = 'DEMOSTRACIÓN · Datos de ejemplo (?ejemplo=1)';
      dom.puntoFrescura.className = 'punto-frescura frescura-ambar';
      dom.alertaTrabajador.hidden = true;
      return;
    }

    if (origenDatos === 'desconectado-con-cache') {
      const timestampStr = datos ? (datos.generado || datos.actualizado) : null;
      const fechaGen = timestampStr ? new Date(timestampStr) : new Date();
      const difSegundos = Math.max(0, Math.floor((Date.now() - fechaGen.getTime()) / 1000));
      const min = Math.floor(difSegundos / 60);
      const textoAntiguedad = min > 0 ? `${min} min` : `${difSegundos} s`;
      dom.textoFrescura.textContent = `Sin conexión · último dato hace ${textoAntiguedad}`;
      dom.textoFrescura.title = timestampStr ? `Último dato real recibido el ${fechaGen.toLocaleString('es-ES')}` : '';
      dom.puntoFrescura.className = 'punto-frescura frescura-rojo';
      dom.alertaTrabajador.hidden = true;
      return;
    }

    const timestampStr = datos ? (datos.generado || datos.actualizado) : null;
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

    const params = new URLSearchParams(window.location.search);
    const abrirProcesosParam = (params.get('abrir-procesos') || '').toLowerCase();

    // Guardar qué tarjetas tenían el desplegable de procesos abierto para preservarlo entre recargas
    const abiertosPrevios = new Set();
    dom.cuadriculaAgentes.querySelectorAll('.tarjeta-agente').forEach(t => {
      const d = t.querySelector('.desplegable-procesos');
      if (d && d.open) {
        abiertosPrevios.add(t.id);
      }
    });

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

      const hilosLiderados = hilosAbiertos.filter(h => (h.lider || '').toLowerCase() === id);
      if (hilosLiderados.length > 0) {
        const badgeLider = document.createElement('span');
        badgeLider.className = 'insignia-lider';
        // Un solo hilo en la etiqueta: el del encargo en curso, o el primero; el resto se cuenta.
        const activo = hilosLiderados.find(h => h.id === agente.ejecucion?.hilo) || hilosLiderados[0];
        const resto = hilosLiderados.length - 1;
        badgeLider.textContent = `👑 Líder de ${acortarTexto(activo.titulo || activo.id, 24)}${resto > 0 ? ` (+${resto})` : ''}`;
        badgeLider.title = `Líder en: ${hilosLiderados.map(h => h.titulo || h.id).join(' · ')}`;
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

      // En vivo: el encargo en curso, dónde corre y lo último que va diciendo el agente.
      if (agente.ejecucion) {
        const vivo = document.createElement('div');
        vivo.className = 'ejecucion-viva';
        const cabecera = document.createElement('div');
        cabecera.className = 'ejecucion-cabecera';
        cabecera.textContent = `Encargo #${agente.ejecucion.n} en ${agente.ejecucion.hilo} · corre en ${agente.ejecucion.corre_en}`;
        const salida = document.createElement('pre');
        salida.className = 'ejecucion-salida';
        salida.textContent = agente.ejecucion.salida || '(todavía sin salida)';
        vivo.appendChild(cabecera);
        vivo.appendChild(salida);
        cuerpo.appendChild(vivo);
      } else if (agente.resultado) {
        const ultimo = document.createElement('div');
        ultimo.className = 'ejecucion-viva';
        const fin = new Date(agente.resultado.fin);
        ultimo.textContent = `Último encargo: #${agente.resultado.n} en ${agente.resultado.hilo}, ${agente.resultado.estado === 'hecho' ? 'hecho' : 'sin éxito'} ${tiempoRelativo(fin)}`;
        cuerpo.appendChild(ultimo);
      }

      // Alerta visible si la tiene (cortes a propósito no son fallos ni se pintan en rojo)
      if (agente.alerta) {
        const tipoAlerta = agente.alerta.tipo || 'alerta';
        const textoAlerta = agente.alerta.texto || agente.alerta.motivo || JSON.stringify(agente.alerta);
        const esCortado = esCorteAProposito(tipoAlerta, textoAlerta || agente.motivo);
        const alertaDiv = document.createElement('div');
        alertaDiv.className = esCortado ? 'alerta-tarjeta alerta-cortado' : 'alerta-tarjeta';
        const icono = esCortado ? 'ℹ️' : '⚠️';
        alertaDiv.innerHTML = `<span aria-hidden="true">${icono}</span> <span>[${escaparHtml(tipoAlerta)}] ${escaparHtml(textoAlerta)}</span>`;
        cuerpo.appendChild(alertaDiv);
      }

      // Desplegable «Procesos» (cerrado por defecto)
      const desplegable = document.createElement('details');
      desplegable.className = 'desplegable-procesos';
      if (abiertosPrevios.has(`tarjeta-${id}`) || abrirProcesosParam === id || abrirProcesosParam === 'todos' || abrirProcesosParam === '1') {
        desplegable.open = true;
      }

      const summary = document.createElement('summary');
      summary.className = 'resumen-procesos';
      summary.textContent = 'Procesos';
      desplegable.appendChild(summary);

      const cuerpoProcesos = document.createElement('div');
      cuerpoProcesos.className = 'cuerpo-procesos';

      // CLI: PID · hora de inicio (hora local, HH:mm:ss) · nombre · línea de comandos recortada.
      // Si el dato es null: «sin proceso».
      const filaCli = document.createElement('div');
      filaCli.className = 'fila-proceso';
      const labelCli = document.createElement('strong');
      labelCli.className = 'proceso-etiqueta';
      labelCli.textContent = 'CLI: ';
      filaCli.appendChild(labelCli);

      const valorCli = document.createElement('span');
      valorCli.className = 'proceso-valor';
      if (agente.cli) {
        const pidCli = agente.cli.pid != null ? agente.cli.pid : '—';
        const horaCli = formatearHoraSegundos(agente.cli.inicio);
        const nomCli = agente.cli.nombre || '—';
        const lineaCli = acortarTexto(agente.cli.linea, 60) || '—';
        valorCli.textContent = `PID ${pidCli} · ${horaCli} · ${nomCli} · ${lineaCli}`;
        if (agente.cli.linea) {
          valorCli.title = agente.cli.linea;
        }
      } else {
        valorCli.className += ' proceso-sin-proceso';
        valorCli.textContent = 'sin proceso';
      }
      filaCli.appendChild(valorCli);
      cuerpoProcesos.appendChild(filaCli);

      // Panel (solo codex y agy): PID · hora de inicio · línea de comandos recortada.
      // Si el dato es null: «sin proceso».
      if (id !== 'claude') {
        const filaPanel = document.createElement('div');
        filaPanel.className = 'fila-proceso';
        const labelPanel = document.createElement('strong');
        labelPanel.className = 'proceso-etiqueta';
        labelPanel.textContent = 'Panel: ';
        filaPanel.appendChild(labelPanel);

        const valorPanel = document.createElement('span');
        valorPanel.className = 'proceso-valor';
        if (agente.panel) {
          const pidPanel = agente.panel.pid != null ? agente.panel.pid : '—';
          const horaPanel = formatearHoraSegundos(agente.panel.inicio);
          const lineaPanel = acortarTexto(agente.panel.linea, 60) || '—';
          valorPanel.textContent = `PID ${pidPanel} · ${horaPanel} · ${lineaPanel}`;
          if (agente.panel.linea) {
            valorPanel.title = agente.panel.linea;
          }
        } else {
          valorPanel.className += ' proceso-sin-proceso';
          valorPanel.textContent = 'sin proceso';
        }
        filaPanel.appendChild(valorPanel);
        cuerpoProcesos.appendChild(filaPanel);
      }

      desplegable.appendChild(cuerpoProcesos);
      cuerpo.appendChild(desplegable);

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
      if (id === 'claude') {
        if (agente.cli) {
          spanLatido.textContent = 'Sesión de claude abierta';
          spanLatido.title = `Sesión CLI de Claude abierta${agente.cli.pid ? ` (PID ${agente.cli.pid})` : ''}`;
        } else {
          spanLatido.textContent = 'Sin sesión abierta';
          spanLatido.title = 'No hay sesión CLI de Claude abierta';
        }
      } else {
        if (agente.latido) {
          const latidoFecha = new Date(agente.latido);
          spanLatido.textContent = `Latido: ${tiempoRelativo(latidoFecha)}`;
          spanLatido.title = `Latido del proceso: ${latidoFecha.toLocaleString('es-ES')}`;
        } else {
          spanLatido.textContent = 'Latido: —';
        }
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

    // 1º Caídos (estado: caido)
    agentesList.forEach(ag => {
      const id = (ag.agente || ag.id || '').toLowerCase();
      const estado = (ag.estado || '').toLowerCase();
      if (estado === 'caido') {
        const fechaCaido = ag.desde ? new Date(ag.desde) : (ag.actualizado ? new Date(ag.actualizado) : new Date());
        let ordenCmd = `.\\mesa.ps1 pendientes -Para ${id}`;
        if (ag.ejecucion && ag.ejecucion.hilo && ag.ejecucion.n) {
          ordenCmd = `.\\mesa.ps1 reintentar -Hilo ${ag.ejecucion.hilo} -N ${ag.ejecucion.n} -De claude`;
        }
        incidencias.push({
          id: `caido-${id}`,
          grupoPrioridad: 1,
          tipo: 'caido',
          fechaObj: fechaCaido,
          agente: id,
          titulo: `Panel de ${capitalize(id)} caído`,
          paso: `El panel de ${capitalize(id)} no reporta latido reciente o su proceso no está activo.`,
          hizo: `El supervisor marcó el estado a 'caido' para evitar enviar nuevas tareas no atendidas.`,
          necesita: `Arrancar o continuar la sesión de ${capitalize(id)}.`,
          orden: ordenCmd
        });
      }
    });

    // 2º Aprobaciones y escalados (esperando-daniel y pendientes con aprobación/escalado)
    agentesList.forEach(ag => {
      const id = (ag.agente || ag.id || '').toLowerCase();
      const estado = (ag.estado || '').toLowerCase();
      if (estado === 'esperando-daniel') {
        const fechaEsp = ag.desde ? new Date(ag.desde) : (ag.actualizado ? new Date(ag.actualizado) : new Date());
        incidencias.push({
          id: `esperando-${id}`,
          grupoPrioridad: 2,
          tipo: 'esperando-daniel',
          fechaObj: fechaEsp,
          agente: id,
          titulo: `${capitalize(id)} requiere intervención de Daniel`,
          paso: ag.motivo || `El encargo se encuentra escalado tras agotar reintentos o necesita login.`,
          hizo: `El sistema detuvo el encargo y notificó a la mesa sin reintentar automáticamente.`,
          necesita: `Revisar el hilo activo y dar respuesta o nueva instrucción.`,
          orden: ag.hilo
            ? `.\\mesa.ps1 leer -Hilo ${ag.hilo}`
            : `.\\mesa.ps1 pendientes -Para ${id}`
        });
      }
    });

    if (Array.isArray(datos.pendientes)) {
      datos.pendientes.forEach((p, idx) => {
        if (p.texto && (p.texto.includes('ESCALADO') || p.texto.includes('aprobación'))) {
          const fechaPend = p.fecha ? new Date(p.fecha) : new Date();
          let ordenPend = `.\\mesa.ps1 pendientes -Para daniel`;
          if (p.hilo && p.n) {
            ordenPend = `.\\mesa.ps1 aprobar -Hilo ${p.hilo} -N ${p.n}`;
          }
          incidencias.push({
            id: `pend-${idx}`,
            grupoPrioridad: 2,
            tipo: 'aprobacion',
            fechaObj: fechaPend,
            agente: p.autor || 'sistema',
            titulo: `Aprobación pendiente de ${p.autor || 'agente'}`,
            paso: p.texto,
            hizo: `El agente está a la espera de confirmación.`,
            necesita: `Aprobar o rechazar el avance en el hilo.`,
            orden: ordenPend
          });
        }
      });
    }

    // 3º Alertas del vigía (nivel alto sin revisar; cortes a propósito NO son fallos ni alertas)
    if (Array.isArray(datos.alertas)) {
      const gruposAlertas = new Map();
      datos.alertas.filter(a => a.nivel === 'alto' && !a.revisada).forEach(al => {
        const mot = al.motivo || 'Acción que requiere revisión';
        const tipo = String(al.tipo || '').toLowerCase();
        if (esCorteAProposito(tipo, mot)) return;

        const ruta = al.archivo || al.ruta || al.valor || '';
        const clave = `${mot}|${ruta}`;
        if (!gruposAlertas.has(clave)) {
          gruposAlertas.set(clave, []);
        }
        gruposAlertas.get(clave).push(al);
      });

      gruposAlertas.forEach((items) => {
        const primero = items[0];
        const count = items.length;
        const itemsOrdenados = [...items].sort((x, y) => new Date(y.hora || 0) - new Date(x.hora || 0));
        const masReciente = itemsOrdenados[0];
        const masAntigua = itemsOrdenados[itemsOrdenados.length - 1];

        const titulo = count > 1
          ? `Alerta alta sin revisar: ${primero.motivo || 'Acción peligrosa'} ×${count}`
          : `Alerta alta sin revisar: ${primero.motivo || 'Acción peligrosa'}`;

        const horaUltima = masReciente.hora ? horaCorta(new Date(masReciente.hora)) : '—';
        const detalleVeces = count > 1 ? ` (${count} veces, última a las ${horaUltima})` : '';
        const ordenCmd = items.map(it => `.\\mesa.ps1 alertas -Revisada ${it.id}`).join('; ');

        incidencias.push({
          id: `alerta-${primero.id}`,
          grupoPrioridad: 3,
          tipo: 'alerta-alta',
          fechaObj: new Date(masAntigua.hora || Date.now()),
          agente: primero.agente || 'sistema',
          titulo: titulo,
          paso: `El vigía registró: ${primero.motivo || 'comando no permitido'}${detalleVeces}.`,
          hizo: `La escritura se hizo y solo quedó registrada.`,
          necesita: `Revisar los argumentos y marcar la alerta en la mesa.`,
          orden: ordenCmd
        });
      });
    }

    // Incidencias adicionales provistas directamente en datos.te_necesito
    if (Array.isArray(datos.te_necesito)) {
      datos.te_necesito.forEach(tn => {
        if (!incidencias.some(i => i.id === tn.id)) {
          const tipo = String(tn.tipo || '').toLowerCase();
          const mot = String(tn.paso || tn.titulo || '').toLowerCase();
          if (esCorteAProposito(tipo, mot)) return;
          const grupo = tipo === 'caido' ? 1 : (tipo === 'esperando-daniel' || tipo === 'aprobacion' ? 2 : 3);
          incidencias.push({
            ...tn,
            grupoPrioridad: grupo,
            fechaObj: tn.fecha ? new Date(tn.fecha) : new Date()
          });
        }
      });
    }

    // Orden estricto de Te necesito:
    // 1º caídos, 2º esperando-daniel / aprobaciones, 3º alertas.
    // Dentro de cada grupo, el más antiguo primero.
    incidencias.sort((a, b) => {
      if (a.grupoPrioridad !== b.grupoPrioridad) {
        return a.grupoPrioridad - b.grupoPrioridad;
      }
      const tA = a.fechaObj ? a.fechaObj.getTime() : 0;
      const tB = b.fechaObj ? b.fechaObj.getTime() : 0;
      return tA - tB;
    });

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

      const titCorto = acortarTexto(hilo.titulo || hilo.id, 24);
      const liderBadge = document.createElement('span');
      liderBadge.className = 'hilo-lider-badge';
      liderBadge.textContent = `Líder de ${titCorto}: ${capitalize(hilo.lider || '—')}`;

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
    const titCortoModal = acortarTexto(hilo.titulo || hilo.id, 24);
    dom.modalHiloTitulo.textContent = hilo.titulo || hilo.id;
    dom.modalHiloSubtitulo.textContent = `Líder de ${titCortoModal}: ${capitalize(hilo.lider || '—')} · Participantes: ${(hilo.participantes || []).join(', ') || '—'}`;
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
  function acortarTexto(txt, maxLen = 24) {
    if (!txt) return '';
    const s = String(txt).trim();
    if (s.length <= maxLen) return s;
    return s.slice(0, maxLen - 1).trimEnd() + '…';
  }

  function esCorteAProposito(tipo, motivo) {
    const t = String(tipo || '').toLowerCase();
    const m = String(motivo || '').toLowerCase();
    return t === 'cortado' || m.includes('cortado por') || m.startsWith('cortado');
  }

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

  function formatearHoraSegundos(fechaIso) {
    if (!fechaIso) return '—';
    const fecha = new Date(fechaIso);
    if (isNaN(fecha.getTime())) return '—';
    return fecha.toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
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
