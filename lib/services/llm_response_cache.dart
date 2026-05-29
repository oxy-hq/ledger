/// In-memory cache of LLM responses keyed by the logged row's id. Lost
/// on app restart (good enough for surfacing the post-log comment
/// during the user's session). Could be persisted to sqflite later if
/// the user wants historical comments.
///
/// Listeners are notified when an entry is added/removed so the timeline
/// can rebuild the relevant row.
class LlmResponseCache {
  final Map<String, String> _byRowId = {};
  final Set<void Function()> _listeners = {};

  String? get(String rowId) => _byRowId[rowId];

  /// True while a request is in-flight for this id (a response can be
  /// loading even when the cache doesn't have a value yet).
  final Set<String> _pending = {};
  bool isPending(String rowId) => _pending.contains(rowId);

  void markPending(String rowId) {
    _pending.add(rowId);
    _notify();
  }

  void put(String rowId, String response) {
    _byRowId[rowId] = response;
    _pending.remove(rowId);
    _notify();
  }

  void putError(String rowId, String error) {
    _byRowId[rowId] = '⚠️ $error';
    _pending.remove(rowId);
    _notify();
  }

  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) =>
      _listeners.remove(listener);

  void _notify() {
    for (final l in _listeners) {
      l();
    }
  }
}
