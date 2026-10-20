# Fondo legal

No es asesoría legal: resume la licencia y lo que hay que comprobar antes de publicar una versión.

## Licencia del código propio

MIT ([`LICENSE`](../LICENSE)). Todo el código es propio: PowerShell, HTML, CSS y JavaScript. La oficina dibuja su pixel art por código, sin sprites, fuentes ni imágenes de terceros. No se redistribuye ningún binario: los tres CLI los instala cada persona con su cuenta y sus términos ([`LICENCIAS.md`](../LICENCIAS.md)).

## Marcas

«Claude», «Codex» y «Antigravity» se nombran solo para decir con qué programas funciona Cuadrilla (uso nominativo). No se usan sus logotipos ni se sugiere respaldo de Anthropic, OpenAI o Google. Los personajes de la oficina son propios.

## Antes de publicar

1. `git log --all --name-only` no muestra nunca nada de `datos\` salvo `mesa.ejemplo.json`, `personajes.json` y `reclamos\LEEME.md`, ni `CLAUDE.md`/`AGENTS.md`/`GEMINI.md` generados, ni `docs\interno\`, ni `docs\historial\`.
2. `git grep -n -i -E "token|password|secret|@gmail|C:\\\\Users\\\\"` no encuentra datos reales (las cadenas `FALSO` de las pruebas son ficticias).
3. Ningún archivo versionado nombra a una persona, una carpeta de un PC concreto, un proyecto privado ni un identificador de sesión.
4. Las capturas del README se hacen con datos de demostración, no con los hilos reales.
