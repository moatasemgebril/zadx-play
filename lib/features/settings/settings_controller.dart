import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/catalog/locations.dart';
import '../../services/app_lock/lock_rules.dart';

/// Overridden in main() with the real instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPrefsProvider must be overridden in main()'),
);

const supportedLanguages = ['ar', 'en'];

/// Languages shown as "coming soon" in the picker.
const upcomingLanguages = {'fr': 'Français', 'tr': 'Türkçe', 'ur': 'اردو', 'id': 'Indonesia'};

@immutable
class AppSettings {
  const AppSettings({
    this.language = 'ar',
    this.countryId = 'eg',
    this.cityId = 'cairo',
    this.methodId = 'egypt',
    this.asrFactor = 1,
    this.muezzinId = 'madinah_rec',
    this.reciterId = 'afasy',
    this.lockAtAdhan = true,
    this.notifyParentOnTasks = true,
    this.notifyParentOnAdhan = true,
    this.controlledGameIds = const {'roblox', 'minecraft', 'brawlstars', 'subway', 'stumble'},
    this.parentPinHash,
    this.soundEffectsOn = true,
    this.sfxVolume = 0.6,
    this.lockMode = LockMode.allApps,
    this.allowedApps = const {},
    this.allowMessaging = true,
    this.pcAllowBrowsers = false,
    this.dailyLimitMinutes = 60,
  });

  final String language;
  final String countryId;
  final String cityId;
  final String methodId;
  final int asrFactor;
  final String muezzinId;
  final String reciterId;
  final bool lockAtAdhan;
  final bool notifyParentOnTasks;
  final bool notifyParentOnAdhan;
  final Set<String> controlledGameIds;
  final String? parentPinHash;

  /// Short sound effects (taps, stars, chimes). On by default.
  final bool soundEffectsOn;

  /// 0.0–1.0, effects volume.
  final double sfxVolume;

  /// Device-wide lock (default) or legacy "selected games only". docs/decisions/DEVICE-WIDE-LOCK.md
  final LockMode lockMode;

  /// Android packages the parent always allows in [LockMode.allApps] (school apps, camera, maps…).
  final Set<String> allowedApps;

  /// SMS + contacts stay open in [LockMode.allApps]. Phone/emergency calls are never locked.
  final bool allowMessaging;

  /// Windows Guard: keep browsers open (homework) in [LockMode.allApps].
  final bool pcAllowBrowsers;

  /// Plans without tasks (Free): screen minutes per day before the lock closes (prayer lock still applies).
  final int dailyLimitMinutes;

  Locale get locale => Locale(language);
  bool get isRtl => language == 'ar' || language == 'ur';

  AppSettings copyWith({
    String? language,
    String? countryId,
    String? cityId,
    String? methodId,
    int? asrFactor,
    String? muezzinId,
    String? reciterId,
    bool? lockAtAdhan,
    bool? notifyParentOnTasks,
    bool? notifyParentOnAdhan,
    Set<String>? controlledGameIds,
    String? parentPinHash,
    bool? soundEffectsOn,
    double? sfxVolume,
    LockMode? lockMode,
    Set<String>? allowedApps,
    bool? allowMessaging,
    bool? pcAllowBrowsers,
    int? dailyLimitMinutes,
  }) =>
      AppSettings(
        language: language ?? this.language,
        countryId: countryId ?? this.countryId,
        cityId: cityId ?? this.cityId,
        methodId: methodId ?? this.methodId,
        asrFactor: asrFactor ?? this.asrFactor,
        muezzinId: muezzinId ?? this.muezzinId,
        reciterId: reciterId ?? this.reciterId,
        lockAtAdhan: lockAtAdhan ?? this.lockAtAdhan,
        notifyParentOnTasks: notifyParentOnTasks ?? this.notifyParentOnTasks,
        notifyParentOnAdhan: notifyParentOnAdhan ?? this.notifyParentOnAdhan,
        controlledGameIds: controlledGameIds ?? this.controlledGameIds,
        parentPinHash: parentPinHash ?? this.parentPinHash,
        soundEffectsOn: soundEffectsOn ?? this.soundEffectsOn,
        sfxVolume: sfxVolume ?? this.sfxVolume,
        lockMode: lockMode ?? this.lockMode,
        allowedApps: allowedApps ?? this.allowedApps,
        allowMessaging: allowMessaging ?? this.allowMessaging,
        pcAllowBrowsers: pcAllowBrowsers ?? this.pcAllowBrowsers,
        dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
      );
}

