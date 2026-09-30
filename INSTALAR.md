# Instalar ORBEX en tu Mac

ORBEX se escribe en la nube y **nunca se compiló en una Mac**: la lógica pura (`OrbexCore`) sí se compila
y se prueba con Swift 6.1, pero la parte de macOS (AppKit/SwiftUI) solo se revisa por sintaxis. Es probable
que la primera compilación tire algún error chico. Por eso lo más cómodo es que lo haga **Claude** en tu Mac:
compila, corrige lo mínimo y vuelve a intentar solo.

## Antes de empezar (una sola vez)

- **macOS 15 o superior.**
- **Xcode 16 o superior** desde el App Store, **o** solo las herramientas de línea de comandos:
  `xcode-select --install`. Con Xcode 26 en macOS 26, ORBEX usa el Liquid Glass nativo.
- **Claude Code** (https://claude.com/claude-code): corré `claude` una vez en la Terminal para loguearte.
  El chat de ORBEX lo usa, y sirve para que Claude te instale la app.

Para saber si ya tenés el compilador: `swift --version` en la Terminal (tiene que decir 6.0 o más).

---

## Camino A · Primera vez

1. En GitHub: botón verde **Code → Download ZIP**, y descomprimilo (o `git clone` del repo).
2. En la Terminal, entrá a la carpeta y corré:
   ```bash
   bash scripts/install.sh
   ```
   Compila (`swift build -c release`), arma `dist/ORBEX.app` con su ícono y firma ad hoc, genera
   `dist/ORBEX.dmg`, la copia a **Aplicaciones**, le saca la cuarentena y la abre.

## Camino B · Ya tenías la versión anterior

1. Bajá el **ZIP nuevo** y descomprimilo (queda en una carpeta nueva; la vieja podés dejarla por ahora).
2. En la Terminal, entrá a la carpeta **nueva** y corré:
   ```bash
   bash scripts/actualizar.sh
   ```
   (con `--si` responde que sí a todas las preguntas, salvo borrar tus datos).

**Qué borra `actualizar.sh`:**
- la app vieja (`/Applications/ORBEX.app` y `~/Applications/ORBEX.app`) y los compilados (`.build`, `dist`);
- el acceso directo viejo del Escritorio (la app nueva lo vuelve a crear si lo tenías activado);
- los hooks viejos de Coucou/NotchBuddy en `~/.claude/settings.json`: **te muestra el diff, guarda un backup
  con fecha y solo escribe si confirmás**;
- si preguntás que sí: `Coucou.app`, la carpeta `~/.claude/coucou`, y la carpeta/ZIP viejo del proyecto
  (en Descargas, Escritorio o Documentos).

**Qué NO toca:** tus notas, memoria, timers, recordatorios, ajustes y las claves del Keychain. Siguen
donde estaban y la versión nueva las usa tal cual.

Después compila e instala con `install.sh`, igual que el camino A.

---

## Que lo haga Claude (recomendado)

Sirve **Claude Code en la Mac** (abrilo con `claude` dentro de la carpeta nueva) o **Claude Desktop con
acceso a la Terminal**. Pegale esto tal cual:

```
Quiero instalar/actualizar ORBEX en esta Mac. La carpeta NUEVA del proyecto es la que
descomprimí último (si no estás en ella, buscala en Descargas y preguntame si hay dudas).
Leé CLAUDE.md e INSTALAR.md antes de empezar. La parte de macOS nunca se compiló en una Mac.

1. Chequeá que haya compilador: `swift --version` (6.0 o más). Si no hay, decime que instale
   Xcode 16+ o corra `xcode-select --install`, y pará ahí.
2. Andá a la carpeta nueva y corré `bash scripts/actualizar.sh` (si es la primera vez que
   instalo ORBEX, `bash scripts/install.sh`). Cuando pregunte por borrar la carpeta o el ZIP
   viejo, respondé que NO por ahora. A cualquier cambio en ~/.claude/settings.json mostrámelo
   y esperá mi OK.
3. Si el compilador marca errores, corregilos con el cambio MÍNIMO (sin cambiar diseño ni
   comportamiento, sin agregar dependencias, respetando CLAUDE.md) y volvé a correr
   `bash scripts/install.sh`. Repetí hasta que compile e instale.
4. Verificá que ORBEX abre: que el proceso "Orbex" esté corriendo (`pgrep -x Orbex`), que
   la isla aparezca en el notch y que el menú de la barra tenga "Probar estados".
5. Recién cuando todo ande, preguntame si borro la carpeta y el ZIP de la versión vieja;
   borralos solo si te digo que sí. No borres mis datos (notas, memoria, ajustes, Keychain).
Al final decime qué corregiste (archivo y motivo) y qué quedó pendiente de probar.
```

Si algo falla y lo hacés a mano, copiá los errores de la Terminal y pasáselos a Claude.

Otros comandos:

| Comando | Qué hace |
|---|---|
| `bash scripts/build-app.sh` | Solo compila y arma `dist/ORBEX.app` |
| `bash scripts/make-dmg.sh` | Arma `dist/ORBEX.dmg` |
| `bash scripts/uninstall.sh` | Desinstala (app, acceso directo, hooks, inicio con la Mac). `--all` borra también datos y claves |
| `swift test` | Pruebas de la lógica |

---

## Primer arranque

- Aparece la **bienvenida**: acceso directo en el Escritorio, iniciar con la Mac y tema.
- Si macOS dice *"no se puede verificar al desarrollador"* (la app no está notarizada): **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**. El script ya intenta evitarlo.
- ORBEX vive en el **notch**: pasá el mouse para que asome y hacé clic para abrir. Atajos: **⌃⌥O** abrir, **⌃⌥A** asistente, **⌃⌥C** reloj, **⌃⌥,** configuración.
- En el menú de la barra (la esfera con ojos) está **Probar estados**, para ver trabajando, te necesito, festejar y dormir.

### Permisos que macOS te va a pedir (solo cuando uses cada cosa)

| Permiso | Para qué |
|---|---|
| Carpeta Escritorio | Crear el acceso directo |
| Automatización | Terminal/iTerm2 (saltar a la sesión), Mail (mandar un mail desde la isla), Spotify/Música, Apple Notas |
| Accesibilidad | Solo si arrastrás a ORBEX sobre una ventana: lee el título de esa ventana como contexto |
| Notificaciones | Timers y recordatorios |
| Grabación de pantalla y audio | Solo si activás "Bailar al ritmo" (Configuración › Música) |

---

## Activar cada parte

| Qué | Dónde |
|---|---|
| Asistente con Claude (usa tu `claude` local, sin claves) | Configuración › Asistente (Claude) |
| Ver sesiones de Claude Code y aprobar permisos desde el notch | Configuración › Claude Code → **Instalar hooks…** (te muestra el diff antes de escribir `~/.claude/settings.json` y deja un backup) |
| Reloj flotante | ⌃⌥C o el botón Reloj; opciones en Configuración › Reloj |
| Timers, notas, acciones y apps permitidas | Configuración › Timers / Notas / Acciones y apps |
| Recordatorios y memoria | Decile al asistente "a las 21 recordame…" o "acordate que…" |
| Spotify y baile | Configuración › Música |
| Stripe, Notion, Cal.com (opcionales, apagados) | Configuración › Integraciones (clave en el Keychain) |
| Temas: Liquid Glass / macOS limpio / Y2K | Configuración › Tema |

---

## Hablarle a ORBEX ("Orbex, …")

Decile **"Orbex"** (o "Orbi", "Orbes"… entiende variantes) seguido de lo que quieras, y ORBEX lo hace. No
responde hablando: se pone **magenta**, lleva la mano a la oreja mientras te escucha y asiente al terminar.

- **Activar:** Configuración › Voz › prender. La primera vez macOS te pide micrófono y reconocimiento de voz.
- **Atajo:** ⌃⌥Espacio (o ⌃⌥V si macOS se queda con el primero): hablás, te callás y listo. Tocarlo de nuevo corta.
- **Siempre atento:** opcional (apagado por defecto, gasta algo de batería): escucha su nombre todo el tiempo.
  Se pausa con la pantalla bloqueada.
- **Privacidad:** el reconocimiento corre en tu Mac. Si falta el modelo en español: Ajustes del Sistema ›
  Teclado › Dictado → agregá español.
- **Ejemplos:** "Orbex, abrí Spotify" · "Orbi, poné un timer de 5 minutos" · "Orbex, recordame a las 18 llamar
  a Juan" · "Orbex, anotá comprar pan" · "Orbex, mostrame el reloj" · cualquier otra cosa va a Claude.
- Lo sensible (abrir algo fuera de tu lista, acciones con confirmación) **nunca** se hace solo por voz: se abre
  el chat de la isla con el botón para confirmar.

## Problemas comunes

| Problema | Solución |
|---|---|
| La isla no calza con el notch | Configuración › Isla › Ajuste fino (ancho ±10, alto ±6) |
| No veo la isla en un monitor externo | Es normal: simula un notch arriba al centro. Elegí la pantalla en Configuración › Isla |
| El asistente dice que no encuentra `claude` | Instalá Claude Code y corré `claude` una vez para loguearte |
| Claude Code no muestra la isla al pedir permiso | Configuración › Claude Code → Instalar hooks. Si ORBEX está cerrado, Claude Code sigue normal: nunca se bloquea |
| Un atajo no anda | Otra app lo está usando (los atajos de ORBEX son fijos: ⌃⌥O/A/C/,). Se cambian en `Sources/Orbex/System/HotKeys.swift` |
| Quiero sacarla | `bash scripts/uninstall.sh` (o `--all` para borrar todo) |
| Quiero actualizar | Camino B: `bash scripts/actualizar.sh` desde la carpeta nueva |
