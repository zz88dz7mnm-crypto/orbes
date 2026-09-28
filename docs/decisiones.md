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