class SettingsController extends Notifier<AppSettings> {
  static const _k = 'settings.';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final p = _prefs;
    const d = AppSettings();
    return AppSettings(
      language: p.getString('${_k}language') ?? _deviceLanguage(),
      countryId: p.getString('${_k}country') ?? d.countryId,
      cityId: p.getString('${_k}city') ?? d.cityId,
      methodId: p.getString('${_k}method') ?? d.methodId,
      asrFactor: p.getInt('${_k}asr') ?? d.asrFactor,
      muezzinId: p.getString('${_k}muezzin') ?? d.muezzinId,
      reciterId: p.getString('${_k}reciter') ?? d.reciterId,
      lockAtAdhan: p.getBool('${_k}lockAtAdhan') ?? d.lockAtAdhan,
      notifyParentOnTasks: p.getBool('${_k}notifyTasks') ?? d.notifyParentOnTasks,
      notifyParentOnAdhan: p.getBool('${_k}notifyAdhan') ?? d.notifyParentOnAdhan,
      controlledGameIds: p.getStringList('${_k}games')?.toSet() ?? d.controlledGameIds,
      parentPinHash: p.getString('${_k}pin'),
      soundEffectsOn: p.getBool('${_k}sfxOn') ?? d.soundEffectsOn,
      sfxVolume: (p.getDouble('${_k}sfxVolume') ?? d.sfxVolume).clamp(0.0, 1.0),
      lockMode: LockMode.parse(p.getString('${_k}lockMode')),
      allowedApps: p.getStringList('${_k}allowedApps')?.toSet() ?? d.allowedApps,
      allowMessaging: p.getBool('${_k}allowMessaging') ?? d.allowMessaging,
      pcAllowBrowsers: p.getBool('${_k}pcAllowBrowsers') ?? d.pcAllowBrowsers,
      dailyLimitMinutes: (p.getInt('${_k}dailyLimit') ?? d.dailyLimitMinutes).clamp(0, 24 * 60),
    );
  }

  String _deviceLanguage() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return supportedLanguages.contains(code) ? code : 'ar';
  }

  void setLanguage(String code) {
    if (!supportedLanguages.contains(code)) return;
    state = state.copyWith(language: code);
    _prefs.setString('${_k}language', code);
  }

  /// Picking a country selects its first city and its default method/Asr rule.
  void setCountry(String countryId) {
    final c = countryById(countryId);
    final firstCity = citiesOf(countryId).first;
    state = state.copyWith(
      countryId: c.id,
      cityId: firstCity.id,
      methodId: c.methodId,
      asrFactor: c.asrFactor,
    );
    _prefs
      ..setString('${_k}country', c.id)
      ..setString('${_k}city', firstCity.id)
      ..setString('${_k}method', c.methodId)
      ..setInt('${_k}asr', c.asrFactor);
  }

  void setCity(String cityId) {
    state = state.copyWith(cityId: cityId);
    _prefs.setString('${_k}city', cityId);
  }

  void setMethod(String methodId) {
    state = state.copyWith(methodId: methodId);
    _prefs.setString('${_k}method', methodId);
  }

  void setAsrFactor(int factor) {
    state = state.copyWith(asrFactor: factor);
    _prefs.setInt('${_k}asr', factor);
  }

  void setMuezzin(String id) {
    state = state.copyWith(muezzinId: id);
    _prefs.setString('${_k}muezzin', id);
  }

  void setReciter(String id) {
    state = state.copyWith(reciterId: id);
    _prefs.setString('${_k}reciter', id);
  }

  /// Returns false when the plan limit would be exceeded.
  bool toggleGame(String gameId, {required int maxGames}) {
    final next = {...state.controlledGameIds};
    if (next.contains(gameId)) {
      next.remove(gameId);
    } else {
      if (next.length >= maxGames) return false;
      next.add(gameId);
    }
    state = state.copyWith(controlledGameIds: next);
    _prefs.setStringList('${_k}games', next.toList());
    return true;
  }

  void setLockMode(LockMode mode) {
    state = state.copyWith(lockMode: mode);
    _prefs.setString('${_k}lockMode', mode.name);
  }

  /// Adds or removes an Android package from the parent's allow-list. Zad X and the
  /// always-allowed core are handled natively and need no entry here.
  void setAppAllowed(String package, bool allowed) {
    if (package.trim().isEmpty) return;
    final next = {...state.allowedApps};
    if (allowed) {
      next.add(package);
    } else {
      next.remove(package);
    }
    state = state.copyWith(allowedApps: next);
    _prefs.setStringList('${_k}allowedApps', next.toList()..sort());
  }

  void setAllowMessaging(bool v) {
    state = state.copyWith(allowMessaging: v);
    _prefs.setBool('${_k}allowMessaging', v);
  }

  void setPcAllowBrowsers(bool v) {
    state = state.copyWith(pcAllowBrowsers: v);
    _prefs.setBool('${_k}pcAllowBrowsers', v);
  }

  void setDailyLimitMinutes(int minutes) {
    final v = minutes.clamp(0, 24 * 60);
    state = state.copyWith(dailyLimitMinutes: v);
    _prefs.setInt('${_k}dailyLimit', v);
  }

  void setLockAtAdhan(bool v) {
    state = state.copyWith(lockAtAdhan: v);
    _prefs.setBool('${_k}lockAtAdhan', v);
  }

  void setNotifyOnTasks(bool v) {
    state = state.copyWith(notifyParentOnTasks: v);
    _prefs.setBool('${_k}notifyTasks', v);
  }

  void setNotifyOnAdhan(bool v) {
    state = state.copyWith(notifyParentOnAdhan: v);
    _prefs.setBool('${_k}notifyAdhan', v);
  }

  void setSoundEffectsOn(bool v) {
    state = state.copyWith(soundEffectsOn: v);
    _prefs.setBool('${_k}sfxOn', v);
  }

  void setSfxVolume(double v) {
    final clamped = v.isNaN ? const AppSettings().sfxVolume : v.clamp(0.0, 1.0);
    state = state.copyWith(sfxVolume: clamped);
    _prefs.setDouble('${_k}sfxVolume', clamped);
  }

  void setParentPinHash(String hash) {
    state = state.copyWith(parentPinHash: hash);
    _prefs.setString('${_k}pin', hash);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
