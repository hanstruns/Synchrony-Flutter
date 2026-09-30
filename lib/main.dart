import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'models/game_state.dart';
import 'services/ads_service.dart';
import 'services/game_connection.dart';
import 'services/feedback_service.dart';
import 'widgets/playing_card.dart';

const lime = Color(0xffbcf582);
const ink = Color(0xff09181d);
const panel = Color(0xff10272c);
const muted = Color(0xffa5b9b7);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(SynchronyApp(prefs: prefs));
}

class SynchronyApp extends StatelessWidget {
  final SharedPreferences prefs;
  final GameConnection? connection;
  const SynchronyApp({super.key, required this.prefs, this.connection});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Synchrony: Enlaza tu Mente',
    debugShowCheckedModeBanner: false,
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lime,
        brightness: Brightness.dark,
        primary: lime,
        onPrimary: ink,
        surface: panel,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ink,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xff345056)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xff345056)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: GameApp(prefs: prefs, connection: connection),
  );
}

class GameApp extends StatefulWidget {
  final SharedPreferences prefs;
  final GameConnection? connection;
  const GameApp({super.key, required this.prefs, this.connection});
  @override
  State<GameApp> createState() => _GameAppState();
}

class _GameAppState extends State<GameApp>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final GameConnection game;
  late final AdsService ads;
  final feedback = FeedbackService();
  bool foreground = true;
  late final TextEditingController name, server, web;
  final players = TextEditingController(text: '2');
  final deck = TextEditingController(text: '100');
  final code = TextEditingController();
  final form = GlobalKey<FormState>();
  String mode = 'create';
  int onlinePlayers = 2, lastEvent = -1, lastCountdown = -1;
  bool finishing = false, sound = false, vibration = true;
  String? lastRoom;
  late final AnimationController breathing, celebration;
  Timer? ticker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    name = TextEditingController(text: widget.prefs.getString('name') ?? '');
    server = TextEditingController(
      text: AppConfig.serverUrl.isNotEmpty
          ? AppConfig.serverUrl
          : widget.prefs.getString('server') ?? '',
    );
    web = TextEditingController(
      text: AppConfig.webUrl.isNotEmpty
          ? AppConfig.webUrl
          : widget.prefs.getString('web') ?? '',
    );
    sound = widget.prefs.getBool('sound') ?? false;
    vibration = widget.prefs.getBool('vibration') ?? true;
    breathing = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    celebration = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    game = (widget.connection ?? GameConnection())..addListener(_changed);
    ads = AdsService(widget.prefs)..addListener(_adsChanged);
    ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || game.state == null) return;
      final s = game.state!;
      if (s.phase == 'countdown') {
        final n = math.max(
          1,
          ((s.countdownAt! - game.serverNow) / 1000).ceil(),
        );
        if (n != lastCountdown) {
          lastCountdown = n;
          if (foreground && !ads.showing) {
            unawaited(feedback.play('countdown', sound: sound));
          }
        }
      } else {
        lastCountdown = -1;
      }
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(game.restore());
      unawaited(ads.initialize());
    });
  }

  void _adsChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    final s = game.state;
    if (s != null) {
      if (lastRoom != s.adKey) {
        lastRoom = s.adKey;
        lastEvent = -1;
      }
      if (lastEvent != s.eventId) {
        if (lastEvent != -1) {
          if (foreground &&
              !ads.showing &&
              const [
                'card',
                'start',
                'success',
                'won',
                'mistake',
                'lost',
              ].contains(s.eventType)) {
            unawaited(
              feedback.play(
                s.eventType,
                sound: sound,
                vibration: vibration && s.eventType != 'card',
              ),
            );
          }
          if (const ['success', 'won'].contains(s.eventType) &&
              !MediaQuery.disableAnimationsOf(context)) {
            celebration.forward(from: 0);
          }
        }
        lastEvent = s.eventId;
      }
      if (s.finished) unawaited(ads.preload());
    }
    final message = game.message;
    if (message != null) {
      game.clearMessage();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notice(message);
      });
    }
    setState(() {});
  }

  Future<void> _testFeedback({required bool soundOnly}) async {
    final error = await feedback.play(
      'test',
      sound: soundOnly,
      vibration: !soundOnly,
    );
    if (mounted && error != null) _notice(error);
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) unawaited(feedback.stop());
    // Un anuncio es una transición nativa; no se inicia otra conexión debajo de él.
    if (ads.showing || finishing) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      game.suspend();
    }
    if (state == AppLifecycleState.resumed) game.resume();
  }

  Future<void> _enter() async {
    if (!form.currentState!.validate()) return;
    if (server.text.trim().isEmpty) {
      await _settings();
      return;
    }
    var room = code.text.trim();
    if (room.startsWith('https://') || room.startsWith('http://')) {
      room = Uri.tryParse(room)?.queryParameters['sala'] ?? room;
    }
    if (mode == 'join' && !RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(room)) {
      _notice('Escribe un código de 6 caracteres o pega el enlace de la sala.');
      return;
    }
    final count = mode == 'match'
        ? onlinePlayers
        : int.tryParse(players.text) ?? 0;
    final total = int.tryParse(deck.text) ?? 0;
    if (mode == 'create' &&
        (count < 1 || count > total || total < 2 || total > 100000)) {
      _notice(
        'Debe haber al menos una carta por jugador y entre 2 y 100.000 cartas.',
      );
      return;
    }
    await widget.prefs.setString('name', name.text.trim());
    await game.enter(
      server.text,
      name.text,
      mode,
      players: count,
      deck: total,
      code: room,
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _notice('Copiado. Compártelo con tu equipo.');
  }

  Future<void> _leave() async {
    if (finishing) return;
    if (game.state?.finished == true) {
      await _finish();
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Abandonar la sala?'),
        content: const Text(
          'Si estás jugando, tus cartas se retirarán. Tu equipo podrá continuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir aquí'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (yes == true) await game.leave();
  }

  Future<void> _finish() async {
    if (finishing) return;
    final result = game.state;
    if (result == null) return;
    setState(() => finishing = true);
    // Cerrar la sesión ANTES del anuncio evita cambios de sala o desconexiones durante su reproducción.
    await game.leave();
    try {
      await ads.showForResult(result);
    } finally {
      if (mounted) setState(() => finishing = false);
    }
  }

  Future<void> _openUrl(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _notice('Esta dirección aún no está configurada.');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _notice('No se pudo abrir el enlace.');
    }
  }

  Future<void> _settings() async {
    final editServer = TextEditingController(text: server.text);
    final editWeb = TextEditingController(text: web.text);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('A tu ritmo'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sonidos'),
                    value: sound,
                    onChanged: (v) {
                      setState(() => sound = v);
                      update(() {});
                      unawaited(widget.prefs.setBool('sound', v));
                      if (v) unawaited(_testFeedback(soundOnly: true));
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vibración'),
                    value: vibration,
                    onChanged: (v) {
                      setState(() => vibration = v);
                      update(() {});
                      unawaited(widget.prefs.setBool('vibration', v));
                      if (v) unawaited(_testFeedback(soundOnly: false));
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _testFeedback(soundOnly: true),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Probar sonido'),
                      ),
                      TextButton.icon(
                        onPressed: () => _testFeedback(soundOnly: false),
                        icon: const Icon(Icons.vibration),
                        label: const Text('Probar vibración'),
                      ),
                    ],
                  ),
                  const Text(
                    'Sube el volumen multimedia. En iPhone, desactiva el modo silencio. La vibración requiere un móvil compatible y estar permitida en sus ajustes.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  ListenableBuilder(
                    listenable: ads,
                    builder: (context, child) => Column(
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          'Anuncios ${AppConfig.testAds ? "de prueba" : "reales"}: ${ads.status}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        TextButton(
                          onPressed: () => ads.retry(),
                          child: const Text('Volver a cargar anuncio'),
                        ),
                      ],
                    ),
                  ),
                  if (!game.hasSession &&
                      (kDebugMode || AppConfig.serverUrl.isEmpty)) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: editServer,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Servidor de Render',
                        hintText: 'https://tu-servidor.onrender.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: editWeb,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Web para compartir salas',
                        hintText: 'https://usuario.github.io/synchrony/',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (ads.privacyRequired)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(ads.openPrivacy());
                      },
                      child: const Text('Opciones de privacidad publicitaria'),
                    ),
                  if (AppConfig.privacyUrl.isNotEmpty)
                    TextButton(
                      onPressed: () => _openUrl(AppConfig.privacyUrl),
                      child: const Text('Política de privacidad'),
                    ),
                  if (AppConfig.supportEmail.isNotEmpty)
                    TextButton(
                      onPressed: () => _copy(AppConfig.supportEmail),
                      child: const Text('Copiar correo de soporte'),
                    ),
                  Text(
                    AppConfig.testAds
                        ? 'Versión de prueba · publicidad de prueba'
                        : 'Synchrony · 1.0.1',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                if (!game.hasSession &&
                    (kDebugMode || AppConfig.serverUrl.isEmpty)) {
                  try {
                    if (editServer.text.trim().isNotEmpty) {
                      server.text = GameConnection.validateServer(
                        editServer.text,
                      );
                    }
                    if (editWeb.text.trim().isNotEmpty) {
                      final u = Uri.tryParse(editWeb.text.trim());
                      if (u == null || u.scheme != 'https' || u.host.isEmpty) {
                        throw const FormatException('La web debe usar HTTPS.');
                      }
                    }
                    web.text = editWeb.text.trim();
                    await widget.prefs.setString('server', server.text);
                    await widget.prefs.setString('web', web.text);
                  } on FormatException catch (e) {
                    if (mounted) _notice(e.message);
                    return;
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    // El diálogo conserva los controladores durante su animación de salida.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    editServer.dispose();
    editWeb.dispose();
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enlaza tu mente.'),
      content: const SingleChildScrollView(
        child: Text(
          '1. Recibirás 1 carta en la primera ronda, 2 en la segunda y así sucesivamente.\n\n'
          '2. Jugad de menor a mayor, sin turnos ni decir vuestros números. Pulsa una carta cuando sientas que es su momento.\n\n'
          '3. Si queda una carta menor, perdéis una vida y repetís la ronda con un nuevo reparto. Tenéis 5 vidas.\n\n'
          '4. Todos pulsáis Estoy listo y comienza una cuenta atrás de 5 segundos.\n\n'
          '5. Ganáis al completar una ronda jugando al menos el 79 % de la baraja. No hay cartas especiales.\n\n'
          'Cada ronda dura como máximo 5 segundos por carta de la baraja. Con 100 cartas: 8 min 20 s.\n\n'
          'Si se pierde la conexión, tienes 30 segundos desde su detección para volver. Después se retiran tus cartas y observas la partida. Mantén la app abierta al jugar.\n\n'
          'Las salas caducan tras 15 minutos sin acciones. Al terminar una partida, puede aparecer publicidad al continuar.',
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Conectemos'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final active = game.hasSession;
    return PopScope(
      canPop: !active && !finishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !finishing) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset('assets/icon.png', width: 34, height: 34),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'synchrony',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Cómo jugar',
              onPressed: _help,
              icon: const Icon(Icons.help_outline_rounded),
            ),
            IconButton(
              tooltip: 'Ajustes',
              onPressed: finishing ? null : _settings,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-.8, -.5),
                radius: 1.6,
                colors: [Color(0xff18392f), ink],
              ),
            ),
            child: SizedBox.expand(
              child: finishing || game.restoring
                  ? const Center(child: CircularProgressIndicator())
                  : AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      child: !active
                          ? _home()
                          : game.state == null
                          ? _recovering()
                          : _room(game.state!),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recovering() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          const Text('Recuperando vuestra conexión…'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _leave,
            child: const Text('Volver al inicio'),
          ),
        ],
      ),
    ),
  );
  Widget _home() => Center(
    key: const ValueKey('home'),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final introduction = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UN EQUIPO. UN MISMO LATIDO.',
                  style: TextStyle(color: lime, fontSize: 11, letterSpacing: 2),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No es suerte.\nEs sincronía.',
                  style: TextStyle(
                    fontSize: 43,
                    fontWeight: FontWeight.w400,
                    height: 1.06,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cartas en orden. Mentes conectadas.\nSin hablar de números. Solo vuestro instinto.',
                  style: TextStyle(color: muted, height: 1.6),
                ),
                if (bounds.maxWidth > 740) ...[
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 210,
                    child: Stack(
                      children: [
                        Transform.rotate(
                          angle: -.2,
                          child: const PlayingCard(
                            number: 8,
                            deck: 100,
                            width: 120,
                            height: 168,
                          ),
                        ),
                        const Positioned(
                          left: 80,
                          top: 0,
                          child: PlayingCard(
                            number: 34,
                            deck: 100,
                            width: 120,
                            height: 168,
                          ),
                        ),
                        Positioned(
                          left: 170,
                          top: 13,
                          child: Transform.rotate(
                            angle: .2,
                            child: const PlayingCard(
                              number: 72,
                              deck: 100,
                              width: 120,
                              height: 168,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
            final entry = Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: panel.withValues(alpha: .9),
                border: Border.all(color: const Color(0xff345046)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'El siguiente latido eres tú.',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: name,
                      maxLength: 24,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Tu nombre',
                        counterText: '',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Escribe tu nombre.'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'create', label: Text('Crear')),
                        ButtonSegment(value: 'join', label: Text('Unirme')),
                        ButtonSegment(value: 'match', label: Text('Online')),
                      ],
                      selected: {mode},
                      onSelectionChanged: game.busy
                          ? null
                          : (v) => setState(() => mode = v.first),
                    ),
                    const SizedBox(height: 22),
                    if (mode == 'create')
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: players,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Jugadores',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: deck,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Baraja',
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (mode == 'join')
                      TextFormField(
                        controller: code,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          labelText: 'Código o enlace de sala',
                          hintText: 'aB3xY9',
                        ),
                      ),
                    if (mode == 'match')
                      DropdownButtonFormField<int>(
                        initialValue: onlinePlayers,
                        decoration: const InputDecoration(
                          labelText: 'Tamaño del equipo',
                        ),
                        items: [
                          for (var n = 2; n <= 8; n++)
                            DropdownMenuItem(
                              value: n,
                              child: Text('$n jugadores'),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => onlinePlayers = v ?? 2),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      mode == 'create'
                          ? 'Sala privada. Sin el límite online de 8 jugadores.'
                          : mode == 'join'
                          ? 'El código distingue mayúsculas y minúsculas.'
                          : 'Buscamos personas para vuestro equipo. Baraja de 100 cartas.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: muted,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: game.busy ? null : _enter,
                      icon: game.busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.north_east_rounded),
                      label: Text(
                        game.busy
                            ? 'Conectando…'
                            : mode == 'create'
                            ? 'Crear partida'
                            : mode == 'join'
                            ? 'Enlazarme a la sala'
                            : 'Buscar partida',
                      ),
                    ),
                    if (server.text.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextButton(
                          onPressed: _settings,
                          child: const Text('Configurar servidor'),
                        ),
                      ),
                  ],
                ),
              ),
            );
            if (bounds.maxWidth > 740) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: introduction),
                  const SizedBox(width: 36),
                  Expanded(child: entry),
                ],
              );
            }
            return Column(
              children: [introduction, const SizedBox(height: 28), entry],
            );
          },
        ),
      ),
    ),
  );
  Widget _room(GameState s) {
    final landscape = MediaQuery.sizeOf(context).width > 740;
    final header = Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          s.code,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 25,
            letterSpacing: 3,
          ),
        ),
        IconButton(
          tooltip: 'Copiar código',
          onPressed: () => _copy(s.code),
          icon: const Icon(Icons.copy_rounded, size: 20),
        ),
        IconButton(
          tooltip: 'Copiar enlace web',
          onPressed: () {
            final uri = Uri.tryParse(web.text);
            if (uri == null || uri.host.isEmpty) {
              _notice(
                'Configura la dirección de la web en Ajustes para compartir enlaces.',
              );
              return;
            }
            _copy(uri.replace(queryParameters: {'sala': s.code}).toString());
          },
          icon: const Icon(Icons.link_rounded),
        ),
        Text(
          game.connected ? 'Conectados' : 'Reconectando…',
          style: TextStyle(
            color: game.connected ? lime : Colors.orange,
            fontSize: 12,
          ),
        ),
        TextButton(
          onPressed: game.busy ? null : _leave,
          child: const Text('Salir'),
        ),
      ],
    );
    final crew = SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: s.players.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final p = s.players[index];
          return Container(
            width: 178,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: p.id == s.me
                    ? lime.withValues(alpha: .4)
                    : const Color(0xff294045),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: HSLColor.fromAHSL(
                    1,
                    ((index * 53 + 100) % 360).toDouble(),
                    .2,
                    .25,
                  ).toColor(),
                  child: Text(
                    p.name.characters.take(2).toString().toUpperCase(),
                    style: const TextStyle(fontSize: 12, color: lime),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.name}${p.id == s.me ? ' · tú' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        p.excluded
                            ? 'Espectador'
                            : !p.online
                            ? 'Reconectando'
                            : p.ready
                            ? 'Listo ✓'
                            : s.phase == 'playing'
                            ? '${p.count} cartas'
                            : 'Esperando',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.ready ? lime : muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    final table = Column(children: [_stats(s), _arena(s), _progress(s)]);
    final controls = Column(
      children: [_status(s), const SizedBox(height: 20), _hand(s)],
    );
    return Center(
      key: const ValueKey('room'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1150),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              crew,
              const SizedBox(height: 20),
              if (landscape)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: table),
                    const SizedBox(width: 24),
                    Expanded(child: controls),
                  ],
                )
              else ...[
                table,
                const SizedBox(height: 12),
                controls,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stats(GameState s) {
    final remaining = s.deadline == null
        ? null
        : math.max(0, ((s.deadline! - game.serverNow) / 1000).ceil());
    final timer = remaining == null
        ? '—'
        : '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}';
    Widget stat(String title, Widget value) => Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            color: muted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 7),
        value,
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        stat(
          'RONDA',
          Text(
            s.round.toString().padLeft(2, '0'),
            style: const TextStyle(fontSize: 24),
          ),
        ),
        stat(
          'VIDAS',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 5; i++)
                Icon(
                  i < s.lives
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  color: i < s.lives ? lime : const Color(0xff3c5353),
                  size: 20,
                ),
            ],
          ),
        ),
        stat(
          'TIEMPO',
          Text(
            timer,
            style: TextStyle(
              fontSize: 23,
              color: remaining != null && remaining <= 30
                  ? const Color(0xffff8790)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _arena(GameState s) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final countdown = s.phase == 'countdown'
        ? math.max(1, ((s.countdownAt! - game.serverNow) / 1000).ceil())
        : null;
    return SizedBox(
      height: 273,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: breathing,
              builder: (context, _) => CustomPaint(
                painter: OrbitPainter(reduce ? .5 : breathing.value),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'UN MISMO LATIDO',
                style: TextStyle(fontSize: 10, color: muted, letterSpacing: 2),
              ),
              const SizedBox(height: 17),
              AnimatedSwitcher(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 360),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: PlayingCard(
                  key: ValueKey('${s.round}:${s.last}'),
                  number: s.last,
                  deck: s.deck,
                  width: 106,
                  height: 146,
                ),
              ),
              const SizedBox(height: 17),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  s.eventText,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: s.phase == 'retry' || s.phase == 'lost'
                        ? const Color(0xffff9da3)
                        : muted,
                  ),
                ),
              ),
            ],
          ),
          if (countdown != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Text(
                      '$countdown',
                      key: ValueKey(countdown),
                      style: const TextStyle(
                        fontSize: 100,
                        fontWeight: FontWeight.w200,
                        color: lime,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: celebration,
                builder: (context, _) => CustomPaint(
                  painter: Celebration(
                    celebration.value == 0 ? 1 : celebration.value,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress(GameState s) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              s.phase == 'lobby'
                  ? '${s.players.length} / ${s.capacity} jugadores'
                  : '${s.played} / ${s.dealt} jugadas${s.removed > 0 ? ' · ${s.removed} retiradas' : ''}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ),
          Text(
            'Meta ${s.target} · Baraja ${s.deck}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
      const SizedBox(height: 9),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          minHeight: 3,
          value: s.dealt == 0
              ? 0
              : ((s.played + s.removed) / s.dealt).clamp(0.0, 1.0).toDouble(),
        ),
      ),
    ],
  );
  Widget _status(GameState s) {
    final (title, subtitle) = switch (s.phase) {
      'lobby' => (
        'Conectando mentes…',
        'Todos debéis estar aquí y pulsar Estoy listo.',
      ),
      'countdown' => (
        'Respirad juntos.',
        'Las cartas están a punto de llegar.',
      ),
      'playing' => (
        'Confía en tu intuición.',
        'De menor a mayor. Sin turnos. Sin decir los números.',
      ),
      'between' => (
        'Ronda superada.',
        'Ahora recibiréis hasta ${s.round} cartas por persona.',
      ),
      'retry' => (
        'Un latido a destiempo.',
        'Repetimos la ronda ${s.round}. Quedan ${s.lives} vidas.',
      ),
      'won' => (
        'Sincronía perfecta.',
        'Habéis enlazado vuestras mentes. ${s.played} cartas jugadas.',
      ),
      'lost' => (
        'El silencio también enseña.',
        'No quedan vidas. Podéis volver a intentarlo.',
      ),
      _ => (
        'La conexión ha terminado.',
        'Ya no quedan participantes en esta partida.',
      ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: s.phase == 'retry' || s.phase == 'lost'
            ? const Color(0xff35272c)
            : panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.finished ? lime : const Color(0xff365449)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
          ),
          if (s.canReady || s.finished || s.phase == 'abandoned') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    game.busy ||
                        (!game.connected &&
                            !s.finished &&
                            s.phase != 'abandoned')
                    ? null
                    : () {
                        if (s.finished) {
                          _finish();
                        } else if (s.phase == 'abandoned') {
                          game.leave();
                        } else {
                          game.action('ready');
                        }
                      },
                icon: Icon(
                  s.finished ? Icons.north_east_rounded : Icons.check_rounded,
                ),
                label: Text(
                  s.finished
                      ? 'Continuar'
                      : s.phase == 'abandoned'
                      ? 'Volver al inicio'
                      : s.self?.ready == true
                      ? 'Estoy listo ✓'
                      : 'Estoy listo',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hand(GameState s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            'Tu mano · ${s.hand.length}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              s.self?.excluded == true
                  ? 'Observas la partida'
                  : 'Solo tú ves tus cartas',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (s.hand.isEmpty)
        Padding(
          padding: const EdgeInsets.all(22),
          child: Text(
            s.self?.excluded == true
                ? 'Tu equipo sigue jugando.'
                : s.phase == 'playing'
                ? 'Ya has jugado tus cartas. Confía en tu equipo.'
                : 'Las cartas llegarán cuando estéis todos listos.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        )
      else
        SizedBox(
          height: s.hand.length <= 4 ? 122 : 250,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 98,
              mainAxisExtent: 116,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
            ),
            itemCount: s.hand.length,
            itemBuilder: (context, index) => PlayingCard(
              number: s.hand[index],
              deck: s.deck,
              enabled: game.connected && !game.busy && s.canPlay,
              onTap: () {
                unawaited(feedback.play('card', vibration: vibration));
                game.action('play', card: s.hand[index]);
              },
            ),
          ),
        ),
    ],
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    game.removeListener(_changed);
    ads.removeListener(_adsChanged);
    game.dispose();
    ads.dispose();
    feedback.dispose();
    breathing.dispose();
    celebration.dispose();
    for (final c in [name, server, web, players, deck, code]) {
      c.dispose();
    }
    super.dispose();
  }
}
