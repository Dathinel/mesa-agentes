# Fondo legal de la Mesa de agentes

El repositorio (https://github.com/Dathinel/mesa-agentes) se crea **privado**. Este documento resume la licencia y lo que hay que comprobar antes de hacerlo público. No es asesoría legal.

## Licencia del código propio

MIT, `Copyright (c) 2026 Dathinel` ([`LICENSE`](../LICENSE)). Todo el código es propio: PowerShell, HTML, CSS y JavaScript escritos para la mesa. La oficina dibuja su pixel art por código, sin sprites, fuentes ni imágenes de terceros. No se redistribuye ningún binario: los tres CLI los instala cada usuario con su cuenta ([`LICENCIAS.md`](../LICENCIAS.md)).

## Marcas

«Claude», «Codex» y «Antigravity» se nombran solo para decir con qué programas funciona la mesa (uso nominativo). No se usan sus logotipos ni se sugiere respaldo de Anthropic, OpenAI o Google. Los personajes de la oficina son propios.

## Lista de comprobación antes de hacerlo público

1. `git ls-files` no incluye nada de `datos\` salvo `mesa.json`, `personajes.json` y `reclamos\LEEME.md` (los hilos tienen conversaciones completas).
2. `git grep -n -i -E "token|password|secret|@gmail|C:\\\\Users\\\\"` sin resultados reales (las cadenas `FALSO` de las pruebas son ficticias).
3. `CLAUDE.md`, `AGENTS.md` y `GEMINI.md` nombran un ámbito excluido concreto: decidir si se deja o se cambia por «los ámbitos de `datos\excluidos.txt`».
4. `docs\historial\` y `anteriores\` siguen fuera del repositorio (`.gitignore`).
5. `datos\mesa.json` no lleva cifras de cuota que no quieras publicar (`cuota_manual`).
6. El README y las capturas no muestran rutas personales ni nombres de proyectos privados.
