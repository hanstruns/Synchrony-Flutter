import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/game_state.dart';
import 'ad_gate.dart';

class AdsService extends ChangeNotifier {
  final SharedPreferences prefs;
  late final AdGate gate;
  InterstitialAd? _ad;
  bool _loading = false, _initializing = false, _initialized = false;
  bool privacyRequired = false, showing = false, _disposed = false;
  int _consentEpoch = 0;
  DateTime? _lastAttempt;
  String status = 'Sin iniciar';
  Timer? _retryTimer;
  void _status(String value) {
    status = value;
    _notify();
  }

  Future<void> retry() async {
    if (_disposed || _loading || _initializing || showing) return;
    _retryTimer?.cancel();
    _lastAttempt = null;
    if (_ad != null) {
      _status('Listo para el final de la partida');
      return;
    }
    if (_initialized) {
      await preload();
    } else {
      await initialize();
    }
  }

  void _retryLater() {
    _retryTimer?.cancel();
    if (!_disposed) {
      _retryTimer = Timer(
        const Duration(seconds: 31),
        () => unawaited(preload()),
      );
    }
  }

  AdsService(this.prefs) {
    gate = AdGate(prefs.getStringList('ad_results') ?? []);
  }
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  String get _unit => AppConfig.testAds
      ? (Platform.isAndroid
            ? 'ca-app-pub-3940256099942544/1033173712'
            : 'ca-app-pub-3940256099942544/4411468910')
      : (Platform.isAndroid
            ? AppConfig.androidInterstitial
            : AppConfig.iosInterstitial);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (!supported) {
      _status('Solo disponible en Android/iOS');
      return;
    }
    if (_initializing || _disposed) return;
    _status('Inicializando…');
    _initializing = true;
    // La configuración de prueba puede no tener mensajes UMP publicados.
    // Nunca se utiliza esta excepción con unidades publicitarias reales.
    if (AppConfig.testAds) {
      await _enable();
      _initializing = false;
      return;
    }
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => ConsentForm.loadAndShowConsentFormIfRequired(
          (_) => _refreshConsent(),
        ),
        (_) => _refreshConsent(),
      );
    } catch (error) {
      _initializing = false;
      _status('Error de consentimiento: $error');
    }
  }

  Future<void> _refreshConsent() async {
    if (_disposed) return;
    try {
      privacyRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (await ConsentInformation.instance.canRequestAds()) {
        await _enable();
      } else {
        _status('No disponible: revisar consentimiento de AdMob');
      }
    } catch (error) {
      _status('Error de consentimiento: $error');
    } finally {
      _initializing = false;
      _notify();
    }
  }

  Future<void> _enable() async {
    if (_disposed) return;
    try {
      if (!_initialized) {
        await MobileAds.instance.initialize();
        _initialized = true;
      }
      await preload();
    } catch (error) {
      _status('Error al iniciar el SDK: $error');
      /* Un fallo de publicidad no bloquea el juego. */
    }
  }

  Future<void> preload() async {
    if (!_initialized || _ad != null || _loading || _disposed || showing) {
      return;
    }
    if (_lastAttempt != null &&
        DateTime.now().difference(_lastAttempt!).inSeconds < 30) {
      return;
    }
    if (!AppConfig.testAds &&
        !await ConsentInformation.instance.canRequestAds()) {
      return;
    }
    _loading = true;
    _status('Cargando…');
    _lastAttempt = DateTime.now();
    final epoch = _consentEpoch;
    try {
      await InterstitialAd.load(
        adUnitId: _unit,
        request: const AdRequest(nonPersonalizedAds: true),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _loading = false;
            if (_disposed || epoch != _consentEpoch) {
              ad.dispose();
              return;
            }
            _ad = ad;
            _retryTimer?.cancel();
            _status('Listo para el final de la partida');
          },
          onAdFailedToLoad: (error) {
            _loading = false;
            if (_disposed || epoch != _consentEpoch) return;
            _status('Error ${error.code}: ${error.message}');
            _retryLater();
          },
        ),
      );
    } catch (error) {
      _loading = false;
      _status('Error de carga: $error');
      _retryLater();
    }
  }

  Future<void> showForResult(GameState state) async {
    if (!supported || showing || _disposed) return;
    if (!gate.claim(
      state.adKey,
      state.phase,
      spectator: state.self?.excluded ?? true,
    )) {
      return;
    }
    final keys = gate.consumed.toList();
    try {
      await prefs.setStringList(
        'ad_results',
        keys.skip(keys.length > 200 ? keys.length - 200 : 0).toList(),
      );
    } catch (_) {
      /* La deduplicación se mantiene al menos durante este proceso. */
    }
    if (!AppConfig.testAds &&
        !await ConsentInformation.instance.canRequestAds()) {
      return;
    }
    final ad = _ad;
    _ad = null;
    if (ad == null) {
      unawaited(preload());
      return;
    }
    final done = Completer<void>();
    showing = true;
    _status('Mostrando anuncio');
    void finish() {
      ad.dispose();
      showing = false;
      _lastAttempt = null;
      _status('Anuncio cerrado');
      if (!done.isCompleted) done.complete();
      unawaited(preload());
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (_) => finish(),
      onAdFailedToShowFullScreenContent: (_, _) => finish(),
    );
    try {
      await ad.show();
    } catch (_) {
      finish();
    }
    // No se oculta el botón del SDK ni se fuerza una duración artificial.
    await done.future;
  }

  Future<void> openPrivacy() async {
    if (!supported || !privacyRequired || showing) return;
    ++_consentEpoch;
    _ad?.dispose();
    _ad = null;
    ConsentForm.showPrivacyOptionsForm((_) => _refreshConsent());
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    ++_consentEpoch;
    _ad?.dispose();
    super.dispose();
  }
}
