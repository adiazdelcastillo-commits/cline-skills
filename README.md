> [!IMPORTANT]
> **Este repositorio nunca debe contener un PAT real.** Solo la plantilla
> `mcp-settings.template.json`, con el marcador `PEGAR_AQUI_EL_PAT`.

# 🧰 Respaldo de skills de Cline

Respaldo portable de **35 skills** de Cline, incluidos `remote-python-runner`, que permite
ejecutar pruebas de Python en la nube de GitHub sin tener Python instalado localmente.

## 📦 Contenido

| Ruta | Qué es |
|---|---|
| `skills/` | Los 35 skills (389 archivos) |
| `install-skills.ps1` | Instalador idempotente en `~/.cline/skills/` |
| `mcp-settings.template.json` | Plantilla de config MCP **sin token** |
| `.clinerules` | Reglas de enrutado y estilo |
| `.gitignore` | Exclusiones de seguridad |

## 🚀 Replicar en otra máquina (5 minutos)

### 1. Instalar los skills

```powershell
git clone <url-de-este-repo> cline-skills
cd cline-skills
.\install-skills.ps1
```

Comprueba que se han instalado:
```powershell
(Get-ChildItem "$env:USERPROFILE\.cline\skills" -Directory).Count
```

### 2. Cargar la ventana de VS Code

```
Ctrl + Shift + P  →  "Developer: Reload Window"
```
Cline lee los skills **solo al arrancar**.

### 3. Configurar el PAT de GitHub (para `remote-python-runner`)

Crea un **PAT fine-grained** en <https://github.com/settings/personal-access-tokens/new>
con:

| Permiso | Nivel |
|---|---|
| **Actions** | Read and write |
| **Contents** | **Read and write** |
| **Workflows** | Read and write |

> ⚠️ `Contents: Read-only` **no basta** para publicar archivos: la API devuelve 403.

Copia `mcp-settings.template.json` a:

```
%USERPROFILE%\.cline\data\settings\cline_mcp_settings.json
```

y sustituye `PEGAR_AQUI_EL_PAT` por tu token.

> 🔒 **El archivo debe guardarse SIN BOM.** PowerShell 5.1 con `Set-Content -Encoding UTF8`
> añade un BOM que Node.js rechaza con *"Invalid JSON in MCP settings file"*.
> Usa:
> ```powershell
> [System.IO.File]::WriteAllText($dest, $json, (New-Object System.Text.UTF8Encoding $false))
> ```

### 4. Verificar

```powershell
.\install-skills.ps1 -DryRun
```

---

## 🐍 `remote-python-runner`: ejecutar Python en la nube

Si no tienes Python local, el skill lanza las pruebas en **GitHub Actions** y te devuelve
el resultado en el chat.

```
Tú: "corre las pruebas"
  → Cline dispara el workflow run-tests.yml
  → GitHub levanta un runner Ubuntu con Python
  → ejecuta pytest, publica artefactos y se apaga
  → Cline te informa: conclusion, tests pasados/fallados y el enlace
```

### Requisitos

1. Un repositorio con `.github/workflows/run-tests.yml` (básate en `lab/` de este repo).
2. El PAT configurado (paso 3).
3. El repo incluido en *Repository access* del PAT.

> 💡 **No necesitas crear un repositorio cada vez.** El repo es permanente; lo que se
> recrea en cada ejecución es el *entorno* (el runner), que es desechable.

### Usar el skill

Simply escribe en el chat:

- «corre las pruebas»
- «ejecuta la suite»
- «valida el proyecto»

Se activa solo por su `description`, sin nombrarlo.

---

## 📁 Estructura de un skill

```
skills/<nombre>/
├── SKILL.md          ← obligatorio: frontmatter con name + description
├── scripts/          ← opcional
└── references/       ← opcional
```

`SKILL.md` empieza siempre con:
```markdown
---
name: nombre-del-skill
description: Qué hace Y cuándo usarlo. Esta línea decide si el skill se activa.
---
```

---

## 🔐 Seguridad

| Regla | Motivo |
|---|---|
| Nunca subir `cline_mcp_settings.json` | Contiene el PAT |
| Nunca escribir un PAT en un archivo del repo | Quedaría en el historial de Git |
| Nunca pasar el PAT por línea de comandos | Queda en el historial del shell |
| Revisar antes de hacer público un repo de skills | Puede incluir trabajo propietario |

---

## 🛠️ Mantenimiento

Para volver a generar este respaldo tras cambiar skills:

```powershell
.\scripts\inventory-skills.ps1    # auditar: secretos, tamaño, rutas
.\scripts\export-skills.ps1       # copiar y sanear a skills-export/
git add skills/ && git commit -m "chore: sincroniza skills"
```