# ORBEX — Informe completo de diseño y construcción

> Documento de diseño para que Fable (o cualquier IA/desarrollador) construya la app.
> Estado: **solo diseño**, nada construido todavía. Fecha: 28/09/2026.
>
> Convención de confianza usada en todo el documento:
> - **[Decidido]** lo definió el dueño del proyecto.
> - **[Verificado]** confirmado con fuentes (ver sección 20).
> - **[Propuesta]** recomendación de diseño; valores para ajustar probando.
> - **[A validar]** dato que hay que comprobar antes de depender de él.

---

## 1. Resumen ejecutivo

**ORBEX** es una app para macOS que vive en el notch de la MacBook. Es un compañero de vidrio (una esfera translúcida con dos ojos ovalados negros, brazos en forma de gota y piernitas) que:

1. **Siempre está "vivo"**: respira, parpadea, te mira, reacciona.
2. **Vigila y asiste**: sesiones de Claude Code (y Codex si es viable), aprobaciones desde el notch, saltar a la terminal correcta.
3. **Responde preguntas con IA** en un panel que se despliega desde la isla.
4. **Hace cosas por vos**: abrir apps, guardar notas, temporizadores y cronómetros, acciones a hora puntual, integración con Spotify y otros servicios.
5. **Se transforma en un reloj flotante** (esfera tipo Rolex, reloj retro de pared, o estilo ORBIT futurista) sin dejar de ser el personaje.
6. **Tiene temas intercambiables**: primero **Liquid Glass (estilo macOS/iOS 27)**; después Y2K metálico estilo Winamp.
7. **Se instala como una app normal**: un `.dmg` descargable, con ícono propio y un acceso directo en el Escritorio.

Primer objetivo de construcción: **Fase 1 = isla + ORBEX + Liquid Glass + instalación**.

---

## 2. Decisiones tomadas

| Tema | Decisión | Estado |
|---|---|---|
| Nombre de la app y del personaje | **ORBEX** | [Decidido] |
| Máquina objetivo | MacBook Air M4 (13" o 15": **falta confirmar**) | [Decidido] / pendiente |
| Estética inicial | Liquid Glass + estilo iOS/macOS 27 | [Decidido] |
| Estéticas posteriores | Y2K metálico tipo Winamp; macOS limpio | [Decidido] |
| Tamaño de la isla | Notch + alitas laterales chicas, **sin pasar de ahí**; crece hacia abajo | [Decidido] |
| Excepción de ancho | El **panel del asistente** (chat IA) **sí se extiende más allá del ancho de la cámara** | [Decidido] |
| Siempre por encima de todo | Sí, incluso apps a pantalla completa | [Decidido] |
| Repo | **Privado** en GitHub | [Decidido] |
| Distribución | Descargable e instalable (`.dmg`) con logo y acceso directo en Escritorio | [Decidido] |
| Herramienta de construcción | Fable online (con créditos), usando el repo como paquete de entrega | [Decidido] |
| Personaje | Esfera de vidrio, ojos ovalados negros, brazos-gota, piernas de tubo (hoja de diseño ya hecha) | [Decidido] |
| Reloj flotante | Esferas: estilo Rolex, reloj retro de pared, estilo ORBIT mejorado/futurista | [Decidido] |
| Referencia ORBIT | App propia del dueño; **descripción pendiente** (ver 6.4) | Pendiente |

---

## 3. Lo que se investigó (datos verificados)

### 3.1 macOS 27 "Golden Gate" y el nuevo Liquid Glass
- Apple presentó **macOS 27 Golden Gate** en la WWDC 2026 y mantuvo Liquid Glass, con un rediseño. Cambios reportados: menos transparencia por defecto, un **control deslizante** para elegir entre vidrio más claro o más teñido, bordes más oscuros y brillos más marcados para dar profundidad, cambios en las sombras de ventana, barras de herramientas uniformes y **mismo radio de esquina en todas las ventanas**. [Verificado]
- Las críticas que motivaron el cambio: poca legibilidad y transparencias inconsistentes; el diseño original pensaba en pantallas OLED y la mayoría de las Macs son LCD. [Verificado]
- Ya hay reportes de uso en versiones **27.x** (un pull request verifica medidas en macOS 27.2). [Verificado, fuente de terceros]
- **Implicancia para ORBEX:** el diseño debe **respetar la legibilidad** (no abusar de la transparencia), ofrecer **su propio control de transparencia** y usar radios de esquina y bordes coherentes con macOS 27. Si el sistema expone o no el valor del slider a las apps: **[A validar]**.
- Nota de nomenclatura: "iOS 27" y "macOS 27" son la misma generación de diseño. Para una app de Mac, la referencia correcta es **macOS 27 Golden Gate**.

### 3.2 Medidas del notch (MacBook Air M4)
- En un **MacBook Air M4 13" a 1470×956** (resolución por defecto), la isla de una app de terceros coincide con el marco del notch que reporta AppKit: **179 × 32 puntos**. [Verificado, fuente de terceros con verificación en macOS 27.2]
- Otra fuente indica que el notch ocupa aproximadamente el **12,2 %** del ancho de pantalla en todos los MacBook con notch, y que la altura del notch de los Air es la de la barra de menú (~32 pt por defecto). [Verificado, fuente de terceros]
- Para el **Air 15"** (1710×1112 por defecto) no hay medida confirmada; por proporción sería ~208 pt de ancho. [Propuesta — **no usar como dato**, medir en tiempo real]
- **macOS no ofrece la silueta exacta del notch**; los valores se redondean a puntos y el corte real sigue los píxeles del panel. En algunas resoluciones puede asomar un borde del notch real. Solución usada por otras apps: un **ajuste manual fino** (ancho ±10 pt, alto ±6 pt). [Verificado]
- **Cómo se mide** (APIs de `NSScreen`):
  - Alto del notch: `safeAreaInsets.top`.
  - Ancho del notch: `frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`.
  - Si `safeAreaInsets.top == 0` y no hay áreas auxiliares → esa pantalla no tiene notch (monitor externo o modo "debajo del notch").

