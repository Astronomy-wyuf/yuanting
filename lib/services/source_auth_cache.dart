import 'package:shared_preferences/shared_preferences.dart';

/// 书源 auth 令牌进程内 + SharedPreferences 缓存
class SourceAuthCache {
  SourceAuthCache(this.prefs);

  final SharedPreferences prefs;
  final Map<String, _Entry> _memory = {};

  static String _key(String sourceId, String authId) =>
      'source_auth_${sourceId}_$authId';

  String? get(String sourceId, String authId) {
    final mem = _memory[_key(sourceId, authId)];
    if (mem != null && !mem.expired) return mem.token;
    final raw = prefs.getString(_key(sourceId, authId));
    final exp = prefs.getInt('${_key(sourceId, authId)}_exp') ?? 0;
    if (raw == null || raw.isEmpty) return null;
    if (exp > 0 && DateTime.now().millisecondsSinceEpoch > exp) {
      clear(sourceId, authId);
      return null;
    }
    _memory[_key(sourceId, authId)] = _Entry(
      raw,
      exp > 0
          ? DateTime.fromMillisecondsSinceEpoch(exp)
          : DateTime.now().add(const Duration(days: 365)),
    );
    return raw;
  }

  Future<void> set(
    String sourceId,
    String authId,
    String token, {
    required int ttlSec,
  }) async {
    final exp = DateTime.now().add(Duration(seconds: ttlSec < 1 ? 3600 : ttlSec));
    _memory[_key(sourceId, authId)] = _Entry(token, exp);
    await prefs.setString(_key(sourceId, authId), token);
    await prefs.setInt(
        '${_key(sourceId, authId)}_exp', exp.millisecondsSinceEpoch);
  }

  Future<void> clear(String sourceId, String authId) async {
    _memory.remove(_key(sourceId, authId));
    await prefs.remove(_key(sourceId, authId));
    await prefs.remove('${_key(sourceId, authId)}_exp');
  }
}

class _Entry {
  final String token;
  final DateTime expiresAt;
  _Entry(this.token, this.expiresAt);
  bool get expired => DateTime.now().isAfter(expiresAt);
}
