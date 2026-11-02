import 'dart:ffi';
import 'dart:io';

/// Keeps the computer from going to sleep while a night is being recorded.
///
/// On Windows this calls the Win32 function SetThreadExecutionState through dart:ffi: no plugin needed.
/// The screen may still turn off (that's fine and saves power); the computer keeps running.
/// Other platforms: not implemented yet (Android needs a foreground service, a later checkpoint).
class KeepAwake {
  static const _esContinuous = 0x80000000;
  static const _esSystemRequired = 0x00000001;
  static const _esAwaymodeRequired = 0x00000040;

  static int Function(int)? _setThreadExecutionState;

  static int Function(int)? _load() {
    if (!Platform.isWindows) return null;
    return _setThreadExecutionState ??= DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Uint32 Function(Uint32), int Function(int)>('SetThreadExecutionState');
  }

  /// True if the operating system accepted the request.
  static bool get supported => Platform.isWindows;

  static bool enable() {
    final call = _load();
    if (call == null) return false;
    return call(_esContinuous | _esSystemRequired | _esAwaymodeRequired) != 0;
  }

  static void disable() {
    _load()?.call(_esContinuous);
  }
}