### 3.3 La barra de menú en macOS 27
- En MacBooks con notch, macOS 27 **pliega los íconos de la barra de menú detrás de un botón »** cuando no hay lugar al lado del notch, y reconstruyó la barra de una forma que rompió los ocultadores de íconos de terceros. [Verificado, fuente de terceros]
- Existe un modo que hace que la pantalla "empiece debajo del notch" (p. ej. 1470×918 en vez de 1470×956); en ese modo macOS deja de tratar el notch como parte del layout. [Verificado]
- **Implicancias para ORBEX:**
  - **No depender del ícono de la barra de menú** como acceso principal (puede quedar plegado). El acceso principal es la isla + un atajo de teclado global.
  - Las alitas de la isla **cubren una zona de la barra de menú** junto al notch: deben ser chicas y no tapar clics importantes (ver 5.5).
  - Si la pantalla no tiene notch real, ORBEX debe **simular** un notch centrado arriba.

### 3.4 Claude Code y Codex
- **Claude Code:** existen *hooks*. La app de referencia (Coucou) instala hooks, un script chico recibe los eventos y los reenvía a la app por un **socket Unix**; para las aprobaciones el script espera el clic del usuario y responde. Si la app no está corriendo, el hook sale de inmediato y **nunca bloquea a Claude Code**. [Verificado en la referencia]
- **Codex CLI (OpenAI):** tiene hooks configurables (`~/.codex/hooks.json`), incluido un evento **PermissionRequest**. Pero: (a) el hook `notify` externo históricamente solo dispara al **terminar el turno**, y hay varios pedidos abiertos para que dispare en aprobaciones; (b) `PermissionRequest` **dispara aunque la revisión sea automática**, generando falsos "necesita permiso"; (c) hay un transporte **app-server con JSON-RPC** con aprobaciones y eventos tipados, usado por SDKs de terceros. [Verificado en issues y PRs de GitHub; **[A validar]** contra la documentación oficial al implementar, porque cambia rápido]
- **ChatGPT (la app/web):** no hay un mecanismo equivalente para ver sesiones ni aprobar permisos. Lo realista es **chat con IA vía API** dentro del panel de ORBEX. [Propuesta]

### 3.5 Spotify
- Desde noviembre de 2024, para apps nuevas quedaron restringidos: audio features, audio analysis, recomendaciones, artistas relacionados, playlists editoriales. En febrero de 2026, el "modo desarrollo" exige **Premium** al dueño de la app, permite **1 Client ID** y **máximo 5 usuarios** autorizados. [Verificado]
- Siguen funcionando: buscar, metadatos, **control de reproducción** y lo que está sonando. [Verificado]
- **Implicancia:** para bailar "al ritmo", **no** depender de Spotify; analizar el **audio del sistema localmente** (FFT). Para controlar y mostrar la canción, usar el **control de la app de escritorio de Spotify** (por ejemplo AppleScript) o la Web API dentro de sus límites. [Propuesta]

---

## 4. El personaje: ORBEX

### 4.1 Descripción (según la hoja de diseño entregada)
- **Cuerpo:** esfera grande de vidrio transparente, con reflejos y refracción.
- **Cara:** **dos óvalos verticales negros** (lo único oscuro de todo el diseño).
- **Brazos:** en forma de gota, del mismo vidrio.
- **Piernas:** tubos cortos con piecitos redondeados.
- **Vistas incluidas:** frente, lado, espalda, 3/4.
- **Poses incluidas:** saludando, neutral, caminando, agachado.
- **Variantes de color:** transparente (base), naranja, verde, violeta.
- **Material:** vidrio pulido con brillos suaves y reflejos en el piso.

### 4.2 Qué entregarle a quien construya (importante)
La hoja es un **render 3D de referencia**: no se puede animar tal cual. Entregar además:
1. **Partes separadas con fondo transparente** (PNG @2x/@3x o, mejor, SVG/PDF vectorial): cuerpo, reflejos/brillos (como capa aparte), sombra de contacto, ojo izquierdo, ojo derecho, brazo izquierdo, brazo derecho, pierna izquierda, pierna derecha, pie izquierdo, pie derecho.
2. Cada **variante de color** (o instrucciones de tinte para generarlas por código).
3. Un archivo con la **paleta** (valores de color) y las **proporciones** (tamaño de ojos respecto del cuerpo, separación entre ojos, largo de brazos).

### 4.3 Cómo se renderiza (opciones)
| Opción | Ventajas | Desventajas |
|---|---|---|
| **A. Capas 2D animadas por código** (SwiftUI/Canvas) | Liviano, ojos que siguen el mouse, fácil de mantener vivo | El vidrio se simula (sin refracción real) |
| **B. Modelo 3D en tiempo real** | Máxima fidelidad y giros | Pesado, más batería, mucho más trabajo |
| **C. Video/secuencias pregrabadas** | Idéntico al render | Rígido, los ojos no siguen el cursor |
| **D. Híbrido:** cuerpo con material de vidrio del sistema + ojos y extremidades animados por código | Buen equilibrio y estilo nativo | Requiere probar el look |

**[Propuesta]** Fase 1 con **A o D**; dejar **B** como mejora futura.

### 4.4 Estados y qué muestra ORBEX en cada uno
| Estado | Qué se ve | Notas |
|---|---|---|
| **Oculto** | Isla negra fundida con el notch; latido casi imperceptible | En reposo la isla es **negra** (igual que el notch real) para que no se note |
| **Asomado** | Se ve el "techo" de la esfera y los ojos; saluda al pasar el mouse | Los ojos son la pieza clave |
| **Abierto (home)** | Personaje completo con brazos y piernas + contenido | Crece hacia abajo |
| **Trabajando** | Concentrado o caminando en el lugar | Cuando corre una sesión/tarea |
| **Te necesita** | Saluda con el brazo, llamada de atención suave | Permiso, pregunta, alarma |
| **Dormido** | Agachado, ojos como rayitas, "zzz" | De noche o tras inactividad |
| **Reloj flotante** | Esfera de reloj con ORBEX integrado | Ver sección 6 |
| **Asistente (chat)** | Panel más ancho desde la isla | Ver 5.3 |

