import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TvModePreference {
  auto,
  tv,
  mobile,
}

/// Service to detect Android TV / Leanback environments and control TV mode UI.
class TvModeService extends ChangeNotifier {
  static final TvModeService instance = TvModeService();

  static const _channel = MethodChannel('com.mbx.stream/tv_mode');
  static const String _prefKey = 'mbx_tv_mode_pref_v1';

  SharedPreferences? _prefs;
  TvModePreference _preference = TvModePreference.auto;
  bool _isTvHardware = false;

  TvModePreference get preference => _preference;
  bool get isTvHardware => _isTvHardware;

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();

    final savedPref = _prefs?.getString(_prefKey);
    if (savedPref == 'tv') {
      _preference = TvModePreference.tv;
    } else if (savedPref == 'mobile') {
      _preference = TvModePreference.mobile;
    } else {
      _preference = TvModePreference.auto;
    }

    await detectHardware();
  }

  Future<void> detectHardware() async {
    try {
      final bool? isTv = await _channel.invokeMethod<bool>('isTvDevice');
      _isTvHardware = isTv ?? false;
    } catch (_) {
      _isTvHardware = false;
    }

    notifyListeners();
  }

  bool isTvMode(BuildContext context) {
    switch (_preference) {
      case TvModePreference.tv:
        return true;
      case TvModePreference.mobile:
        return false;
      case TvModePreference.auto:
        if (_isTvHardware) return true;
        final size = MediaQuery.of(context).size;
        // Widescreen 16:9 TV / Desktop presentation
        final isWidescreen = size.width >= 750 && (size.width / (size.height > 0 ? size.height : 1) >= 1.3);
        return isWidescreen;
    }
  }

  Future<void> setPreference(TvModePreference pref) async {
    _preference = pref;
    _prefs ??= await SharedPreferences.getInstance();
    final str = pref == TvModePreference.tv
        ? 'tv'
        : (pref == TvModePreference.mobile ? 'mobile' : 'auto');
    await _prefs?.setString(_prefKey, str);
    notifyListeners();
  }
}
