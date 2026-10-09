import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The outcome of asking the phone for one of its e-mail accounts.
sealed class EmailPick {
  const EmailPick();
}

/// The user chose this address.
class EmailPicked extends EmailPick {
  const EmailPicked(this.email);
  final String email;
}

/// The user closed the list without choosing.
class EmailPickCancelled extends EmailPick {
  const EmailPickCancelled();
}

/// No chooser on this device (not Android, or the system refused); the user
/// types the address instead.
class EmailPickUnavailable extends EmailPick {
  const EmailPickUnavailable();
}

/// Opens Android's account chooser (MainActivity, channel
/// `eshary/account_picker`): it lists the e-mail accounts signed in on the
/// phone and returns the one the user taps.
class DeviceEmailPicker {
  const DeviceEmailPicker([this._channel = const MethodChannel(_name)]);

  static const _name = 'eshary/account_picker';
  final MethodChannel _channel;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<EmailPick> pick() async {
    if (!isSupported) return const EmailPickUnavailable();
    try {
      final email = await _channel.invokeMethod<String>('pickEmail');
      if (email == null) return const EmailPickCancelled();
      final clean = email.trim().toLowerCase();
      // An account that is not an e-mail address is of no use here.
      if (!_emailRegex.hasMatch(clean)) return const EmailPickUnavailable();
      return EmailPicked(clean);
    } on PlatformException {
      return const EmailPickUnavailable();
    } on MissingPluginException {
      return const EmailPickUnavailable();
    }
  }
}

final deviceEmailPickerProvider =
    Provider<DeviceEmailPicker>((ref) => const DeviceEmailPicker());
