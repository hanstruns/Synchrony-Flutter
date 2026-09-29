/// Una transición al resultado habilita una sola oportunidad de anuncio.
/// La clave combina sala e identidad de jugador, no el evento SSE mutable.
class AdGate {
  final Set<String> consumed;
  AdGate(Iterable<String> previous) : consumed = {...previous};
  bool claim(String key, String phase, {required bool spectator}) {
    if (spectator || (phase != 'won' && phase != 'lost')) return false;
    return consumed.add(key);
  }
}
