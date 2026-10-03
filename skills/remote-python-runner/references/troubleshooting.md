# Troubleshooting — remote-python-runner

## Las tools MCP de GitHub no aparecen en la sesión

Síntoma: el servidor MCP está configurado y el token es válido, pero el agente **no
ve** `actions_run_trigger`, `actions_list` ni `actions_get`.

| Diagnóstico | Cómo | Resultado |
|---|---|---|
| ¿El servidor responde? | `scripts\diagnose-mcp.ps1` | Handshake `initialize` → **HTTP 200**, protocolo 2025-06-18 |
| ¿Devuelve tools? | `tools/list` | **46 tools** servidas correctamente |
| ¿Faltan las de Actions? | Filtrar `actions*` | **0 tools** ← aquí está el problema |
| ¿Es el header? | `scripts\diag-toolsets.ps1` | Ver tabla abajo |

**Causa raíz:** el header `X-MCP-Toolsets` filtra la lista de tools.

| Valor de `X-MCP-Toolsets` | Tools totales | `actions_*` |
|---|---|---|
| *(ausente — default)* | 46 | **0** ❌ |
| `actions` | 4 | 3 ✅ |
| `actions,repos,context` | 27 | 3 ✅ |
| `all` | 95 | 3 ✅ |

Si el header falta, el servidor entrega el toolset **por defecto**, que **no incluye
Actions**. El síntoma es indistinguible de "el servidor no está conectado".

**Solución:** comprueba que exista en `cline_mcp_settings.json`:

```json
"headers": {
  "Authorization": "Bearer <PAT>",
  "X-MCP-Toolsets": "actions,repos,context"
}
```

Si el header está bien pero las tools siguen sin aparecer, el problema es la **conexión
de Cline**, no la configuración: abre el panel de **MCP Servers** y comprueba el estado
del servidor `github`. Si aparece *conectado* y aun así no hay tools, **recarga la ventana
de VS Code** y verifica de nuevo.

**Mientras tanto, usa el fallback REST** (`gh-run.ps1`): usa la misma credencial y cumple
la misma función.

## HTTP 405 (SSE error)

`"type"` debe ser exactamente `streamableHttp` (camelCase, sin guion). Omitirlo o
escribir `streamable-http` hace que Cline caiga a SSE, que este servidor no soporta.

## 401 Unauthorized

- PAT expirado (cada 90 días) o copiado con espacios/comillas de más.
- Valida con `.\scripts\validate-mcp.ps1` (no imprime el token).

## 403 Forbidden al escribir en el repo

- `Contents: Read-only` **no basta** para publicar: la API exige `Read and write`.
- Repositorio no incluido en *Repository access* del PAT. Añádelo y **no hace falta**
  regenerar el token: los permisos se evalúan en servidor.

## 404 Not Found en el workflow

- El workflow no está en la rama por defecto, o está deshabilitado.
- Comprueba con `actions_list(method=list_workflows)` el `path` exacto.

## El workflow no se encola

- Falta el disparador `workflow_dispatch` en el `on:`.

## La corrida nunca termina

- Límite de 15 min por job (`timeout-minutes`). Divide la suite o usa `-k` para acotar.
- El script `gh-run.ps1` cancela la corrida y devuelve error al superar el timeout.

## conclusion = success PERO hay tests fallados 🔴

**Esto es un bug del pipeline, nunca un aprobado.**

Causa clásica: `continue-on-error: true` combinado con `set -e` en el paso de pytest,
que hace que el paso nunca falle. Solución: quitar `continue-on-error` y `set -e`; los
artefactos se siguen publicando porque los pasos posteriores llevan `if: always()`.

Verifica siempre con `.\scripts\evaluate-report.ps1`, que marca `FALSO-POSITIVO`.

## Salida con código 5 (no tests ran)

El selector `-k` no coincide con ningún test. Revisa el nombre real del test
(p. ej. `-k redondeo_comercial`, no `-k vacio`).

## 0 tests ejecutados

`testpaths` en `pyproject.toml` no apunta a la carpeta real, o los tests no se
copiaron al repo.

## La API dice que tienes permisos pero la escritura falla

`permissions.push` describe los permisos del **usuario**, no los del **token**. La única
prueba fiable es un `PUT` real. Verifica con una escritura de sondeo.

## Coste y cuotas

- Repositorio **público**: minutos de Actions ilimitados, 0 USD.
- Repositorio **privado**: 2 000 min/mes incluidos; ~20 corridas ≈ 20 min ≈ 1 %.
- Storage de artifacts: 500 MB incluidos; los artifacts se borran solos a los 30 días.