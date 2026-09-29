import 'dart:convert';
import 'dart:io';

void main() {
  final c = jsonDecode(File('config/app.json').readAsStringSync()) as Map;
  final errors = <String>[];
  for (final k in ['server_url', 'web_url', 'privacy_url']) {
    final uri = Uri.tryParse(c[k]?.toString() ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      errors.add('$k debe ser una URL HTTPS real.');
    }
  }
  if (!(c['support_email']?.toString().contains('@') ?? false)) {
    errors.add('Falta support_email.');
  }
  if (c['ads_mode'] != 'live') {
    errors.add(
      'ads_mode sigue en test. Cambia a live solo después de validar con anuncios de prueba.',
    );
  }
  for (final k in [
    'android_admob_app_id',
    'ios_admob_app_id',
    'android_interstitial_id',
    'ios_interstitial_id',
  ]) {
    final v = c[k]?.toString() ?? '';
    final pattern = k.contains('interstitial')
        ? r'^ca-app-pub-\d+/\d+$'
        : r'^ca-app-pub-\d+~\d+$';
    if (!RegExp(pattern).hasMatch(v) || v.contains('3940256099942544')) {
      errors.add('$k necesita tu identificador real.');
    }
  }
  if (!File('pubspec.lock').existsSync()) {
    errors.add(
      'Falta pubspec.lock: ejecuta la preparación y conserva las versiones resueltas.',
    );
  }
  if (!Directory('android').existsSync() || !Directory('ios').existsSync()) {
    errors.add('Ejecuta dart tool/setup.dart.');
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
  } else {
    stdout.writeln(
      'Configuración básica completa. Aún debes probar en dispositivos, firmar y completar las fichas y declaraciones de las tiendas.',
    );
  }
}
