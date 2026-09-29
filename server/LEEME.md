# Synchrony: Enlaza tu Mente

Juego cooperativo multijugador para **GitHub Pages + Render**. Interfaz en español, diseño vertical y horizontal, cartas de colores, animaciones, sonidos opcionales y salas sincronizadas en tiempo real. No necesita librerías externas ni una base de datos.

## 1. Probarlo en tu ordenador

Instala Node.js 22 o posterior. Descomprime el ZIP, abre una terminal en la carpeta `synchrony` y ejecuta:

```bash
node server.js
```

Abre `http://localhost:3000`. Abre otra ventana independiente o un navegador diferente para simular otro jugador. También puedes usar dos pestañas abiertas por separado (las sesiones se guardan por pestaña).

No abras `index.html` con doble clic: para conectar al servidor utiliza HTTP o HTTPS.

## 2. Subir los archivos a GitHub

1. Crea un repositorio, por ejemplo `synchrony`.
2. Sube **el contenido** de la carpeta `synchrony`, no el ZIP. `index.html`, `server.js` y `package.json` deben quedar en la raíz del repositorio.
3. Incluye también `game.js`, `app.js`, `styles.css`, `config.js`, `package-lock.json`, `icon.svg`, `manifest.webmanifest`, `render.yaml` y `.nojekyll`.
4. No hay claves secretas en estos archivos. No añadas credenciales al repositorio.

## 3. Crear el servidor en Render

En Render, selecciona **New → Web Service**, conecta tu repositorio y usa:

| Campo | Valor |
|---|---|
| Runtime | Node |
| Branch | main (o la rama donde subiste el juego) |
| Root Directory | Vacío si los archivos están en la raíz |
| Build Command | `npm ci` |
| Start Command | `node server.js` |
| Health Check Path | `/health` |

Elige el plan que prefieras. Render asigna el puerto automáticamente mediante `PORT`. No necesitas cambiarlo.

En **Environment**, añade:

```text
ALLOWED_ORIGINS=https://TU-USUARIO.github.io
```

Es el **origen**, sin `/synchrony/` y sin barra final. Para varios orígenes, sepáralos por comas. Si vas a abrir la web directamente desde Render, añade también `https://TU-SERVICIO.onrender.com`. En local puedes dejar la variable sin definir. Si está vacía, el servidor permite orígenes externos.

Espera a que el servicio aparezca como disponible. Copia su URL HTTPS, por ejemplo `https://synchrony-abc.onrender.com`. Comprueba que `https://synchrony-abc.onrender.com/health` responde `{"ok":true}`.

También se incluye `render.yaml` si prefieres configurar el servicio como Blueprint.

## 4. Enlazar la web con Render

Edita `config.js` en GitHub:

```js
window.SYNCHRONY_SERVER = "https://TU-SERVICIO.onrender.com";
```

Guarda el cambio. No añadas `/api` ni una barra final.

Como alternativa para probar, puedes introducir esa dirección en **Conexión al servidor** en la pantalla inicial. Se guardará solo en ese navegador. Para que todos tus amigos entren sin configurar nada, utiliza `config.js`.

## 5. Activar GitHub Pages

En el repositorio, abre **Settings → Pages**:

1. En Source elige **Deploy from a branch**.
2. Selecciona **main** y **/(root)**.
3. Pulsa **Save** y espera a que termine la publicación.
4. Abre la dirección que muestra GitHub, normalmente `https://TU-USUARIO.github.io/synchrony/`.

Crea una sala y comparte su enlace. Los enlaces usan `?sala=aB3xY9`, por lo que funcionan sin rutas especiales en GitHub Pages.

## Reglas implementadas

- Salas privadas: eliges el número total de jugadores, incluyéndote, y el tamaño de la baraja. No se aplica el límite online de 8. Debe haber al menos una carta por jugador. Ejemplo: 12 jugadores y 150 cartas.
- Búsqueda online: equipos de 2 a 8 jugadores, baraja de 100. Une salas públicas abiertas del mismo tamaño; si no hay ninguna, crea una y espera a más personas. No se añaden bots.
- Códigos alfanuméricos de 6 caracteres, **sensibles a mayúsculas y minúsculas**.
- El equipo debe completar las plazas antes de la primera cuenta atrás. Cada persona confirma que está lista; todos deben estar conectados.
- Primera ronda: una carta por participante; segunda: dos; tercera: tres, etc. Las cartas son únicas, aleatorias y se ordenan en tu mano.
- Si una ronda exigiría más cartas que la baraja, se reparte toda la baraja, dando como máximo una carta de diferencia entre jugadores. Nunca se duplica una carta.
- Todos juegan sin turnos. Pulsar una carta la juega inmediatamente. No hay confirmación por carta que frene la partida.
- Cada jugada debe ser la menor carta que quede entre todas las manos. El servidor lo verifica; cada cliente solo recibe su propia mano y el número de cartas de sus compañeros.
- Un fallo resta una de las **5 vidas**, cancela la ronda y exige que todos vuelvan a confirmar. Se repite la misma ronda con nuevas cartas. Agotar las vidas termina la partida.
- Una ronda completada aumenta una carta por persona para la siguiente.
- Victoria: completar una ronda jugando al menos `ceil(baraja × 0,79)` cartas. Con 100 cartas y 2 jugadores, normalmente se alcanza en la ronda 40 (80 cartas). Las cartas retiradas por desconexión no cuentan para ese objetivo.
- No hay descartes especiales ni otras acciones de cartas.

