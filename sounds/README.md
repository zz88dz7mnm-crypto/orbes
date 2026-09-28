# Sonidos

ORBEX **no usa archivos de audio**: todos los sonidos se sintetizan por código en `Sources/Orbex/System/SoundEngine.swift` (osciladores + envolventes), así son 100 % originales y no hay licencias de terceros.

- Todos los sonidos usan notas de la **escala pentatónica de Do mayor** (Do, Re, Mi, Sol, La), así nunca desafinan entre sí.
- Cada tema trae su **pack** (timbre distinto): Liquid Glass = gotas y campanitas (senoidales con ataque rápido), macOS limpio = clics suaves, Y2K = chiptune (cuadradas).
- Se precargan en buffers al arrancar para que la latencia sea mínima.

Si más adelante se quieren sonidos grabados, van en esta carpeta (WAV/CAF cortos) con un `LICENSES.md` que diga el origen de cada uno. **No reutilizar los sonidos de Coucou.**