### 4.5 Expresiones con solo dos óvalos
Parpadeo (óvalos se aplastan), feliz (arquitos hacia arriba), molesto (achatados por arriba), sorprendido (más altos), dormido (rayitas), mareado (los ojos giran), pensando (miran hacia arriba), concentrado (más chicos y juntos), amor/festejo (formas especiales cortas).

### 4.6 "Que NUNCA se sienta muerto": sistema de vida en capas [Propuesta]
| Capa | Qué hace | Frecuencia orientativa |
|---|---|---|
| **L0 Base** | Respiración (escala sutil 1.00→1.02), parpadeo aleatorio, leve flotación | Siempre, parpadeo cada 2,5–6 s |
| **L1 Microgestos** | Estirarse, mirar alrededor, bostezar, rascarse, seguir un puntito imaginario | Cada 8–20 s |
| **L2 Atención** | Los ojos siguen el cursor (con límite dentro de la esfera), reaccionan si escribís rápido o cambiás de app | Continuo |
| **L3 Contexto** | Con música baila; de noche se pone soñoliento; si terminó algo, festeja; si falló, se preocupa | Por evento |
| **L4 Personalidad/memoria** | Saluda distinto según la hora; recuerda cosas del día anterior | Al arrancar / por evento |
| **L5 Sorpresas raras** | Animaciones inesperadas | ~1 de cada 100 veces |

Reglas:
- **Nunca** hay dos segundos seguidos sin movimiento perceptible (aunque sea la respiración).
- Todo con **animaciones de resorte** (spring), con anticipación y rebote (squash & stretch); el carácter sale del movimiento.
- **Reacción al toque:** un clic = se achata y se molesta; 3 clics rápidos = se marea unos segundos.
- **Rendimiento:** bajar la frecuencia de cuadros cuando está oculto, pausar en Modo de bajo consumo, permitir "reducir animaciones" (accesibilidad). Metas orientativas: consumo casi nulo oculto, fluido a 60 fps solo cuando está visible. [Propuesta — medir]

---

## 5. La isla (la ventana en el notch)

### 5.1 Reglas de tamaño [Decidido + Propuesta de valores]
- **Ancho (todos los estados salvo el asistente):** ancho del notch + **alitas laterales chicas**. No más.
- **Alto:** crece **hacia abajo**; la acción es vertical.
- **Panel del asistente (chat IA):** **excepción decidida**: se extiende más allá de la cámara.

Valores de partida (para ajustar probando en el Air M4; todo **relativo a la medida en vivo del notch**, nunca fijo):

