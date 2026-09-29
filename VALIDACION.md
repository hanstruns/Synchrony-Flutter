# Validación de la entrega

Entorno: Flutter 3.47.5, Dart 3.13.4, Linux.

- `flutter analyze`: sin incidencias.
- `dart tool/setup.dart`: preparación completada correctamente.
- `SYNCHRONY_INTEGRATION=1 flutter test --no-pub`: 15 pruebas superadas.
- `npm --prefix server test`: 16 pruebas superadas.
- Se renderizaron inicio y mesa a 390×844, 844×390 y 320×640 sin excepciones de desbordamiento. Las pantallas usan desplazamiento cuando el contenido supera la altura disponible.
- La prueba de integración inicia Node, conecta dos clientes Dart, confirma preparación, recibe cartas privadas, reconecta un cliente, juega en orden y comprueba la victoria.
- Las pruebas de publicidad verifican cuándo se permite un anuncio y que no se repita. No muestran anuncios reales ni prueban los SDK nativos en un dispositivo.

Pendiente antes de publicar: compilación APK/AAB e IPA con los toolchains nativos, pruebas en Android/iPhone, firma, configuración real del servidor/AdMob/privacidad y revisión de las tiendas. El workflow incluido genera una APK de depuración; no se ha ejecutado remotamente en esta entrega.