## Tiempos y desconexiones

- Antes de cada ronda y de cada reintento, todos pulsan **Estoy listo**. Después hay una cuenta atrás de **5 segundos**.
- Cada ronda dispone de `baraja × 5 segundos`, independientemente del número de cartas repartidas. Con 100 cartas, **500 segundos = 8 minutos y 20 segundos**. El reloj empieza al repartir, después de la cuenta atrás.
- Agotar el reloj resta una vida y permite repetir. Las esperas y los resultados no consumen el tiempo de la siguiente ronda.
- El servidor elimina la sala tras **900 segundos sin acciones de ningún jugador**. Entrar, confirmar, jugar o salir cuentan como acciones. Los mensajes automáticos de conexión no mantienen viva la sala indefinidamente. Este límite de inactividad es independiente del reloj de la ronda.
- Una desconexión conserva las cartas durante **30 segundos desde que se detecta**. Las caídas silenciosas se detectan por falta de latido en un máximo aproximado de 15 segundos. Tras el margen, las cartas se retiran; al volver, la persona observa sin participar hasta una nueva partida.
- En la sala inicial, una plaza desconectada se libera tras ese margen para que otra persona pueda ocuparla.
- Recargar la pestaña recupera la misma sesión. Cerrar definitivamente una pestaña puede perder la credencial local: no se usa una cuenta de usuario.
- Una desconexión durante la cuenta atrás la cancela y solicita nuevas confirmaciones.
- Salir voluntariamente retira las cartas inmediatamente.

## Funcionamiento técnico y límites prácticos

- Node.js estándar: servidor HTTP y eventos enviados por el servidor (SSE mediante `fetch`), con acciones HTTP autenticadas por un token aleatorio. No hace falta Socket.IO ni un CDN.
- El servidor es la autoridad. La revisión de la mesa impide que una petición repetida o una pulsación basada en un estado antiguo reste una vida por accidente. Si dos jugadas se solapan, puede pedirse que uno vuelva a pulsar.
- Las salas se guardan **en memoria**. Reiniciar, redesplegar o suspender el proceso elimina las salas existentes. Usa **una sola instancia** del servicio. Para varias instancias o persistencia entre reinicios habría que añadir un almacén compartido.
- El plan gratuito de Render puede suspender el servicio tras un periodo sin tráfico y tardar al volver a arrancar. La web admite hasta 90 segundos para las peticiones de entrada. No se garantiza disponibilidad continua en ese plan.
- No existe un límite de 8 participantes en las privadas; por protección de recursos, esta versión admite barajas de hasta **100.000 cartas** y hasta 1.000 salas simultáneas. Eso es una validación técnica, no una promesa de rendimiento para ese volumen. Los grupos grandes requieren dimensionar el servidor. El límite de baraja está en `game.js` (`maxDeck`) y en `index.html`.
- El sonido comienza desactivado y se activa con el botón musical. Se respeta la preferencia de movimiento reducido.
- No hay fuentes externas, analítica ni anuncios.

## Comprobar las reglas

```bash
npm test
```

Las pruebas incluidas cubren reparto, orden, vidas, reintentos, reloj, desconexión, privacidad de manos, victoria, barajas grandes y solicitudes repetidas.

## Archivos principales

| Archivo | Función |
|---|---|
| `index.html`, `styles.css`, `app.js` | Interfaz estática para GitHub Pages |
| `config.js` | URL del servidor Render |
| `server.js` | HTTP, conexión en tiempo real y sesiones |
| `game.js` | Reglas y estado de las salas |
| `render.yaml` | Configuración opcional de Render |
| `test/game.test.js` | Pruebas automáticas de las reglas |

## Si algo no conecta

- Comprueba que `config.js` contiene el dominio correcto con `https://`.
- Comprueba `/health` y el estado del servicio en Render.
- Revisa `ALLOWED_ORIGINS`: usa `https://usuario.github.io`, sin el nombre del repositorio.
- Si acabas de editar GitHub Pages, espera al despliegue y recarga la página.
- Si el código no existe, revisa las mayúsculas o crea otra sala; puede haber caducado o el servidor puede haberse reiniciado.
- Si una pestaña queda en segundo plano o el móvil bloquea la pantalla, el navegador puede suspender la conexión. Mantén el juego visible durante la partida.

## Futura aplicación Flutter

Esta entrega es la versión web. El diseño no bloquea la orientación y usa HTTPS y rutas relativas, para facilitar una futura envoltura WebView. La app Flutter, los permisos específicos de Android/iOS, la persistencia al pasar a segundo plano y la publicación en las tiendas quedan para después de validar el juego, como pediste.

## Documentación de publicación consultada

- Render, servicios Node: https://render.com/docs/deploy-node-express-app
- Render, servicios web y puerto: https://render.com/docs/web-services
- Render, comportamiento del plan gratuito: https://render.com/docs/free
- GitHub Pages, rama y carpeta de publicación: https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site

## Validación de esta entrega

Se han superado 16 pruebas automáticas de reglas y de integración HTTP/SSE con dos clientes. La sintaxis JavaScript también está comprobada. No se pudo completar la inspección visual automatizada: el entorno no disponía de navegador y falló su descarga. El diseño incluye ajustes para móvil vertical y horizontal, pero conviene probar esas dos orientaciones en tus dispositivos al publicarlo. No se ha publicado en tus cuentas de GitHub o Render.
