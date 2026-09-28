# ORBEX — especificación del personaje

Referencia visual: [`hoja-personaje.webp`](hoja-personaje.webp) (render 3D entregado por el dueño).

ORBEX se **dibuja por código** en `Sources/Orbex/Character/`. Estas son las proporciones que usa el código, sacadas de la hoja (vista de frente). Todo es relativo al **diámetro del cuerpo `D`**.

## Proporciones

| Parte | Medida | Notas |
|---|---|---|
| Cuerpo | círculo de diámetro `D` | Vidrio azulado casi transparente |
| Ojos | óvalos verticales `0,075 D` de ancho × `0,20 D` de alto | Negro casi puro, con un brillo chiquito arriba |
| Separación de ojos | centros a `±0,14 D` del eje | Un poco por encima del centro: `y = −0,06 D` |
| Brazos | gota de `0,24 D` de ancho × `0,36 D` de alto | Pegados a los costados, parte ancha abajo; centro en `x = ±0,52 D`, `y = +0,10 D` |
| Piernas | tubo de `0,11 D` de ancho × `0,20 D` de alto | Centro en `x = ±0,17 D`, salen desde `y = +0,44 D` |
| Pies | cápsula `0,22 D` × `0,10 D` | Redondeados, un poco hacia adelante |
| Sombra de contacto | elipse `0,9 D` × `0,08 D` | Suave, en el piso |

## Material (vidrio)

- Relleno: degradado radial de blanco-celeste muy transparente (centro) a gris azulado (borde).
- Borde: línea fina clara (`rim light`), más brillante arriba a la izquierda.
- Reflejos: una curva ancha arriba a la izquierda (ventana), un punto brillante chico, y un reflejo tenue abajo a la derecha (luz rebotada).
- Refracción simulada: una sombra interna suave en la parte inferior del cuerpo.

## Variantes de color

| Nombre | Tinte (RGB aprox.) | Uso |
|---|---|---|
| Transparente (base) | `#D6E4F0` | Sin integración activa |
| Naranja | `#F2A04A` | |
| Verde | `#8DB86B` | Spotify |
| Violeta | `#B07CE8` | Stripe |

## Poses de la hoja

Saludando (brazo derecho arriba), neutral, caminando (brazo adelante, pierna atrás), agachado (cuerpo bajo, brazos apoyados). Vistas: frente, lado, espalda, 3/4.

## Reemplazar por assets

Si más adelante hay partes separadas (PNG @2x/@3x o SVG), van en `parts/` con estos nombres: `body`, `highlights`, `shadow`, `eye-left`, `eye-right`, `arm-left`, `arm-right`, `leg-left`, `leg-right`, `foot-left`, `foot-right`. El código dibuja cada parte en una función separada para poder reemplazarla una por una.