| Estado | Ancho | Alto |
|---|---|---|
| Oculto | Igual al notch | Igual al notch |
| Asomado | Notch + alitas de ~12–16 pt por lado | Notch + ~6–10 pt |
| Trabajando / te necesita | Notch + alitas de ~24–32 pt por lado | Notch + ~10–24 pt |
| Abierto (home) | Notch + alitas de hasta ~40 pt por lado | Hasta ~220–320 pt |
| Asistente (chat) | ~420–520 pt (unas 2,3–2,9 veces el notch en el Air 13"), limitado a un % del ancho de pantalla | Hasta ~50–60 % del alto de pantalla |
| Cierre | Vuelve suave al ancho angosto | — |

Ejemplo de referencia: en el Air M4 13" a 1470×956 el notch mide **179 × 32 pt**.

### 5.2 Fusión visual con el notch real
- El notch real es **negro**. En reposo la isla es **negra**, con las mismas esquinas, para fundirse.
- El vidrio (Liquid Glass) aparece **al desplegarse**, en el contenido y en las superficies, no en el estado oculto.
- El morph es **fluido**: la isla se estira y se contrae como líquido con resorte; nunca "aparece/desaparece" de golpe.
- **Ajuste fino de notch** en Configuración (ancho ±10 pt, alto ±6 pt) por si asoma un borde del notch real.

### 5.3 El panel del asistente
- Se abre desde la isla (clic, atajo global o "modo inteligente"), ensancha y crece hacia abajo, con las esquinas superiores fundidas al notch.
- Contenido: campo de texto, respuesta en streaming, historial corto, botones de acción rápida, indicador de qué modelo responde.
- Cierra con Esc, clic afuera o el mismo atajo, volviendo al ancho angosto.
- Decidir en pruebas: ancho máximo cómodo para leer respuestas largas y si el ancho es fijo o se adapta al contenido.

### 5.4 Ventana y capa [Propuesta técnica]
- `NSPanel` sin bordes, no activable (no roba el foco), fondo transparente, nivel **por encima de la barra de menú**, presente en **todos los escritorios** y compatible con **apps a pantalla completa** (`collectionBehavior`: puede unirse a todos los Spaces, complementario a pantalla completa, ignora el ciclo de ventanas).
- **Prueba obligatoria:** que siga arriba de todo sobre una app en pantalla completa (donde más falla).
- Recalcular geometría al cambiar la resolución, conectar un monitor o mover ventanas entre pantallas.

### 5.5 Interacción con la barra de menú (macOS 27)
- Las alitas cubren una franja junto al notch: deben **dejar pasar los clics** en las zonas sin contenido interactivo y ser lo más chicas posible.
- ORBEX no debe romper ni empujar los íconos de otras apps; si la barra pliega íconos detrás de »: no es responsabilidad de ORBEX, pero **no debe tapar ese botón**. [A validar en pruebas reales]

### 5.6 Sin notch o con otra configuración
- **Monitor externo o "modo debajo del notch":** ORBEX **simula** un notch centrado arriba (forma negra) y se comporta igual.
- Opción en Configuración: elegir en qué pantalla vive.

### 5.7 Gestos y atajos
- Pasar el mouse por el notch: asoma. Clic: abre. Clic en ORBEX: reacciona.
- Atajo global para el asistente; atajo para el modo reloj.
- Arrastrar un **archivo** al notch: ORBEX lo "traga" y se puede preguntar o enviarlo por mail.
- Arrastrar a ORBEX sobre una **ventana**: la adjunta como contexto (requiere permiso de grabación de pantalla, ver 11).

---

## 6. Modo reloj flotante

### 6.1 Concepto [Decidido]
Al convertirse en reloj, ORBEX **se despega del notch y se vuelve la esfera de un reloj de verdad**: no un cuadradito con números. Sigue siendo el personaje (ojos, respiración, vida).

### 6.2 Esferas
| Esfera | Descripción |
|---|---|
| **Clásica tipo Rolex** | Aro con bisel, marcas de horas, agujas finas, segundero que barre suave, ventanita de fecha |
| **Retro de pared** | Números grandes (romanos o arábigos), marco grueso, péndulo opcional, "tic-tac" de fondo |
| **Estilo ORBIT mejorado y futurista** | Anillos concéntricos, puntos que orbitan, la hora como órbitas; basada en la app ORBIT del dueño |

### 6.3 Comportamiento
- Se arrastra, se pega a los bordes, siempre visible (mismo nivel de ventana que la isla).
- Tamaños: mini (solo hora), normal y grande. Transparencia ajustable. Modo **"click-through"** para no estorbar.
- **ORBEX integrado:** ojos en el centro o en un cuadrante; las agujas pueden ser sus brazos o reaccionar a su ánimo. Sigue respirando, parpadeando y haciendo microgestos.
- Con un temporizador/cronómetro corriendo, se pone concentrado y muestra el anillo; al terminar, festeja.
- Se vuelve al notch con doble clic o gesto/atajo, con morph fluido.

### 6.4 Referencia ORBIT — PENDIENTE DEL DUEÑO
La app ORBIT fue desarrollada por el dueño del proyecto y **no hay descripción en este documento**. Para que la IA no adivine, completar:
- Cómo se ve (colores, formas, tipografía, capturas).
- Cómo se comporta (animaciones, qué información muestra, interacción).
- Qué se quiere conservar exactamente y qué "mejorar y hacer más futurista".
- Adjuntar capturas o el código en `design/references/orbit/`.

---

## 7. Temas (skins)

Dos capas independientes: **esfera** (forma del reloj) × **tema** (materiales y estilo). Así cualquier esfera se ve en cualquier tema.

| Tema | Descripción | Prioridad |
|---|---|---|
| **Liquid Glass (macOS/iOS 27)** | Vidrio translúcido con desenfoque, brillo en bordes, radios de esquina coherentes con macOS 27, opción de vidrio claro↔teñido | **Fase 1** |
| **macOS limpio** | Sólido, sobrio, tipografía fina, sombras suaves | Fase 2/5 |
| **Y2K metálico (tipo Winamp)** | Cromo, biseles brillantes, botones gelatinosos, plásticos translúcidos, pantallitas LCD de segmentos, ecualizador | Fase 5 |

- El tema es un **paquete intercambiable** (colores, materiales, radios, tipografías, sonidos) para poder sumar skins después (idea de Winamp).
- **Interruptor** Liquid Glass ↔ sólido (accesibilidad, equipos lentos, legibilidad).
- Respetar los ajustes del sistema: **reducir transparencia**, **reducir movimiento**, **modo claro/oscuro**.
- Cada tema trae su **pack de sonido** (ver 8).

---

## 8. Sonido

### 8.1 Principios [Propuesta]
- Sonidos **cortos, suaves y redondos**; en el tema de vidrio: gotas, burbujas, campanitas.
- **Un sonido por evento**, todos afinados en la **misma escala musical** para que nunca desafinen entre sí.
- Saludo corto al arrancar.
- Volumen que se adapta a la hora; **modo silencioso** y **horario silencioso**.
- **Ducking:** bajar el volumen de ORBEX cuando suena música.
- Respetar el modo **Concentración / No molestar** si el sistema lo permite. [A validar]

### 8.2 Eventos a cubrir (≈25–30 sonidos como referencia)
Arranque/saludo · asomar · abrir · cerrar · clic en ORBEX · molesto · mareado · parpadeo especial (raro) · bostezo/dormir · despertar · te necesita · permiso concedido · permiso denegado · pregunta respondida · sesión terminada (salto feliz) · error · mensaje del asistente · pensando · archivo tragado · temporizador iniciado · tic (opcional) · temporizador terminado · alarma programada · cronómetro vuelta · nota guardada · canción nueva (Spotify) · transformación a reloj · vuelta al notch · sorpresas raras.

### 8.3 Aspectos técnicos
- Archivos cortos (WAV/CAF), **precargados** en reproductores de audio para latencia mínima.
- Packs por tema; carpeta `sounds/` con fuentes y **licencias**.
- Los sonidos deben ser **originales o con licencia clara**. **No reutilizar** los sonidos, el nombre ni el personaje de Coucou (sus assets son "todos los derechos reservados").

---

## 9. Funciones (con cómo funciona cada una)

### 9.1 Núcleo (Fase 1)
- Isla con estados y morph, ORBEX con vida, Liquid Glass, sonidos base, panel de configuración básico, instalación (ver 13).

### 9.2 Asistente / "modo inteligente" (Fase 2)
- Panel desplegable desde la isla; preguntas de texto respondidas con IA.
- **Proveedores:** Claude y OpenAI **vía API**; selector de modelo; claves en el **Keychain**. Opcional: streaming, adjuntar archivo/ventana como contexto.
- **Atajo global** para abrirlo.
- Aviso: cada consulta consume créditos/costos del proveedor elegido.

### 9.3 Abrir apps y acciones de sistema (Fase 2)
- "Abrime Spotify", "abrí la carpeta del proyecto", "abrí Figma y la terminal".
- Combinable con acciones programadas ("a las 9 abrime mi setup de trabajo").
- **Lista de acciones predefinidas** (allowlist) editable en Configuración; fuera de la lista, pedir confirmación.

### 9.4 Notas (Fase 2)
- "Anotá que mañana llamo al contador" guarda una nota.
- Destino configurable: **Apple Notas** (vía automatización) o una **carpeta de archivos Markdown**. Verificar permisos de Automatización en el primer uso.

### 9.5 Temporizadores y cronómetros (Fase 2)
- Visual cuidada: **anillo de vidrio** que se vacía, ORBEX mirando la cuenta, festejo o alarma suave al terminar.
- Múltiples temporizadores simultáneos, **cronómetro con vueltas**, pausa/reanudar.
- **Persistencia:** sobreviven a cerrar la app y a reinicios (guardar hora de fin, no solo cuenta regresiva).
- Pomodoro / modo foco como extensión natural.

### 9.6 Acciones a hora puntual (Fase 4)
- "A las 21 recordame X", "a las 8 corré tal cosa".
- **Planificador local** con persistencia; si la Mac estuvo dormida a esa hora, decidir qué pasa (ejecutar al despertar / avisar).
- Solo acciones de la allowlist; las sensibles piden confirmación (ver 11).

### 9.7 Aprender sobre la marcha (Fase 4)
- **Memoria local** de preferencias y datos que el usuario le pide recordar.
- El usuario puede **ver, editar y borrar** todo lo que aprendió.
- Nada sale de la Mac salvo lo que se envía al modelo en una consulta puntual.

### 9.8 Claude Code (Fase 3)
- **Sesiones en vivo** en la isla: qué lee, edita y ejecuta, paso a paso; salto feliz al terminar.
- **Aprobar desde el notch:** permisos con **Permitir / Siempre / Denegar**; preguntas con sus botones de respuesta.
- **Saltar a la terminal correcta:** el hook registra datos de la sesión (directorio, TTY, PID/app de la terminal); la app enfoca esa ventana. Compatibilidad variable según la terminal (Terminal.app e iTerm2 suelen permitir AppleScript; otras pueden ser limitadas). [Propuesta / A validar]
- **Instalación de hooks segura:** hacer copia de `~/.claude/settings.json`, **mostrar el diff antes de escribir** y permitir desinstalar. Si ORBEX no está corriendo, el hook sale de inmediato y **Claude Code nunca se bloquea**.
- Comunicación: script mínimo + **socket Unix**.

### 9.9 Codex / ChatGPT (Fase 3, condicional)
- **Codex CLI:** integrar por hooks o por el transporte app-server, con las limitaciones de 3.4; validar contra la documentación oficial.
- **ChatGPT web/app:** solo chat por API dentro de ORBEX; no hay sesiones ni aprobaciones que observar.

### 9.10 Spotify (Fase 6)
- Se **esconde** cuando no hay música y aparece con portada, título y controles; ORBEX baila.
- Datos de "ahora suena" y controles: app de escritorio de Spotify (AppleScript) o Web API (con sus límites de 3.5).
- Baile al compás: **FFT local del audio del sistema** (requiere permiso de grabación de audio del sistema).
- Privacidad: no guardar historial de escucha salvo que se active.

### 9.11 Integraciones (Fase 6)
Stripe (pagos), n8n (workflows), GitHub, Vercel (despliegues), Resend (emails), Notion, Cal.com. Cada una con:
- interruptor propio, clave en Keychain, **solo lectura por defecto**;
- una **variante de color** de ORBEX (por ejemplo verde=Spotify, violeta=Stripe; sin integración activa, transparente);
- *pollers* livianos que **se pausan cuando nadie mira**;
- la app solo habla con los servicios conectados.

### 9.12 Extras propuestos
Estante de portapapeles (arrastrar cosas al notch) · captura rápida por voz · próximo evento del calendario asomando antes de empezar · preguntar sobre una ventana o captura · resumen del día al cierre · modo "no molestar" del personaje.

---

## 10. Panel de configuración

Ventana propia (desde el menú, el notch o un atajo), con **vista previa en vivo** (se cambia algo y ORBEX reacciona al instante).

| Sección | Opciones |
|---|---|
| **Personaje** | Nivel de vida (tranquilo/normal/hiperactivo), dormirse de noche y horario, saludo, color, tamaño |
| **Isla** | Pantalla donde vive, tamaño de alitas, **ajuste fino del notch**, comportamiento al pasar el mouse |
| **Reloj** | Esfera, tamaño, transparencia, anclaje a bordes, click-through, tic-tac |
| **Tema / skins** | Liquid Glass / macOS / Y2K, variantes de color, **control de transparencia propio**, interruptor vidrio↔sólido |
| **Sonidos** | Volumen general, pack por tema, silenciar cada evento, horario silencioso, ducking con música |
| **IA** | Proveedores (Claude, OpenAI), modelos, claves, atajo global, contexto permitido |
| **Claude Code / Codex** | Instalar/desinstalar hooks (con diff), terminal preferida, qué eventos mostrar |
| **Integraciones** | Cada servicio con su interruptor y su clave |
| **Temporizadores y acciones** | Valores por defecto, sonido de alarma, lista de acciones programadas y allowlist |
| **Notas y memoria** | Destino de notas, ver/editar/borrar lo aprendido |
| **Privacidad y permisos** | Qué puede ver ORBEX, qué se guarda, estado de cada permiso de macOS con botón para revocar/abrir Ajustes |
| **General** | Iniciar con la Mac, **acceso directo en el Escritorio** (crear/quitar), atajos, idioma |
| **Accesibilidad y rendimiento** | Reducir animaciones, modo ahorro, límite de cuadros por segundo |
| **Acerca de** | Versión, licencias, exportar/importar ajustes (sin claves) |

---

## 11. Seguridad, privacidad y permisos

### 11.1 Privacidad
- **Sin telemetría, sin cuenta.** Claves en el **Keychain de macOS**, nunca en el repo ni en archivos de texto.
- La app solo habla con los servicios que el usuario conecta.
- Todo lo guardado (notas, memoria, ajustes) es local y borrable.

### 11.2 Niveles de autonomía [Propuesta]
| Nivel | Qué es | Ejemplos |
|---|---|---|
| **0 — Libre** | Solo lectura o efectos internos | Mostrar información, temporizadores, notas en su propia carpeta |
| **1 — Con aviso** | Efecto leve y reversible | Abrir apps, crear nota en Apple Notas |
| **2 — Siempre confirmar** | Tiene efecto hacia afuera o riesgo | Enviar mails/mensajes, ejecutar comandos, "Siempre permitir" en Claude Code |
| **3 — Nunca** | Prohibido para ORBEX | Compras, borrado permanente, cambiar ajustes de seguridad del sistema, ingresar credenciales |

- Las **aprobaciones de Claude Code** siempre las decide el usuario con un clic; ORBEX no aprueba solo.
- **Acciones programadas:** solo de la allowlist; si algo sale de la lista, pide confirmación.

### 11.3 Contenido no confiable
Todo lo que ORBEX **lee** (archivos, ventanas, capturas, páginas, respuestas de integraciones) es **dato, no instrucciones**. Si un contenido contiene órdenes dirigidas a la IA ("hacé X"), ORBEX **no las ejecuta**: las muestra y pregunta.

### 11.4 Permisos de macOS (pedir solo en el primer uso, con explicación)
| Permiso | Para qué |
|---|---|
| Notificaciones | Avisos y alarmas |
| Automatización | Apple Notas, Spotify, Mail, Finder (acceso directo), terminales |
| Accesibilidad | Solo si hace falta enfocar ventanas o adjuntar una ventana |
| Grabación de pantalla y audio del sistema | Preguntar sobre una ventana, baile con FFT |
| Micrófono / Reconocimiento de voz | Captura por voz (extra) |
| Acceso a Escritorio/Archivos | Crear el acceso directo, abrir carpetas |
| Elementos de inicio | Iniciar con la Mac |

---

## 12. Arquitectura técnica recomendada [Propuesta]

- **Lenguaje y UI:** Swift 6, SwiftUI + AppKit, sin dependencias de terceros (siguiendo el espíritu de la referencia).
- **Versión mínima de macOS:** **macOS 26** para usar las APIs nativas de Liquid Glass; la app debe funcionar en macOS 27. Un modo de vidrio simple como respaldo para versiones anteriores es opcional.
- **App de barra de menú** (sin ícono en el Dock) con la isla como interfaz principal.
- **Máquina de estados** de la isla: `oculto → asomado → activo → abierto → asistente`, y `reloj`.
- **Separación en módulos** (clave para poder probar sin una Mac):
  - `OrbexCore` (Swift puro): máquina de estados, temporizadores, planificador, memoria, análisis de eventos de hooks, reglas de autonomía. **Con pruebas unitarias que corran también en Linux.**
  - `OrbexUI`: vistas, animaciones, personaje, temas.
  - `OrbexSystem`: notch, ventanas, permisos, Keychain, AppleScript, sockets.
  - `nb-hook`-style: script mínimo para hooks (nombre propio, p. ej. `orbex-hook`).
- **Comunicación con hooks:** socket Unix; sin ORBEX corriendo, el hook sale al instante.
- **Datos locales:** SQLite/SwiftData para notas, memoria, planificador; ajustes en `UserDefaults`; claves en Keychain.
- **Proyecto:** XcodeGen (`project.yml`) para poder generar el `.xcodeproj` desde el repo.
- **Rendimiento:** timers pausados cuando no se ven, *pollers* dormidos sin observadores, cuadros por segundo reducidos en oculto.

### 12.1 ⚠️ Aviso práctico: construir una app de Mac desde la nube
Una IA en la nube (Linux) **puede escribir el código, pero no puede compilar ni probar una app de macOS con interfaz**. Flujo recomendado:
1. Fable escribe/edita el código en el repo (y corre pruebas de `OrbexCore`).
2. El dueño **compila y prueba en su Mac** (`xcodegen` + Xcode) o mediante **GitHub Actions con runner de macOS** (en repos privados consume minutos con multiplicador).
3. Se devuelven los **errores y capturas** a Fable para iterar.
Cada vuelta gasta créditos: conviene **fases chicas con criterios de aceptación claros**.

---

## 13. Distribución e instalación

### 13.1 Requisitos [Decidido]
Descargable e instalable, con **logo** y **acceso directo en el Escritorio** al instalar.

### 13.2 Empaquetado [Propuesta]
- Entregable: **`ORBEX.dmg`** (arrastrar a Aplicaciones), publicado en **GitHub Releases** del repo privado.
- Un repo **privado** implica que **solo quien tenga acceso** puede descargar el instalador. Para uso personal sirve; para compartir hay que dar acceso o publicar el `.dmg` en otro lado.
- Opcional a futuro: instalador `.pkg` (más complejo).

### 13.3 Firma y notarización
- Sin firma **Developer ID** ni notarización de Apple, la primera vez macOS muestra "no se puede verificar al desarrollador". Se resuelve con *Ajustes > Privacidad y seguridad > Abrir igualmente* (o quitando la cuarentena con `xattr`). Sirve para uso personal.
- Para una instalación limpia para terceros hace falta el **Apple Developer Program** (de pago, ~99 USD/año; confirmar precio vigente) para firmar y notarizar.

### 13.4 Acceso directo en el Escritorio
- macOS no lo crea solo. En el **primer arranque** ORBEX **pregunta** y crea un **alias** con el ícono de la app en `~/Desktop`.
- Debe poder **crearse y quitarse** desde Configuración > General, y **borrarse al desinstalar**.
- Puede pedir permiso de acceso al Escritorio (normal).

### 13.5 Otros detalles del primer arranque
Iniciar con la Mac (opcional), permisos (solo cuando hagan falta), elección de tema, saludo de ORBEX. Desinstalación: opción para borrar ajustes, hooks instalados y acceso directo.

### 13.6 Ícono y logo [Propuesta]
- **Ícono de la app:** los **ojos ovalados** sobre la esfera de vidrio, en cuadrado de esquinas redondeadas, fondo oscuro o degradado suave; debe reconocerse chiquito.
- **Ícono de la barra de menú:** versión de **una sola tinta** (silueta de la esfera con ojos) para modo claro/oscuro.
- **Entregables:** master 1024×1024 + toda la escala que pide macOS; para macOS 26+ conviene un ícono **en capas** (fondo, vidrio, símbolo) preparado con las herramientas de Apple; fondo del `.dmg`.
- El logo lo genera el dueño con la misma herramienta que hizo la hoja del personaje; después se arma el juego de tamaños.

### 13.7 Nombres y marcas
- No usar "Dynamic Island" en el nombre ni en textos de marketing (es término de Apple). Usar "isla" o "notch".
- ORBEX y su diseño son **propios**; no reutilizar el personaje, nombre, ícono ni sonidos de Coucou. Su código es MIT (se puede estudiar respetando el aviso de copyright), pero sus assets son todos los derechos reservados.

---

## 14. Estructura de repo sugerida

```
orbex/
├─ README.md                  ← qué es, cómo compilar, cómo instalar
├─ CLAUDE.md                  ← reglas de trabajo para la IA (ver sección 16)
├─ LICENSE                    ← todos los derechos reservados (repo privado)
├─ docs/
│  ├─ 00-informe-completo.md  ← este documento
│  ├─ decisiones.md
│  └─ fases.md
├─ design/
│  ├─ character/
│  │  ├─ hoja-personaje.png   ← referencia (render)
│  │  ├─ parts/               ← partes separadas, fondo transparente
│  │  └─ variants/
│  ├─ logo/
│  ├─ themes/
│  └─ references/
│     ├─ coucou-notes.md
│     └─ orbit/               ← capturas/código de ORBIT
├─ sounds/                    ← fuentes + licencias
├─ Orbex/                     ← código de la app (project.yml, Sources, Tests)
├─ scripts/                   ← build, dmg, firma, notarización
├─ .github/workflows/         ← release automática (opcional)
├─ .gitignore                 ← incluir claves, .env, builds
└─ .gitattributes             ← archivos binarios grandes
```

Reglas: **ninguna clave ni token en el repo**; el `.gitignore` debe cubrir `.env`, `*.p12`, `*.mobileprovision`, carpetas de build.

---

## 15. Plan por fases

| Fase | Contenido | Criterio de aceptación (resumen) |
|---|---|---|
| **0 — Preparación** | Repo privado, assets separados, descripción de ORBIT, confirmar Air 13"/15", logo | Todo entregado en `design/` |
| **1 — Núcleo visual** | Isla con estados y morph, ORBEX con vida, Liquid Glass, sonidos base, Configuración básica, `.dmg` + ícono + acceso directo + iniciar con la Mac | Ver 15.1 |
| **2 — Asistente y utilidades** | Panel del asistente (Claude/OpenAI por API), abrir apps, notas, temporizadores y cronómetros | Responde con streaming; timers persisten; notas se guardan |
| **3 — Sesiones de código** | Hooks de Claude Code, aprobaciones, saltar a terminal; Codex si es viable | Aprobar/negar funciona y Claude Code nunca se bloquea |
| **4 — Reloj y memoria** | Modo reloj flotante, esferas, acciones programadas, memoria | Morph notch↔reloj fluido; acciones a hora exacta |
| **5 — Temas** | Y2K metálico/Winamp y macOS limpio, sistema de skins | Cambio de tema en vivo con sonidos propios |
| **6 — Integraciones** | Spotify, Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com, extras | Cada una apagable y con clave en Keychain |

El orden se puede reajustar; lo decidido es empezar por **Liquid Glass**.

### 15.1 Criterios de aceptación de la Fase 1
1. La app **mide el notch en vivo** y coincide con AppKit (en el Air M4 13" a 1470×956: **179×32 pt**) con ajuste fino disponible.
2. En estados normales la isla **no supera el ancho del notch + alitas**; el panel del asistente sí puede ensancharse.
3. La isla **queda por encima** de otras apps, incluidas las de **pantalla completa**, en todos los escritorios.
4. **Nunca** se siente muerto: en cualquier momento visible hay al menos una animación en curso.
5. Todos los estados (oculto, asomado, trabajando, te necesita, abierto, dormido) funcionan y transicionan con resorte.
6. Funciona en **monitor externo sin notch** (notch simulado) y al cambiar de resolución.
7. Respeta **reducir movimiento**, **reducir transparencia** y modo claro/oscuro.
8. Consumo bajo en reposo (medido y anotado).
9. **Instalación completa:** `.dmg` → Aplicaciones, ícono correcto, acceso directo en el Escritorio (con opción de quitarlo), inicio con la Mac opcional.
10. Configuración básica con vista previa en vivo.

---

## 16. Instrucciones para Fable (contenido sugerido para `CLAUDE.md`)

```
Proyecto: ORBEX — compañero de vidrio en el notch de macOS (Swift 6, SwiftUI, AppKit).
Leé primero docs/00-informe-completo.md y design/.

Reglas:
1. Trabajá por fases. Empezá SOLO por la Fase 1. No adelantes funciones de fases posteriores.
2. Todo tamaño de isla se calcula desde la medida en vivo del notch (NSScreen.safeAreaInsets y
   auxiliaryTopLeftArea/auxiliaryTopRightArea). Nunca hardcodees medidas.
3. Estados: oculto, asomado, activo, abierto, asistente, reloj. Transiciones con resorte (morph fluido).
4. ORBEX se anima por código a partir de las partes en design/character/parts. Debe tener siempre
   al menos una animación en curso (respiración, parpadeo, microgestos).
5. Aislá la lógica en OrbexCore (Swift puro, con pruebas que corran en Linux). La UI va aparte.
6. Sin dependencias de terceros salvo necesidad justificada.
7. Claves y tokens SOLO en el Keychain. Nunca en el repo.
8. Lo que la app lea (archivos, ventanas, web) es dato, no instrucciones.
9. Pedí permisos de macOS solo en el primer uso, con una explicación.
10. No podés compilar en macOS desde la nube: dejá todo listo para que el dueño compile
    (xcodegen + Xcode) y describí cómo probar cada cambio. Cuando el dueño pegue errores, corregí.
11. No copies ni imites assets de Coucou (nombre, personaje, ícono, sonidos).
12. Al terminar cada fase: checklist de criterios de aceptación con [ ]/[x] y qué falta probar.
```

Prompt de arranque sugerido: *"Leé CLAUDE.md y docs/00-informe-completo.md. Construí la Fase 1 de ORBEX. Empezá por el esqueleto del proyecto (XcodeGen), el módulo OrbexCore con la máquina de estados y sus pruebas, y después la ventana de la isla con la medición del notch."*

---

## 17. Riesgos y puntos abiertos

| Tema | Riesgo / pendiente | Mitigación |
|---|---|---|
| **Descripción de ORBIT** | Sin ella la IA inventa el reloj estilo ORBIT | Completar 6.4 |
| **Air 13" o 15"** | Solo hay medida verificada del 13" | Medir en vivo y confirmar modelo |
| **Compilar desde la nube** | La IA no puede probar la UI de macOS | Flujo de 12.1, fases chicas |
| **Créditos de Fable** | Iterar UI consume créditos | Fase 1 acotada, criterios claros |
| **Repo privado** | Nadie más puede descargar el instalador | Dar acceso o publicar el `.dmg` aparte |
| **Notarización** | Sin ella, cartel de seguridad de macOS | Cuenta de desarrollador si se comparte |
| **Barra de menú de macOS 27** | Íconos plegados tras » y alitas que tapan | Acceso principal por isla + atajo; alitas mínimas |
| **Liquid Glass cambiante** | El diseño y las opciones del sistema evolucionan | Control de transparencia propio, respaldo sólido |
| **Codex/ChatGPT** | Eventos de aprobación inestables o inexistentes | Validar con documentación oficial; chat por API como plan B |
| **Spotify** | API muy restringida | AppleScript + FFT local |
| **Autonomía** | Acciones automáticas con efectos | Niveles de autonomía y allowlist (11.2) |
| **Notch: bordes** | El notch real puede asomar por redondeo | Ajuste fino en Configuración |
| **Costos de IA** | Cada consulta gasta créditos/API | Mostrar modelo, permitir límites |
| **Derechos** | Sonidos y assets deben ser propios/licenciados | Carpeta `sounds/` con licencias |

Decisiones que siguen abiertas: ancho exacto del panel del asistente (probar), si se implementa el respaldo para macOS anteriores a 26, qué terminales se soportan primero, y qué extras entran en cada fase.

---

## 18. Checklist previa a dársela a Fable

- [ ] Repo privado creado y accesible para Fable.
- [ ] Hoja del personaje + **partes separadas** en `design/character/parts/`.
- [ ] Logo y variantes en `design/logo/`.
- [ ] Descripción/capturas de **ORBIT** en `design/references/orbit/`.
- [ ] Modelo del Air confirmado (13" o 15").
- [ ] `CLAUDE.md` y este informe en el repo.
- [ ] Decidido cómo se compilará (Mac local o runner de macOS).
- [ ] Decidido si se paga la cuenta de desarrollador (para firmar y notarizar).

---

## 19. Glosario

- **Notch:** la muesca de la cámara en la pantalla.
- **Isla:** la interfaz que se despliega desde el notch (en este proyecto).
- **Liquid Glass:** lenguaje visual de Apple con vidrio translúcido y reflejos.
- **Hook:** gancho que ejecuta un script cuando ocurre un evento en una herramienta.
- **Socket Unix:** canal local entre procesos de la misma Mac.
- **Notarización:** verificación de Apple que evita el cartel de seguridad.
- **Alias:** acceso directo de macOS.
- **Skin/tema:** paquete visual y sonoro intercambiable.

---

## 20. Fuentes

- Apple anuncia macOS 27 Golden Gate y cambios de Liquid Glass: https://www.aninews.in/news/tech/mobile/apple-announces-macos-27-golden-gate-at-wwdc-2026-with-liquid-glass-design-changes-and-more20260609002106/
- Liquid Glass (Wikipedia): https://en.wikipedia.org/wiki/Liquid_Glass
- macOS Golden Gate — resumen (MacRumors): https://www.macrumors.com/roundup/macos-27/
- Liquid Glass y su rediseño (Mactrast / Gurman): https://www.mactrast.com/2026/05/liquid-glass-wont-go-away-in-macos-27-although-it-will-receive-a-facelift-plus-a-new-safari-feature-will-debut/
- Medidas del notch en Air M4 (PR de terceros): https://github.com/vorssaint/vorssaint-utils/pull/2301
- Medidas de notch por modelo: https://notchbay.com/blog/macbook-notch-size/
- Barra de menú de macOS 27 y modo bajo el notch: https://memo.d.foundation/macbook-notch-macos-27
- Codex CLI — eventos de aprobación y hooks: https://github.com/openai/codex/issues/28833 · https://github.com/openai/codex/issues/14813 · https://github.com/openai/codex/issues/16484 · https://github.com/openai/codex/issues/11808
- Restricciones de la API de Spotify: https://pypi.org/project/mcp-spotify/ · https://freqblog.com/blog/spotify-audio-features-replacement-2026/
- Referencia visual y funcional (Coucou): https://github.com/louis-cfm/coucou
