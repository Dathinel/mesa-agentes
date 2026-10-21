// Servidor MCP por stdio para la app de escritorio de Claude. No reimplementa nada: cada herramienta llama a mesa.ps1
// (la misma lógica, candados y cola de aprobación que usan los agentes) y deja una línea en datos\claude-app.log.
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { execFile } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';

const ORIGEN = 'claude-app';
const herramientas = join(dirname(fileURLToPath(import.meta.url)), '..');
const datos = process.env.MESA_DATOS || join(herramientas, '..', 'datos');
const powershell = join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');

// Los parámetros viajan como JSON en una variable de entorno: nunca se interpretan como código de PowerShell.
const puente = '[Console]::OutputEncoding=[Text.Encoding]::UTF8; $p=@{}; (ConvertFrom-Json $env:CUADRILLA_ARGS).psobject.Properties | ForEach-Object { $p[$_.Name]=$_.Value }; & $env:CUADRILLA_SCRIPT @p';

function ps(script, args) {
  return new Promise((resolve) => {
    execFile(powershell, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', puente], {
      env: { ...process.env, CUADRILLA_SCRIPT: join(herramientas, script), CUADRILLA_ARGS: JSON.stringify(args) },
      windowsHide: true, timeout: 120000, maxBuffer: 8 * 1024 * 1024,
    }, (err, stdout, stderr) => resolve({ ok: !err, texto: [stdout, stderr].filter((s) => s && s.trim()).join('\n').trim() || '(sin salida)' }));
  });
}

function registrar(herramienta, args, ok) {
  try { appendFileSync(join(datos, 'claude-app.log'), JSON.stringify({ fecha: new Date().toISOString(), origen: ORIGEN, herramienta, args, ok }) + '\n', 'utf8'); } catch { /* el registro no debe tumbar la herramienta */ }
}

// El primer argumento posicional de mesa.ps1 es el subcomando.
async function mesa(herramienta, comando, args) {
  const r = await ps('mesa.ps1', { Comando: comando, ...args });
  registrar(herramienta, args, r.ok);
  return { content: [{ type: 'text', text: r.texto }], isError: !r.ok };
}

const agente = z.enum(['claude', 'codex', 'agy']);
const hilo = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9-]*$/).describe('Id del hilo, p. ej. 20261020-informe-ventas');
const n = z.number().int().positive().describe('Número del mensaje dentro del hilo');
const lectura = { readOnlyHint: true, openWorldHint: false };

const server = new McpServer({ name: 'cuadrilla', version: '1.0.0' });

server.registerTool('ver_hilos', {
  title: 'Ver hilos', description: 'Lista los hilos de la mesa con estado, líder, participantes y número de mensajes.',
  inputSchema: {}, annotations: lectura,
}, () => mesa('ver_hilos', 'hilos', {}));

server.registerTool('leer_hilo', {
  title: 'Leer hilo', description: 'Muestra un hilo completo: cada mensaje con autor, destino, tipo, estado, texto y traspaso.',
  inputSchema: { hilo }, annotations: lectura,
}, ({ hilo }) => mesa('leer_hilo', 'leer', { Hilo: hilo }));

server.registerTool('ver_pendientes', {
  title: 'Ver pendientes de aprobación', description: 'Encargos que esperan la aprobación de la persona (hilo, número, de, para, modelo y motivo).',
  inputSchema: {}, annotations: lectura,
}, () => mesa('ver_pendientes', 'pendientes', {}));

server.registerTool('abrir_hilo', {
  title: 'Abrir hilo', description: 'Abre un hilo nuevo en la mesa con su líder y participantes. Devuelve el id del hilo.',
  inputSchema: {
    titulo: z.string().min(1).max(200),
    lider: agente.default('claude'),
    participantes: z.array(agente).default([]).describe('Además del líder'),
  },
  annotations: { destructiveHint: false, idempotentHint: false, openWorldHint: false },
}, ({ titulo, lider, participantes }) => mesa('abrir_hilo', 'abrir', { Titulo: titulo, Lider: lider, Participantes: [lider, ...participantes] }));

server.registerTool('enviar_mensaje', {
  title: 'Enviar mensaje', description: 'Escribe en un hilo. A codex, agy o claude crea un encargo que queda PENDIENTE de aprobación (nunca se lanza solo); con solo_nota=true es una nota que no lanza nada.',
  inputSchema: {
    hilo, para: z.enum(['claude', 'codex', 'agy', 'todos']), texto: z.string().min(1).max(20000),
    solo_nota: z.boolean().default(false),
  },
  annotations: { destructiveHint: false, idempotentHint: false, openWorldHint: false },
}, ({ hilo, para, texto, solo_nota }) => mesa('enviar_mensaje', 'enviar', { Hilo: hilo, De: ORIGEN, Para: para, Texto: texto, SoloNota: solo_nota }));

server.registerTool('pasar_liderazgo', {
  title: 'Pasar liderazgo', description: 'Cambia el líder de un hilo y deja el traspaso registrado en el hilo.',
  inputSchema: { hilo, nuevo: agente },
  annotations: { destructiveHint: false, idempotentHint: true, openWorldHint: false },
}, ({ hilo, nuevo }) => mesa('pasar_liderazgo', 'lider', { Hilo: hilo, Nuevo: nuevo, De: ORIGEN }));

server.registerTool('aprobar', {
  title: 'Aprobar encargo', description: 'Aprueba un encargo pendiente y lo lanza en segundo plano (codex exec, agy o claude -p), con los topes de mesa.json.',
  inputSchema: { hilo, n }, annotations: { destructiveHint: true, idempotentHint: false, openWorldHint: true },
}, async ({ hilo, n }) => {
  const r = await mesa('aprobar', 'aprobar', { Hilo: hilo, N: n, NoLanzar: true, Motivo: `aprobado desde ${ORIGEN}` });
  if (r.isError) return r;
  // Igual que delegar.ps1 sin -Visible: ejecutar.ps1 aparte, para no bloquear la app mientras trabaja el agente.
  const lanzado = await ps(join('mcp', 'lanzar.ps1'), { Hilo: hilo, N: n });
  r.content.push({ type: 'text', text: lanzado.texto });
  return { ...r, isError: !lanzado.ok };
});

server.registerTool('rechazar', {
  title: 'Rechazar encargo', description: 'Rechaza un encargo pendiente con un motivo; no se lanza nada.',
  inputSchema: { hilo, n, motivo: z.string().min(1).max(2000) },
  annotations: { destructiveHint: true, idempotentHint: true, openWorldHint: false },
}, ({ hilo, n, motivo }) => mesa('rechazar', 'rechazar', { Hilo: hilo, N: n, Motivo: `${motivo} (${ORIGEN})` }));

await server.connect(new StdioServerTransport());
