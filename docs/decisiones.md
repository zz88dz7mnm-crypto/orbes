# Decisiones

Registro de decisiones del proyecto. Las del informe original están en `00-informe-completo.md` §2.

| Fecha | Decisión | Por qué |
|---|---|---|
| 28/09/2026 | Alcance del trabajo: **todas las fases (0 a 6)** | Pedido del dueño |
| 28/09/2026 | Máquina objetivo: **MacBook Air M4 15"** | Confirmado por el dueño. El notch se mide en vivo igual (no hay medida verificada del 15") |
| 28/09/2026 | ORBEX **dibujado por código** (SwiftUI `Canvas` + `TimelineView`) | No existen todavía las partes separadas del personaje. El dibujo por código anima todo y se puede reemplazar por assets después |
| 28/09/2026 | **Swift Package** en vez de XcodeGen | Menos herramientas para instalar: `swift build` + scripts arman `ORBEX.app`. Xcode abre `Package.swift` directo |
| 28/09/2026 | Mínimo **macOS 14**, Liquid Glass nativo en **macOS 26+** con respaldo `.ultraThinMaterial` | Que compile y corra aunque la Mac o el Xcode no sean los últimos |
| 28/09/2026 | Modo de lenguaje **Swift 5** (tools 5.9) | Evitar errores de concurrencia estricta imposibles de verificar sin compilar en Mac |
| 28/09/2026 | **Sonidos sintetizados por código** | Originales, sin licencias ni archivos binarios |
| 28/09/2026 | `orbex-hook` como **ejecutable Swift** dentro de la app | No depender de Python (no viene instalado en todas las Mac) |
| 28/09/2026 | Si ORBEX no responde a un permiso de Claude Code, el hook **no decide** (Claude Code pregunta en la terminal) | Coucou deniega por defecto; el informe pide no bloquear nunca |
| 28/09/2026 | Compilación: el dueño baja el zip y una IA en su Mac corre `./scripts/install.sh` | No se puede compilar macOS desde la nube (Linux sin Swift). Workflow de GitHub Actions solo manual |
| 28/09/2026 | Avance en `docs/PLAN.md`, push tras cada paso | Pedido del dueño: ver el % y no perder contenido |
| 28/09/2026 | Reloj estilo ORBIT: **interpretación propia** (anillos, órbitas) hasta tener la descripción de ORBIT | §6.4 del informe sigue pendiente |
| 28/09/2026 | **Trabajo por fases estricto**: subagentes solo en la fase actual; no se empieza la siguiente sin cerrar la anterior | Pedido del dueño |
| 28/09/2026 | **Asistente (Fase 2): solo Claude**, usado a través del **CLI `claude` local** (Claude Code, con la suscripción del dueño). Sin OpenAI y sin claves de API | Pedido del dueño. Reemplaza §9.2 del informe |
| 28/09/2026 | Con el asistente activo, **ORBEX se pone naranja** y aparece una **mascota chica: Clawd**, el bichito pixelado de Claude Code (dibujado por código, uso personal) | Pedido del dueño |
| 28/09/2026 | Las sesiones de `claude` que lanza ORBEX llevan `ORBEX_INTERNAL=1`: el relé de hooks (Fase 3) las ignora | Evitar que el asistente aparezca como sesión o pida aprobaciones |
| 28/09/2026 | **Sin pruebas durante las fases**: se escribe el código y se sube; una sola pasada de corrección de errores al final | Pedido del dueño: ahorrar tokens |
| 28/09/2026 | **No se piensa en compilar en la Mac durante el desarrollo**: el foco es hacer la app. El dueño la instala al final con Claude en su Mac | Pedido del dueño |
| 29/09/2026 | **Etapa 2: ORBEX sobre la base de Coucou.** Se clona el código de Coucou (MIT) como cascarón de la app y se le aplica todo lo de ORBEX | Pedido del dueño |
| 29/09/2026 | De Coucou se usa solo el código (`Base/`); nunca nombres, personaje Mochi, íconos, sonidos ni imágenes | Licencia de assets de Coucou |
| 29/09/2026 | **Isla abierta de 640 pt como Coucou** (reemplaza "notch + alitas" del informe §5.1) | Pedido del dueño |
| 29/09/2026 | Clic sobre ORBEX = **cosquillas** (no cachetada); 3 clics → mareo | Pedido del dueño: mejor relación con el usuario |
| 29/09/2026 | Sesiones de Claude Code: UI de Coucou + motor de ORBEX (el `HookServer` de Coucou responde en un formato que Claude Code ignora, timeout de 10 s, solo VS Code) | Revisión del código de Coucou |
| 29/09/2026 | Integraciones: se quedan los 7 pollers y tarjetas de Coucou; se retira `IntegrationsHub` de ORBEX | Duplicado; UI de Coucou más rica |
| 29/09/2026 | Chat de la isla (vista `prompt` de Coucou) con el `claude` local de ORBEX, Clawd y ORBEX naranja; se retira `AssistantPanelView` | Una sola UI de chat |
| 29/09/2026 | Mínimo macOS 15 (como Coucou) | Base clonada |
| 29/09/2026 | La compilación en la Mac la hace el dueño al final (`INSTALAR.md`) | Pedido del dueño |
