import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../sync/diary_keeper_api.dart';
import '../sync/night_upload.dart';
import 'settings.dart';

/// The app's account on the Diary Keeper, and sending nights there.
///
/// Signed in = a refresh token for the Diary Keeper at [Settings.diaryKeeperUrl]. Nights are still
/// recorded on this device first; the Diary Keeper gets a copy, so nothing is lost when it's offline.
class Account extends ChangeNotifier {
  Account(this.settings, {http.Client? client}) : _client = client;

  final Settings settings;
  final http.Client? _client;

  bool busy = false;
  String status = '';

  /// Uploads in progress or done, by night folder: a line of progress, or the result.
  final Map<String, String> uploads = {};

  bool get signedIn =>
      settings.refreshToken != null && settings.accountServer == settings.diaryKeeperUrl && settings.accountEmail != null;

  String? get email => settings.accountEmail;

  DiaryKeeperApi _api({String? refreshToken}) => DiaryKeeperApi(
        settings.diaryKeeperUrl,
        client: _client,
        refreshToken: refreshToken ?? settings.refreshToken,
        onTokens: (_, refresh) => settings.saveRefreshToken(refresh),
      );

  Future<bool> signIn(String email, String password) => _authenticate(email, (api) => api.login(email, password));

  /// Creates an account. The Diary Keeper asks for consent to its current privacy text first.
  Future<bool> register(String email, String password) => _authenticate(email, (api) async {
        final version = await api.version();
        if (version['registration_open'] == false) {
          throw DiaryKeeperException(403, 'This Diary Keeper doesn\'t take new accounts.');
        }
        return api.register(email, password, consentVersion: version['consent_version'] as String);
      });

  Future<bool> _authenticate(String email, Future<Map<String, dynamic>> Function(DiaryKeeperApi) run) async {
    busy = true;
    status = 'Talking to the Diary Keeper...';
    notifyListeners();
    final api = _api(refreshToken: '');
    try {
      final user = await run(api);
      settings.saveAccount(email: (user['email'] as String?) ?? email.trim().toLowerCase(), server: api.baseUrl, refreshToken: api.refreshToken!);
      status = 'Signed in as ${settings.accountEmail}.';
      return true;
    } on DiaryKeeperException catch (e) {
      status = e.status == 401 ? 'Wrong email or password.' : e.toString();
      return false;
    } catch (e) {
      status = 'Something went wrong: $e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final api = _api();
    try {
      await api.logout();
    } catch (_) {
      // Signed out on this device either way.
    }
    settings.forgetAccount();
    status = 'Signed out.';
    notifyListeners();
  }

  /// Sends one night (its folder on this device) to the Diary Keeper. Safe to repeat.
  Future<bool> upload(Directory night) async {
    final key = night.path;
    if (!signedIn) {
      uploads[key] = 'Sign in to the Diary Keeper first (Settings).';
      notifyListeners();
      return false;
    }
    final api = _api();
    void say(String line) {
      uploads[key] = line;
      notifyListeners();
    }

    try {
      say('Reading the night...');
      final package = await NightPackage.read(night);
      await package.upload(api, progress: say);
      say('Sent to the Diary Keeper: ${package.epochs.length} epochs, ${package.events.length} events, ${package.files.length} files.');
      return true;
    } on DiaryKeeperException catch (e) {
      if (e.unauthorized) settings.forgetAccount();
      say(e.unauthorized ? 'Signed out by the Diary Keeper. Sign in again and retry.' : 'Not sent: $e');
      return false;
    } catch (e) {
      say('Not sent: $e');
      return false;
    }
  }

  /// After a night is saved: send it, when signed in and automatic upload is on.
  void nightSaved(String folder) {
    if (signedIn && settings.autoUpload) upload(Directory(folder));
  }
}
