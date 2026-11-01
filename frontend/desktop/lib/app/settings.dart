import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings that survive closing the app.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static const defaultDiaryKeeperUrl = 'http://localhost:8000';

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Where the Diary Keeper (the backend) lives. On a phone this is the laptop's address on the home Wi-Fi.
  String get diaryKeeperUrl => _prefs.getString('diaryKeeperUrl') ?? defaultDiaryKeeperUrl;

  set diaryKeeperUrl(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'/+$'), '');
    _prefs.setString('diaryKeeperUrl', cleaned.isEmpty ? defaultDiaryKeeperUrl : cleaned);
    notifyListeners();
  }

  /// The power grid's frequency: 50 Hz in Europe, Africa, most of Asia; 60 Hz in the Americas.
  int get mainsHz => _prefs.getInt('mainsHz') ?? 50;

  set mainsHz(int value) {
    _prefs.setInt('mainsHz', value);
    notifyListeners();
  }
}
