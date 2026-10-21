// Prueba del servidor MCP en una mesa aislada de %TEMP%: no toca datos\ ni lanza agentes.
// Uso: node herramientas\mcp\probar.mjs
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const datos = mkdtempSync(join(tmpdir(), 'cuadrilla-mcp-'));
const transport = new StdioClientTransport({
  command: process.execPath, args: [join(dirname(fileURLToPath(import.meta.url)), 'servidor.mjs')],
  env: { ...process.env, MESA_DATOS: datos },
});
const client = new Client({ name: 'prueba', version: '1' });
await client.connect(transport);
const texto = async (name, args = {}) => {
  const r = await client.callTool({ name, arguments: args });
  return { error: !!r.isError, t: r.content.map((c) => c.text).join('\n') };
};

try {
  const { tools } = await client.listTools();
  const nombres = tools.map((t) => t.name).sort();
  assert.deepEqual(nombres, ['abrir_hilo', 'aprobar', 'enviar_mensaje', 'leer_hilo', 'pasar_liderazgo', 'rechazar', 'ver_hilos', 'ver_pendientes']);
  for (const t of tools) assert.equal(!!t.annotations?.destructiveHint, ['aprobar', 'rechazar'].includes(t.name), t.name);

  const abierto = await texto('abrir_hilo', { titulo: 'Prueba MCP ñandú', participantes: ['codex'] });
  assert.ok(!abierto.error, abierto.t);
  const id = abierto.t.trim().split('\n').pop().trim();
  assert.match(id, /^\d{8}-prueba-mcp-nandu$/);
  assert.match((await texto('ver_hilos')).t, new RegExp(id));

  // Un encargo de la app nunca se autoaprueba, aunque claude figure en autoaprobar.
  const enc = await texto('enviar_mensaje', { hilo: id, para: 'codex', texto: 'Solo lectura: lista los archivos' });
  assert.match(enc.t, /\(pendiente\)/, enc.t);
  assert.match((await texto('enviar_mensaje', { hilo: id, para: 'agy', texto: 'nota', solo_nota: true })).t, /\(hecho\)/);
  assert.match((await texto('ver_pendientes')).t, new RegExp(id));
  assert.match((await texto('pasar_liderazgo', { hilo: id, nuevo: 'codex' })).t, /cambiado a codex/);

  assert.match((await texto('rechazar', { hilo: id, n: 1, motivo: 'era una prueba' })).t, /Rechazado/);
  const otra = await texto('aprobar', { hilo: id, n: 1 });
  assert.ok(otra.error, 'aprobar un rechazado debe fallar');
  assert.match((await texto('leer_hilo', { hilo: id })).t, /claude-app -> codex.*estado=rechazado/);
  assert.ok((await texto('leer_hilo', { hilo: 'no-existe' })).error);

  const log = readFileSync(join(datos, 'claude-app.log'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  assert.ok(log.length >= 10 && log.every((l) => l.origen === 'claude-app' && l.fecha));
  assert.match(readFileSync(join(datos, 'aprobaciones.log'), 'utf8'), /RECHAZADO.*claude-app/);
  console.log(`OK: ${tools.length} herramientas, ${log.length} acciones registradas`);
} finally {
  await client.close();
  rmSync(datos, { recursive: true, force: true });
}
