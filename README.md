# Synchrony · Aplicación Flutter

Interfaz propia en Flutter/Dart para Android e iOS. No utiliza una WebView para el juego. La web y la aplicación pueden compartir el servidor Node.js y jugar en las mismas salas.

## Estado de esta entrega

- Implementados: inicio, creación y búsqueda de salas, entrada mediante código o enlace pegado, confirmación de jugadores, cuenta atrás, cartas de colores, vidas, reloj, resultados, copia de invitaciones, sonidos del sistema opcionales, vibración, animaciones y adaptación vertical/horizontal.
- Conexión HTTP/SSE compatible con el servidor anterior, manos privadas, credencial guardada en almacenamiento seguro, reconexión y gestión de segundo plano.
- Integración AdMob con **identificadores de prueba**, una sola oportunidad de anuncio al pulsar Continuar tras victoria o derrota completa. Nunca por perder una vida, superar una ronda, desconectarse o abandonar. Si no hay anuncio cargado, continúa sin bloquear.
- Consentimiento UMP y acceso a opciones de privacidad para anuncios reales. Esta primera versión solicita publicidad no personalizada y no solicita permiso ATT ni implementa seguimiento entre aplicaciones. Si después incorporas seguimiento o mediación, debes revisar esa configuración y las declaraciones de privacidad.
- Incluye pruebas Dart y un proceso manual de GitHub Actions para generar una APK de prueba.
- **Validado con Flutter 3.47.5 / Dart 3.13.4:** análisis sin incidencias y 15 pruebas Flutter superadas (pantallas verticales/horizontales, cartas, anuncios y una partida con dos clientes Dart conectados al servidor Node real, incluida reconexión). Las 16 pruebas del servidor también pasan. Se incluyen Android e iOS generados con la plantilla oficial, configuración y archivo de dependencias `pubspec.lock`.
- No se entrega una APK/IPA compilada ni una publicación en las tiendas. Faltan compilar con el SDK de Android/Xcode, probar los plugins en móviles reales y completar tus URLs, cuentas, firma e identificadores publicitarios.

## La primera configuración

Edita `config/app.json`:

```json
"server_url": "https://TU-SERVIDOR.onrender.com",
"web_url": "https://TU-USUARIO.github.io/synchrony/"
```

La URL de Render es la misma que usa tu web. No pongas `/api` ni `/events`. La dirección web sirve para copiar enlaces que abren la sala en el navegador; esta entrega no registra Universal Links/App Links. En la app se puede pegar ese mismo enlace en Unirme.

Si dejas `server_url` vacío, la versión de prueba permite introducirlo desde Ajustes. Antes de publicar, configúralo en el archivo para que los jugadores no tengan que hacerlo.

Si ya tienes el servidor anterior en Render, no necesitas volver a desplegarlo. `server/` contiene una copia completa por comodidad. Si publicas esta copia desde este repositorio, usa **Root Directory: server**, Build `npm ci` y Start `node server.js`.

## Opción A: conseguir una APK con GitHub

1. Crea un repositorio nuevo para la aplicación.
2. Sube **el contenido** de `synchrony-flutter`, incluido `.github/workflows/android-prueba.yml`, directamente a la raíz. No subas la carpeta contenedora ni el ZIP.
3. Edita `config/app.json` con tu servidor. Mantén `ads_mode` en `test`.
4. Abre **Actions → Generar APK de prueba → Run workflow**.
5. El proceso instala Flutter, configura Android/iOS, ejecuta análisis y pruebas, y compila Android. Si alguna comprobación falla, el proceso se detiene: revisa su registro.
6. Si finaliza correctamente, descarga el artefacto **Synchrony-APK-prueba**, descomprímelo e instala `app-debug.apk` en tu Android, autorizando la instalación desde esa fuente cuando Android lo solicite.

Esta APK se firma como depuración y usa anuncios de prueba; no es el archivo para subir a Google Play. GitHub Actions puede consumir la cuota de tu cuenta. El flujo no se ha ejecutado desde esta entrega.

## Opción B: preparar el proyecto en tu ordenador

Instala Flutter estable, Android Studio y el SDK de Android. Usa `flutter doctor` para completar los requisitos. Para compilar iPhone necesitas macOS y Xcode; en Windows puedes desarrollar y probar Android.

Desde la carpeta del proyecto:

