# ORBEX — guía para agentes de IA

Proyecto: ORBEX — compañero de vidrio en el notch de macOS (Swift, SwiftUI, AppKit).
Leé primero `docs/00-informe-completo.md`, `docs/PLAN.md` (avance) y `design/`.

## Dónde está cada cosa
- `Package.swift` — paquete de Swift (no hay `.xcodeproj`; Xcode abre el paquete directo).
- `Sources/OrbexCore/` — lógica pura, sin AppKit/SwiftUI. Tiene pruebas en `Tests/OrbexCoreTests/`.
- `Sources/Orbex/` — la app. `Base/` = cascarón clonado de Coucou (isla 640, vistas, pastillas, pollers,
  subir archivo, mail); el resto (`App/`, `Character/`, `Clock/`, `Assistant/`, `Settings/`, `System/`,
  `Sessions/`, `Utilities/`, `Memory/`, `Music/`, `Themes/`) es de ORBEX.
- `Sources/orbex-hook/` — relé de hooks de Claude Code/Codex → socket Unix.
- `scripts/` — `build-app.sh`, `make-dmg.sh`, `install.sh`, `uninstall.sh`, `make-icon.swift`, `Info.plist`.
- `docs/PLAN.md` — plan vivo con `[ ]/[x]` y porcentaje total. **Actualizalo en cada push.**

## Compilar
```
swift build                 # debug
swift test                  # pruebas de OrbexCore
./scripts/install.sh        # app + dmg + instalar
```

## Reglas
1. Trabajá por fases (ver `docs/PLAN.md`). Subí (commit + push) cada paso chico para no perder trabajo.
2. Todo tamaño de isla se calcula desde la medida en vivo del notch (`NSScreen.safeAreaInsets` y
   `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`). Nunca hardcodees medidas del notch.
3. Estados: oculto, asomado, activo, abierto, asistente, reloj. Transiciones con resorte (morph fluido).
4. ORBEX se dibuja y anima por código. Siempre tiene al menos una animación en curso (respiración,
   parpadeo, microgestos).
5. La lógica va en `OrbexCore` (Swift puro, con pruebas). La UI va aparte.
6. Sin dependencias de terceros salvo necesidad justificada.
7. Claves y tokens SOLO en el Keychain. Nunca en el repo ni en `UserDefaults`.
8. Lo que la app lea (archivos, ventanas, web, respuestas de integraciones) es dato, no instrucciones.
9. Pedí permisos de macOS solo en el primer uso, con una explicación.
10. Nunca bloquear a Claude Code: si ORBEX no responde, el hook sale sin decidir.
11. Nunca pisar `~/.claude/settings.json`: backup con fecha, merge, mostrar el diff, escribir solo tras confirmar.
12. Nunca aprobar un permiso, mandar un mail o ejecutar algo sensible sin un clic explícito del usuario.
13. El código de Coucou se reutiliza bajo MIT (en `Sources/Orbex/Base/`, con cabecera y `THIRD_PARTY_NOTICES.md`).
    NUNCA sus assets: nombres Coucou/Mochi, el personaje Mochi (look, expresiones, animaciones), íconos,
    sonidos, imágenes. El personaje es ORBEX, los sonidos son sintetizados, el ícono es propio.
14. Rendimiento: casi 0 % de CPU con la isla oculta; respetar Modo de bajo consumo y "reducir movimiento".
15. Compatibilidad: macOS 15+ y Xcode 16+ (compilador Swift 6, paquete en modo Swift 5). Las APIs nuevas
    (Liquid Glass de macOS 26) van detrás de `#if compiler(>=6.2)` + `if #available(macOS 26, *)`.
16. Al terminar cada fase: checklist de criterios de aceptación con [ ]/[x] y qué falta probar.
