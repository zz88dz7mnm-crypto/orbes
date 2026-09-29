# Instalar ORBEX en tu Mac

ORBEX se escribió entero en la nube, pero **nunca se compiló en una Mac**. La lógica pura (`OrbexCore`) sí se compiló con Swift 6.1 y pasan sus 116 pruebas, pero la parte de macOS (AppKit/SwiftUI) solo se revisó a mano. Es probable que la primera compilación tire algunos errores chicos. Por eso lo ideal es instalarla **con Claude Code en tu Mac**, que compila, corrige y vuelve a intentar solo.

---

## Opción A (recomendada): que Claude la instale

1. Instalá lo necesario (una sola vez):
   - **Xcode 26** desde el App Store (o como mínimo las herramientas: `xcode-select --install`). Con Xcode 26 ORBEX usa el Liquid Glass nativo.
   - **Claude Code**: https://claude.com/claude-code, y logueate corriendo `claude` una vez en la Terminal. El asistente de ORBEX lo usa.
2. Bajá el proyecto. Tenés dos formas:
   - **Con git** (mejor, así Claude puede subir los arreglos):
     ```bash
     git clone -b claude/clever-heisenberg-xuhx4z https://github.com/zz88dz7mnm-crypto/orbes.git
     cd orbes
     ```
   - **Con ZIP**: en GitHub, botón verde **Code → Download ZIP**, descomprimilo y entrá a la carpeta desde la Terminal.
3. Abrí Claude Code en esa carpeta (`claude`) y pegale esto:

```
Leé CLAUDE.md, INSTALAR.md y docs/PLAN.md. Esta app nunca se compiló en macOS.
Tu tarea: dejar ORBEX compilando, instalado y abierto en esta Mac.
1. Corré `bash scripts/install.sh`.
2. Si falla la compilación, corregí los errores de a uno con el cambio MÍNIMO
   (sin cambiar comportamiento, sin agregar dependencias, respetando CLAUDE.md)
   y volvé a correr el script. Repetí hasta que compile e instale.
3. Corré `swift test` y arreglá lo que falle.
4. Cuando abra, confirmá que la isla aparece en el notch y que el menú de la barra
   tiene "Probar estados".
5. Si trabajás con git, hacé commit de los arreglos con mensajes claros y push.
Al final decime qué arreglaste y qué quedó pendiente.
```

---

## Opción B: a mano

```bash
cd orbes          # la carpeta del proyecto
bash scripts/install.sh
```

El script:
1. compila la app (`swift build -c release`),
2. arma `dist/ORBEX.app` con su ícono y la firma (ad hoc),
3. genera `dist/ORBEX.dmg`,
4. cierra ORBEX si estaba abierto, la copia a **Aplicaciones**, le saca la cuarentena y la abre.

Si la compilación falla, los errores aparecen en la Terminal: copialos y pasáselos a Claude.

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
| Automatización | Apple Notas, Spotify/Música, Terminal/iTerm2 (saltar a la sesión) |
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
| GitHub, Vercel, Stripe, n8n, Resend, Notion, Cal.com | Configuración › Integraciones (clave en el Keychain, solo lectura) |
| Temas: Liquid Glass / macOS limpio / Y2K | Configuración › Tema |

---

## Problemas comunes

| Problema | Solución |
|---|---|
| La isla no calza con el notch | Configuración › Isla › Ajuste fino (ancho ±10, alto ±6) |
| No veo la isla en un monitor externo | Es normal: simula un notch arriba al centro. Elegí la pantalla en Configuración › Isla |
| El asistente dice que no encuentra `claude` | Instalá Claude Code y corré `claude` una vez para loguearte |
| Claude Code no muestra la isla al pedir permiso | Configuración › Claude Code → Instalar hooks. Si ORBEX está cerrado, Claude Code sigue normal: nunca se bloquea |
| Un atajo no anda | Otra app lo está usando. Se puede cambiar en `Sources/Orbex/System/HotKeys.swift` |
| Quiero sacarla | `bash scripts/uninstall.sh` (o `--all` para borrar todo) |