```bash
dart tool/setup.dart
flutter analyze --no-fatal-infos
flutter test
flutter run
```

En Windows también puedes ejecutar `PREPARAR.bat`; en macOS/Linux, `bash preparar.sh`. Ambos preparan, analizan y ejecutan las pruebas.

Las carpetas Android e iOS ya están incluidas. `tool/setup.dart` aplica la configuración, iconos, permisos, almacenamiento seguro, IDs de AdMob y firma Android; si faltan las carpetas nativas, las crea mediante `flutter create`. No sobrescribe las pantallas Dart.

**Ejecuta otra vez `dart tool/setup.dart` después de cambiar `config/app.json`.** No edites a mano `lib/config.dart`: se genera desde ese archivo.

Dependencias directas principales fijadas: `google_mobile_ads 9.1.0`, `shared_preferences 2.5.5`, `flutter_secure_storage 11.2.0`. Usa Flutter 3.47.5, la versión validada y fijada en GitHub Actions. Conserva `pubspec.lock` en tu repositorio; algunas dependencias transitivas requieren un Flutter superior al mínimo declarado por la aplicación.

Para generar una APK local:

```bash
flutter build apk --debug
```

Resultado: `build/app/outputs/flutter-apk/app-debug.apk`.

## Anuncios: comportamiento exacto

1. El servidor anuncia una victoria o derrota definitiva.
2. La app muestra el resultado sin interrumpirlo con un anuncio automático.
3. Al pulsar **Continuar** (o salir desde ese resultado), cierra la sesión y muestra el anuncio precargado si existe.
4. El SDK gestiona los controles y el cierre. Después se vuelve al inicio.
5. Se recuerda la oportunidad por sala e identidad de jugador para no repetirla tras reconexiones. Si el anuncio falla o no está listo, se continúa sin esperar.

La aplicación **no fuerza un mínimo de 15 segundos ni cierra el anuncio a los 60**. La duración y la opción de cerrar dependen del anuncio/SDK. No existe un temporizador que oculte los controles del proveedor.

En modo de prueba se usan exclusivamente los identificadores oficiales de Google, tanto para la aplicación como para las unidades publicitarias. Los anuncios de prueba no generan ingresos. El flujo UMP real solo se activa con `ads_mode: live` y los identificadores de tu cuenta.

## Pruebas en móviles que faltan

- Android e iPhone en vertical y horizontal; texto ampliado.
- Una persona en navegador y otra en app dentro de la misma sala.
- Cuenta atrás, ronda correcta, fallo, victoria y derrota.
- Bloquear el móvil, cambiar de aplicación y volver antes/después de 30 segundos.
- Pérdida de red, reinicio de Render y sala caducada.
- Anuncio de prueba al finalizar, botón de cierre, fallo de carga y repetición del resultado.
- Consentimiento real UMP en un dispositivo de prueba una vez configurada tu cuenta.

No mantengas el juego en segundo plano: la plataforma puede suspenderlo y se aplicará la regla de desconexión. Los anuncios solo aparecen tras cerrar la partida, así que no perjudican a compañeros activos.

## Estructura

- `lib/main.dart`: pantallas, animaciones, controles, orientación y ciclo de vida.
- `lib/services/game_connection.dart`: API, eventos, sesiones y reconexión.
- `lib/services/ads_service.dart`: anuncios y consentimiento.
- `lib/services/ad_gate.dart`: evita publicidad duplicada o en mitad del juego.
- `lib/models/game_state.dart`: contrato de datos del servidor.
- `lib/widgets/playing_card.dart`: cartas nativas, órbitas y confeti.
- `tool/setup.dart`: configuración reproducible de Android/iOS.
- `test/`: pruebas del contrato, publicidad, cartas, pantallas y conexión real. La prueba de conexión se activa con `SYNCHRONY_INTEGRATION=1 flutter test` en macOS/Linux; GitHub Actions también la ejecuta.
- `server/`: servidor Node y web originales, compatibles con la app.
- `PUBLICAR.md`: cuentas, firma, privacidad y publicación en ambas tiendas.

Las salas del servidor siguen en memoria y desaparecen al reiniciar o redesplegar Render. Para la aplicación pública conviene usar un servidor con disponibilidad adecuada y una sola instancia hasta incorporar un almacenamiento compartido.
