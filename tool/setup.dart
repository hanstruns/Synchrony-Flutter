// Ejecutar: dart tool/setup.dart
// Genera proyectos nativos oficiales con el Flutter instalado, sin sustituir lib/.
import 'dart:convert';
import 'dart:io';

Future<void> command(
  String executable,
  List<String> args, {
  String? directory,
}) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: directory,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(
      executable,
      args,
      'El comando no terminó correctamente.',
      code,
    );
  }
}

void copyTree(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entry in from.listSync(followLinks: false)) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is Directory) copyTree(entry, Directory('${to.path}/$name'));
    if (entry is File) entry.copySync('${to.path}/$name');
  }
}

String xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
void main(List<String> args) async {
  try {
    final root = Directory.current;
    if (!File('pubspec.yaml').existsSync() ||
        !File('config/app.json').existsSync()) {
      throw StateError('Ejecuta este comando dentro de synchrony-flutter.');
    }
    final config =
        jsonDecode(File('config/app.json').readAsStringSync())
            as Map<String, dynamic>;
    final id = config['application_id'] as String;
    if (!RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*){2,}$').hasMatch(id)) {
      throw StateError('application_id no es válido.');
    }
    final test = config['ads_mode'] == 'test';
    if (!test && config['ads_mode'] != 'live') {
      throw StateError('ads_mode debe ser test o live.');
    }
    for (final key in ['android_admob_app_id', 'ios_admob_app_id']) {
      if (!RegExp(r'^ca-app-pub-\d+~\d+$').hasMatch(config[key] as String)) {
        throw StateError('$key no es válido.');
      }
    }
    if (!Directory('android').existsSync() || !Directory('ios').existsSync()) {
      final temp = Directory.systemTemp.createTempSync('synchrony_scaffold_');
      try {
        final target = '${temp.path}/synchrony';
        await command('flutter', [
          'create',
          '--no-pub',
          '--platforms=android,ios',
          '--org',
          'com.synchrony',
          '--project-name',
          'synchrony',
          target,
        ]);
        for (final name in ['android', 'ios']) {
          if (!Directory(name).existsSync()) {
            copyTree(Directory('$target/$name'), Directory(name));
          }
        }
        if (!File('.metadata').existsSync()) {
          File('$target/.metadata').copySync('.metadata');
        }
      } finally {
        temp.deleteSync(recursive: true);
      }
    }
    String literal(Object? value) => jsonEncode(value).replaceAll(r'$', r'\$');
    File('lib/config.dart').writeAsStringSync('''
// Generado por tool/setup.dart desde config/app.json.
abstract final class AppConfig {
  static const serverUrl = ${literal(config['server_url'])};
  static const webUrl = ${literal(config['web_url'])};
  static const privacyUrl = ${literal(config['privacy_url'])};
  static const supportEmail = ${literal(config['support_email'])};
  static const testAds = $test;
  static const androidInterstitial = ${literal(config['android_interstitial_id'])};
  static const iosInterstitial = ${literal(config['ios_interstitial_id'])};
}
''');
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    var android = manifest.readAsStringSync();
    if (!android.contains('android.permission.INTERNET')) {
      android = android.replaceFirst(
        '<application',
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
      );
    }
    android = android.replaceAll(
      RegExp(r'android:label="[^"]*"'),
      'android:label="Synchrony"',
    );
    if (!android.contains('android:allowBackup=')) {
      android = android.replaceFirst(
        '<application',
        '<application android:allowBackup="false"',
      );
    }
    android = android.replaceAll(
      RegExp(
        r'<meta-data\s+android:name="com.google.android.gms.ads.APPLICATION_ID"[\s\S]*?/>',
      ),
      '',
    );
    final androidId = test
        ? 'ca-app-pub-3940256099942544~3347511713'
        : config['android_admob_app_id'] as String;
    android = android.replaceFirst(
      '</application>',
      '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="${xml(androidId)}"/>\n    </application>',
    );
    manifest.writeAsStringSync(android);
    Directory('android/app/src/debug').createSync(recursive: true);
    File('android/app/src/debug/AndroidManifest.xml').writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
  <application android:usesCleartextTraffic="true"/>
</manifest>
''');
    final gradle = File('android/app/build.gradle.kts');
    if (!gradle.existsSync()) {
      throw StateError(
        'Se requiere una plantilla reciente de Flutter con build.gradle.kts.',
      );
    }
    var build = gradle
        .readAsStringSync()
        .replaceAll(RegExp(r'namespace\s*=\s*"[^"]+"'), 'namespace = "$id"')
        .replaceAll(
          RegExp(r'applicationId\s*=\s*"[^"]+"'),
          'applicationId = "$id"',
        )
        .replaceAll(RegExp(r'minSdk\s*=\s*[^\n]+'), 'minSdk = 24');
    if (!build.contains('// Synchrony signing')) {
      build = build.replaceFirst('android {', '''
// Synchrony signing: nunca se publica una versión firmada con la clave de depuración.
val synchronyKeys = java.util.Properties()
val synchronyKeyFile = rootProject.file("key.properties")
if (synchronyKeyFile.exists()) {
    synchronyKeyFile.inputStream().use { synchronyKeys.load(it) }
}
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } && !synchronyKeyFile.exists()) {
    throw GradleException("Falta android/key.properties. Consulta PUBLICAR.md para firmar la versión de tienda.")
}
android {
    signingConfigs {
        if (synchronyKeyFile.exists()) {
            create("release") {
                keyAlias = synchronyKeys["keyAlias"] as String
                keyPassword = synchronyKeys["keyPassword"] as String
                storeFile = file(synchronyKeys["storeFile"] as String)
                storePassword = synchronyKeys["storePassword"] as String
            }
        }
    }
''');
      build = build.replaceAll(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.findByName("release")',
      );
    }
    build = build.replaceAll(
      'val synchronyKeys = java.util.Properties()',
      'val synchronyKeys = Properties()',
    );
    if (!build.contains('import java.util.Properties')) {
      build = 'import java.util.Properties\n\n$build';
    }
    build = build.replaceAll(
      '// TODO: Add your own signing config for the release build.',
      '// La firma release se carga desde android/key.properties.',
    );
    build = build.replaceAll(
      '// Signing with the debug keys for now, so `flutter run --release` works.',
      '// Las claves de prueba nunca se usan para la versión de tienda.',
    );
    gradle.writeAsStringSync(build);
    for (final f in Directory(
      'android/app/src/main',
    ).listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('MainActivity.kt')) {
        f.writeAsStringSync(
          f.readAsStringSync().replaceFirst(
            RegExp(r'package [^\n]+'),
            'package $id',
          ),
        );
      }
    }
    final plist = File('ios/Runner/Info.plist');
    var ios = plist.readAsStringSync();
    void stringKey(String key, String value) {
      final pattern = RegExp('<key>$key</key>\\s*<string>[\\s\\S]*?</string>');
      final entry = '<key>$key</key>\n\t<string>${xml(value)}</string>';
      if (pattern.hasMatch(ios)) {
        ios = ios.replaceAll(pattern, entry);
      } else {
        final at = ios.lastIndexOf('</dict>');
        ios = ios.replaceRange(at, at, '$entry\n');
      }
    }

    stringKey('CFBundleDisplayName', 'Synchrony');
    stringKey('CFBundleName', 'Synchrony');
    stringKey(
      'GADApplicationIdentifier',
      test
          ? 'ca-app-pub-3940256099942544~1458002511'
          : config['ios_admob_app_id'] as String,
    );
    // Solo se solicitan anuncios no personalizados y no se pide ATT en esta versión.
    if (!ios.contains('<key>SKAdNetworkItems</key>')) {
      final at = ios.lastIndexOf('</dict>');
      ios = ios.replaceRange(
        at,
        at,
        '<key>SKAdNetworkItems</key><array><dict><key>SKAdNetworkIdentifier</key><string>cstr6suwn9.skadnetwork</string></dict></array>\n',
      );
    }
    plist.writeAsStringSync(ios);
    File('ios/Runner/Runner.entitlements').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>keychain-access-groups</key><array/></dict></plist>
''');
    final project = File('ios/Runner.xcodeproj/project.pbxproj');
    var pbx = project.readAsStringSync().replaceAllMapped(
      RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'),
      (m) =>
          'PRODUCT_BUNDLE_IDENTIFIER = $id${m[1]!.contains('RunnerTests') ? '.RunnerTests' : ''};',
    );
    pbx = pbx.replaceAll(
      RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = [^;]+;'),
      'IPHONEOS_DEPLOYMENT_TARGET = 15.5;',
    );
    if (!pbx.contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;')) {
      pbx = pbx.replaceAll(
        'INFOPLIST_FILE = Runner/Info.plist;',
        'INFOPLIST_FILE = Runner/Info.plist;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
      );
    }
    project.writeAsStringSync(pbx);
    final podfile = File('ios/Podfile');
    if (podfile.existsSync()) {
      podfile.writeAsStringSync(
        podfile.readAsStringSync().replaceAll(
          RegExp(r"#?\s*platform :ios, '[^']+'"),
          "platform :ios, '15.5'",
        ),
      );
    }
    copyTree(
      Directory('tool/icons/android'),
      Directory('android/app/src/main/res'),
    );
    copyTree(
      Directory('tool/icons/ios'),
      Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset'),
    );
    await command('flutter', ['pub', 'get'], directory: root.path);
    await command('dart', [
      'format',
      'lib',
      'test',
      'tool/setup.dart',
      'tool/check_release.dart',
    ], directory: root.path);
    stdout.writeln(
      '\nPreparado. Ahora ejecuta flutter analyze, flutter test y flutter run.',
    );
  } catch (e) {
    stderr.writeln('\nNo se pudo completar la preparación: $e');
    exitCode = 1;
  }
}
