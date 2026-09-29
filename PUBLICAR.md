# Publicar Synchrony en Google Play y App Store

La entrega contiene el código fuente y preparación de los proyectos nativos. Antes de enviar a las tiendas hay que compilar, probar en dispositivos, completar tu configuración y firmar con tus cuentas. La aprobación de las tiendas no está garantizada.

## 1. Datos que debes configurar

En `config/app.json`:

| Campo | Contenido |
|---|---|
| `application_id` | Identificador definitivo, único, p. ej. `com.tunombre.synchrony`. No lo cambies después de publicar. |
| `server_url` | Dominio HTTPS del servidor Render |
| `web_url` | Web pública para invitaciones |
| `privacy_url` | Política de privacidad real y pública |
| `support_email` | Tu correo de soporte |
| `ads_mode` | `test` para pruebas; `live` cuando esté configurado AdMob |
| `android_admob_app_id` / `ios_admob_app_id` | IDs de las aplicaciones en AdMob, con `~` |
| `android_interstitial_id` / `ios_interstitial_id` | IDs de los bloques intersticiales, con `/` |

Después de editar:

```bash
dart tool/setup.dart
flutter analyze --no-fatal-infos
flutter test
```

## 2. AdMob y privacidad

1. Crea tu cuenta en https://admob.google.com/ y completa las verificaciones y los datos de pago que solicite tu cuenta.
2. Registra Synchrony para Android y para iOS; son dos registros publicitarios distintos.
3. Crea un bloque **intersticial** para cada plataforma. Copia tanto el ID de aplicación como el del bloque al archivo de configuración, respetando `~` frente a `/`.
4. En **Privacidad y mensajes**, configura el mensaje de consentimiento para las regiones en las que distribuirás el juego. El código integra UMP, consulta `canRequestAds()` y ofrece opciones de privacidad cuando el SDK lo exige.
5. Publica tu archivo `app-ads.txt`, con la línea exacta de AdMob, en la raíz del dominio de tu sitio de desarrollador. Ejemplo: `https://TU-USUARIO.github.io/app-ads.txt`, **no** dentro de `/synchrony/`. Puedes usar el repositorio de sitio personal `TU-USUARIO.github.io` o un dominio propio. Enlaza ese sitio desde la ficha de la tienda y solicita la verificación de AdMob.
6. Vincula las fichas publicadas y espera la revisión de disponibilidad de anuncios de AdMob.
7. Cambia a `ads_mode: live` solo cuando hayas probado la integración con unidades de prueba y tu cuenta real esté configurada. No pulses anuncios reales para probar ingresos.

La versión entregada pide publicidad no personalizada y no implementa seguimiento entre aplicaciones ni solicita ATT. **No personalizada no significa sin tratamiento de datos:** debes declarar la información que realmente recoge el SDK, la conexión al servidor y las opciones de consentimiento. Si agregas seguimiento, IDFA, analítica o mediación, configura ATT cuando corresponda y actualiza las declaraciones. El consentimiento y la negativa nunca deben impedir jugar.

En iOS se incluye el identificador SKAdNetwork de Google. Antes de activar nuevas redes o fuentes publicitarias, actualiza la lista de SKAdNetworkItems conforme a la guía vigente de AdMob y a los adaptadores instalados. No se incluyen redes de mediación en esta entrega.

No establezcas un temporizador que bloquee el cierre de los anuncios. El SDK decide los tiempos y no permite prometer un mínimo de 15 segundos y máximo de 60 para cada impresión. Puedes limitar la frecuencia en AdMob si detectas partidas excesivamente cortas.

La política de privacidad que publiques debe identificarte, facilitar contacto, explicar apodos, identificadores temporales, datos técnicos y publicidad, finalidades, proveedores, plazos, opciones del usuario y regiones relevantes. No se entrega una política con identidades inventadas. Completa Seguridad de datos de Google Play y Privacidad de la app de Apple según la implementación efectiva.

## 3. Android: firma y archivo para Google Play

La cuenta de Google Play Console cuesta 25 USD en un pago único, sujeto a las condiciones de alta y verificación vigentes. En cuentas personales nuevas se exige la prueba cerrada de al menos 12 participantes inscritos continuamente durante 14 días antes de solicitar acceso a producción.

### Crear la clave

Después de generar `android/`, crea una clave de subida. Guarda una copia segura del archivo y sus contraseñas:

```bash
keytool -genkeypair -v -keystore synchrony-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

No incluyas la clave ni las contraseñas en un repositorio. Crea `android/key.properties`:

```properties
storePassword=TU_CONTRASENA
keyPassword=TU_CONTRASENA
keyAlias=upload
storeFile=/RUTA/ABSOLUTA/synchrony-upload.jks
```

En Windows puedes usar barras normales, por ejemplo `C:/claves/synchrony-upload.jks`.

La preparación configura Gradle para utilizar esta firma. Si falta `key.properties`, una compilación release falla expresamente para evitar que publiques una app firmada con la clave de depuración.

### Compilar

```bash
dart tool/check_release.dart
flutter build appbundle --release
```

Resultado: `build/app/outputs/bundle/release/app-release.aab`.

### Play Console

1. Crea la aplicación, el idioma principal, el nombre y la categoría de juego.
2. Añade icono, capturas reales, descripción, correo de soporte y política de privacidad.
3. Declara que incluye anuncios y completa público objetivo, clasificación por edades, acceso a la app y Seguridad de datos. Si decides dirigirla a niños, revisa y adapta específicamente los requisitos de Families y publicidad antes de distribuirla; no marques esa opción como un trámite sin adaptar la implementación.
4. Configura Play App Signing y sube el AAB a pruebas internas/cerradas.
5. Reúne las pruebas exigidas para tu tipo de cuenta, corrige los problemas detectados y solicita acceso a producción.
6. Envía a revisión y publica cuando esté aprobada. Usa la versión objetivo de Android exigida por Play Console en ese momento, con Flutter/SDK actualizados.

## 4. iOS: Xcode, TestFlight y App Store

Apple Developer Program cuesta 99 USD al año o el importe local mostrado durante el alta. Necesitas un equipo macOS con Xcode actualizado o un servicio de compilación macOS con tu firma configurada.

1. Ejecuta la preparación en un Mac con Flutter, Xcode y los componentes que indique `flutter doctor`.
2. Abre `ios/Runner.xcworkspace`. En Signing & Capabilities, selecciona tu equipo de Apple y comprueba el identificador definitivo. Revisa que Keychain funcione y que el archivo `Runner/Runner.entitlements` esté asociado a Debug, Profile y Release.
3. Registra el mismo Bundle ID en Apple Developer y crea la aplicación en App Store Connect.
4. Prueba en un iPhone real antes del envío: conexión, orientación, sonido, segundo plano, publicidad, privacidad y recuperación de sesión.
5. Genera el archivo firmado:

```bash
dart tool/check_release.dart
flutter build ipa --release
```

6. Sube el IPA desde Transporter o utiliza el archivo generado con Xcode Organizer. Prueba primero en TestFlight; las pruebas externas pueden requerir revisión beta.
7. Completa nombre, descripción, icono, capturas reales, categoría, edad, política de privacidad, declaraciones de datos y contacto de revisión. La configuración actual apunta a Android 7+ e iOS 15.5+; valida los mínimos efectivos de los SDK resueltos.
8. Explica al revisor cómo probarlo: puede crear una sala privada de un jugador con una baraja pequeña para recorrer todas las reglas, y también puede entrar con otro dispositivo o desde la web. No requiere crear una cuenta.
9. Mantén el servidor disponible durante la revisión. Envía la versión a App Review y publica tras su aprobación.

Las declaraciones de vendedor/comerciante y los datos de contacto que pidan las tiendas para tu región deben completarse con tus datos reales.

## 5. Actualizaciones

Incrementa `version` en `pubspec.yaml`, por ejemplo `1.0.1+2`, y vuelve a compilar. Conserva el identificador de aplicación y la firma. Las actualizaciones de la app se distribuyen desde las tiendas; el servidor puede actualizarse por separado manteniendo el contrato API.

## Documentación oficial consultada

- Flutter Android: https://docs.flutter.dev/deployment/android
- Flutter iOS: https://docs.flutter.dev/deployment/ios
- Plugin AdMob: https://developers.google.com/admob/flutter/quick-start
- Intersticiales: https://developers.google.com/admob/flutter/interstitial
- Consentimiento UMP: https://developers.google.com/admob/flutter/privacy
- Privacidad iOS: https://developers.google.com/admob/ios/privacy/strategies
- app-ads.txt: https://support.google.com/admob/answer/14538460
- Pruebas de Google Play: https://support.google.com/googleplay/android-developer/answer/14151465
- Cuenta de Google Play: https://support.google.com/googleplay/android-developer/answer/6112435
- Apple Developer: https://developer.apple.com/programs/enroll/
- Revisión Apple: https://developer.apple.com/app-store/review/guidelines/
