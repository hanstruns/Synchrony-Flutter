import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/game_state.dart';

class GameConnection extends ChangeNotifier {
  final FlutterSecureStorage storage;
  GameConnection({this.storage = const FlutterSecureStorage()});
  GameState? state;
  String server = '', _token = '', _code = '';
  String? message;
  bool connected = false, busy = false, restoring = false, _closed = false;
  int _epoch = 0, _offset = 0;
  HttpClient? _streamClient;
  Timer? _ping;
  bool _pingBusy = false;
  bool get hasSession => _token.isNotEmpty;
  int get serverNow => DateTime.now().millisecondsSinceEpoch + _offset;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void clearMessage() {
    message = null;
  }

  static String validateServer(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null ||
        u.host.isEmpty ||
        u.userInfo.isNotEmpty ||
        u.hasQuery ||
        u.hasFragment ||
        (u.path.isNotEmpty && u.path != '/')) {
      throw const FormatException('Introduce solo el dominio HTTPS de Render.');
    }
    final local =
        u.host == 'localhost' ||
        u.host == '127.0.0.1' ||
        u.host == '10.0.2.2' ||
        u.host.startsWith('192.168.') ||
        u.host.startsWith('10.');
    if (u.scheme != 'https' && !(kDebugMode && local && u.scheme == 'http')) {
      throw const FormatException('La conexión debe usar HTTPS.');
    }
    return '${u.scheme}://${u.authority}';
  }

  Future<void> restore() async {
    restoring = true;
    _notify();
    try {
      final raw = await storage.read(key: 'session');
      if (raw != null) {
        final j = jsonDecode(raw) as Map;
        server = validateServer(j['server'] as String);
        _token = j['token'] as String;
        _code = j['code'] as String;
        _start();
      }
    } catch (_) {
      _token = '';
      _code = '';
      message = 'No se pudo recuperar la sesión. Puedes entrar de nuevo.';
    } finally {
      restoring = false;
      _notify();
    }
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> data, {
    bool auth = true,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        final req = await client.postUrl(Uri.parse('$server/api'));
        req.headers.contentType = ContentType.json;
        if (auth) {
          req.headers.set('Authorization', 'Bearer $_token');
          req.headers.set('X-Room-Code', _code);
        }
        req.write(jsonEncode(data));
        final response = await req.close();
        final raw = await response.transform(utf8.decoder).join();
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (response.statusCode != 200) {
          throw GameError(
            j['error']?.toString() ?? 'No se pudo completar la acción.',
          );
        }
        return j;
      })().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> enter(
    String url,
    String name,
    String action, {
    int players = 2,
    int deck = 100,
    String code = '',
  }) async {
    if (busy || hasSession) return;
    busy = true;
    message = null;
    _notify();
    try {
      server = validateServer(url);
      if (name.trim().isEmpty || name.trim().length > 24) {
        throw const GameError('Escribe un nombre de 1 a 24 caracteres.');
      }
      final j = await _request(
        {
          'action': action,
          'name': name.trim(),
          'players': players,
          'deck': deck,
          'code': code.trim(),
        },
        auth: false,
        timeout: const Duration(seconds: 90),
      );
      if (_closed) return;
      _token = j['token'] as String;
      _code = j['code'] as String;
      try {
        await storage.write(
          key: 'session',
          value: jsonEncode({'token': _token, 'code': _code, 'server': server}),
        );
      } catch (_) {
        message =
            'La partida funciona, pero no se podrá recuperar al cerrar la aplicación.';
      }
      _apply(j['state'] as Map<String, dynamic>);
      _start();
    } catch (e) {
      message = _friendly(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  String _friendly(Object e) {
    if (e is GameError) return e.message;
    if (e is FormatException) return e.message;
    if (e is TimeoutException) {
      return 'El servidor tarda en responder. Puede estar despertando; inténtalo de nuevo.';
    }
    return 'No se pudo conectar. Comprueba tu conexión y la dirección de Render.';
  }

  void _apply(Map<String, dynamic> j) {
    final next = GameState.fromJson(j);
    if (state != null && next.revision < state!.revision) return;
    _offset = next.serverNow - DateTime.now().millisecondsSinceEpoch;
    state = next;
    _notify();
  }

  void _start() {
    final epoch = ++_epoch;
    _streamClient?.close(force: true);
    _ping?.cancel();
    connected = false;
    _ping = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _heartbeat(epoch),
    );
    unawaited(_listen(epoch));
  }

  Future<void> _heartbeat(int epoch) async {
    if (_pingBusy || !hasSession || !connected) return;
    _pingBusy = true;
    try {
      final j = await _request({'action': 'ping'});
      if (epoch == _epoch && !_closed) {
        _apply(j['state'] as Map<String, dynamic>);
      }
    } catch (_) {
      if (epoch == _epoch && !_closed) {
        connected = false;
        _notify();
        _streamClient?.close(force: true);
      }
    } finally {
      _pingBusy = false;
    }
  }

  Future<void> _listen(int epoch) async {
    while (hasSession && epoch == _epoch && !_closed) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);
      _streamClient = client;
      try {
        final request = await client.getUrl(Uri.parse('$server/events'));
        request.headers.set('Authorization', 'Bearer $_token');
        request.headers.set('X-Room-Code', _code);
        final response = await request.close().timeout(
          const Duration(seconds: 90),
        );
        if (epoch != _epoch || _closed) break;
        if (response.statusCode == 401) {
          await _forget();
          message = 'La sala ya no está disponible. Crea otra partida.';
          _notify();
          return;
        }
        if (response.statusCode != 200) {
          throw const GameError('Conexión interrumpida.');
        }
        String event = '', data = '';
        await for (final line
            in response
                .timeout(const Duration(seconds: 25))
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (epoch != _epoch || _closed) break;
          if (line.isEmpty) {
            if (event == 'expired') {
              await _forget();
              message = 'La sala ha caducado.';
              _notify();
              return;
            }
            if (data.isNotEmpty) {
              connected = true;
              _apply(jsonDecode(data) as Map<String, dynamic>);
            }
            event = '';
            data = '';
          } else if (line.startsWith('event:')) {
            event = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            data += line.substring(5).trimLeft();
          }
        }
      } catch (_) {
        /* El bucle reanuda la sesión sin repetir acciones. */
      } finally {
        client.close(force: true);
      }
      if (epoch != _epoch || _closed) return;
      connected = false;
      _notify();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> action(String action, {int? card}) async {
    if (busy || !connected || state == null) return;
    busy = true;
    final epoch = _epoch;
    _notify();
    try {
      final j = await _request({
        'action': action,
        'card': ?card,
        'revision': state!.revision,
      });
      if (epoch == _epoch && !_closed) {
        _apply(j['state'] as Map<String, dynamic>);
      }
    } catch (e) {
      if (epoch == _epoch) message = _friendly(e);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> leave() async {
    // Cancelar el stream antes de olvidar el token evita resucitar una sesión.
    ++_epoch;
    _ping?.cancel();
    _streamClient?.close(force: true);
    connected = false;
    busy = true;
    _notify();
    try {
      if (hasSession) {
        await _request({
          'action': 'leave',
        }, timeout: const Duration(seconds: 3));
      }
    } catch (_) {
      /* El servidor aplicará el margen de desconexión. */
    }
    await _forget();
    busy = false;
    _notify();
  }

  Future<void> _forget() async {
    ++_epoch;
    _ping?.cancel();
    _streamClient?.close(force: true);
    _token = '';
    _code = '';
    state = null;
    connected = false;
    try {
      await storage.delete(key: 'session');
    } catch (_) {
      /* Sesión caducará en el servidor. */
    }
  }

  void suspend() {
    ++_epoch;
    _ping?.cancel();
    _streamClient?.close(force: true);
    connected = false;
    _notify();
  }

  void resume() {
    if (hasSession && !_closed) _start();
  }

  @override
  void dispose() {
    _closed = true;
    ++_epoch;
    _ping?.cancel();
    _streamClient?.close(force: true);
    super.dispose();
  }
}

class GameError implements Exception {
  final String message;
  const GameError(this.message);
}
