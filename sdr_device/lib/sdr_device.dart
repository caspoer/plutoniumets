import 'src/libiio_transport.dart';
export 'src/libiio_ffi_transport.dart';

enum SdrDirection { rx, tx }

class SdrFrequencyRangeHz {
  const SdrFrequencyRangeHz({required this.minimum, required this.maximum});
  final int minimum;
  final int maximum;
}

class SdrChannel {
  const SdrChannel(this.id, {required this.output});
  final String id;
  final bool output;
}

/// Channel IDs confirmed on the connected PlutoSDR Rev.C / AD9361.
class SdrChannelMap {
  const SdrChannelMap({
    required this.rxLo,
    required this.rxControl,
    required this.txLo,
    required this.txControl,
  });

  const SdrChannelMap.plutoRevC()
      : rxLo = const SdrChannel('altvoltage0', output: true),
        rxControl = const SdrChannel('voltage0', output: false),
        txLo = const SdrChannel('altvoltage1', output: true),
        txControl = const SdrChannel('voltage0', output: true);

  final SdrChannel rxLo;
  final SdrChannel rxControl;
  final SdrChannel txLo;
  final SdrChannel txControl;

  SdrChannel lo(SdrDirection direction) =>
      direction == SdrDirection.rx ? rxLo : txLo;
  SdrChannel control(SdrDirection direction) =>
      direction == SdrDirection.rx ? rxControl : txControl;
}

/// PlutoSDR controls over libiio.
///
/// TX cannot be activated through this API. TX settings can be prepared only
/// while the device confirms TX_LO is powered down.
class SdrDevice {
  SdrDevice(this._iio, {this.channels = const SdrChannelMap.plutoRevC()});

  final LibiioTransport _iio;
  final SdrChannelMap channels;

  bool _connected = false;
  bool get isConnected => _connected;
  bool get txEnabled => false;

  /// User-confirmed TX power figures. These are metadata only.
  static const double maxTxPowerDbm = 20.0;
  static const double defaultTxPowerLimitDbm = 2.0;
  static const double minTxGainDb = sdrTxGainMinimumDb;
  static const double maxTxGainDb = sdrTxGainMaximumDb;

  /// TX_LO minimum reported by the attached PlutoSDR, in Hz.
  static const int observedTxFrequencyMinimumHz = 46875000;

  Future<void> connect() async {
    await _iio.connect();
    try {
      // Fail closed: attempt to power down TX_LO and require readback before
      // exposing the device as connected to callers.
      await _iio.writeLong('altvoltage1', true, 'powerdown', 1);
      final powerdown = await _iio.readLong('altvoltage1', true, 'powerdown');
      if (powerdown != 1) {
        throw StateError('TX_LO did not confirm powerdown=1 (read $powerdown).');
      }
      _connected = true;
    } catch (_) {
      await _iio.close();
      rethrow;
    }
  }

  Future<void> close() async {
    if (!_connected) return;
    await _iio.close();
    _connected = false;
  }

  Future<void> _requireConnected() async {
    if (!_connected) throw StateError('SdrDevice is not connected.');
  }

  Future<void> _requireTxPoweredDown() async {
    final powerdown =
        await _iio.readLong('altvoltage1', true, 'powerdown');
    if (powerdown != 1) {
      throw StateError(
          'TX_LO is not confirmed in powerdown; TX settings were not changed.');
    }
  }

  void _requireInitialWrite(SdrDirection direction, String setting) {
    if (direction == SdrDirection.tx) {
      throw StateError('TX activation and unguarded TX writes are disabled.');
    }
    if (setting != 'frequency' && setting != 'hardwaregain') {
      throw StateError(
          'Initial bring-up only permits RX frequency and gain writes.');
    }
  }

  Future<int> readFrequencyHz(SdrDirection direction) async {
    await _requireConnected();
    final channel = channels.lo(direction);
    return _iio.readLong(channel.id, channel.output, 'frequency');
  }

  /// Reads the device-advertised frequency limits without changing the LO.
  Future<SdrFrequencyRangeHz> readFrequencyRangeHz(
      SdrDirection direction) async {
    await _requireConnected();
    final channel = channels.lo(direction);
    final raw = await _iio.readString(
        channel.id, channel.output, 'frequency_available');
    final values = RegExp(r'-?\d+(?:\.\d+)?(?:e[+-]?\d+)?',
            caseSensitive: false)
        .allMatches(raw)
        .map((match) => double.parse(match.group(0)!))
        .toList();
    if (values.length < 2) {
      throw FormatException('Unrecognized frequency_available value: $raw');
    }
    return SdrFrequencyRangeHz(
      minimum: values.first.round(),
      maximum: values.last.round(),
    );
  }

  /// Reads the AD9361 instantaneous RSSI attribute for RX channel 0.
  Future<double> readRxRssiDb() async {
    await _requireConnected();
    final channel = channels.rxControl;
    final raw = await _iio.readString(channel.id, channel.output, 'rssi');
    final match = RegExp(r'-?\d+(?:\.\d+)?(?:e[+-]?\d+)?',
            caseSensitive: false)
        .firstMatch(raw);
    if (match == null) throw FormatException('Unrecognized RX RSSI value: $raw');
    return double.parse(match.group(0)!);
  }

  Future<void> setFrequencyHz(SdrDirection direction, int hz) async {
    await _requireConnected();
    if (hz <= 0) throw ArgumentError.value(hz, 'hz', 'Must be positive.');
    if (direction == SdrDirection.rx) {
      _requireInitialWrite(direction, 'frequency');
    } else {
      await _requireTxPoweredDown();
      final range = await readFrequencyRangeHz(SdrDirection.tx);
      if (hz < range.minimum || hz > range.maximum) {
        throw RangeError.range(hz, range.minimum, range.maximum, 'hz');
      }
    }
    final channel = channels.lo(direction);
    await _iio.writeLong(channel.id, channel.output, 'frequency', hz);
    if (direction == SdrDirection.tx) await _requireTxPoweredDown();
  }

  Future<double> readGainDb(SdrDirection direction) async {
    await _requireConnected();
    final channel = channels.control(direction);
    return _iio.readDouble(channel.id, channel.output, 'hardwaregain');
  }

  Future<String> readRxGainControlMode() async {
    await _requireConnected();
    final channel = channels.rxControl;
    return _iio.readString(
        channel.id, channel.output, 'gain_control_mode');
  }

  Future<void> setGainDb(SdrDirection direction, double db) async {
    await _requireConnected();
    if (direction == SdrDirection.rx) {
      _requireInitialWrite(direction, 'hardwaregain');
      final rx = channels.rxControl;
      await _iio.writeString(
          rx.id, rx.output, 'gain_control_mode', 'manual');
    } else {
      if (db < minTxGainDb || db > maxTxGainDb) {
        throw RangeError.range(db, minTxGainDb, maxTxGainDb, 'db');
      }
      await _requireTxPoweredDown();
    }
    final channel = channels.control(direction);
    await _iio.writeDouble(channel.id, channel.output, 'hardwaregain', db);
    if (direction == SdrDirection.tx) await _requireTxPoweredDown();
  }

  Future<int> readSampleRateHz(SdrDirection direction) async {
    await _requireConnected();
    final channel = channels.control(direction);
    return _iio.readLong(channel.id, channel.output, 'sampling_frequency');
  }

  Future<void> setSampleRateHz(SdrDirection direction, int hz) async {
    await _requireConnected();
    if (hz <= 0) throw ArgumentError.value(hz, 'hz', 'Must be positive.');
    // The AD9361 sample rate is shared by RX and TX paths. Keep TX_LO down
    // while changing both channel views of the shared setting.
    await _requireTxPoweredDown();
    final selected = channels.control(direction);
    final other = direction == SdrDirection.rx
        ? channels.txControl
        : channels.rxControl;
    await _iio.writeLong(
        selected.id, selected.output, 'sampling_frequency', hz);
    await _iio.writeLong(other.id, other.output, 'sampling_frequency', hz);
    await _requireTxPoweredDown();
  }

  Future<int> readBandwidthHz(SdrDirection direction) async {
    await _requireConnected();
    final channel = channels.control(direction);
    return _iio.readLong(channel.id, channel.output, 'rf_bandwidth');
  }

  Future<void> setBandwidthHz(SdrDirection direction, int hz) async {
    await _requireConnected();
    if (hz <= 0) throw ArgumentError.value(hz, 'hz', 'Must be positive.');
    final channel = channels.control(direction);
    if (direction == SdrDirection.tx) await _requireTxPoweredDown();
    await _iio.writeLong(channel.id, channel.output, 'rf_bandwidth', hz);
    if (direction == SdrDirection.tx) await _requireTxPoweredDown();
  }

  Future<String> readPort(SdrDirection direction) async {
    await _requireConnected();
    final channel = channels.control(direction);
    return _iio.readString(channel.id, channel.output, 'rf_port_select');
  }

  Future<void> setPort(SdrDirection direction, String port) async {
    await _requireConnected();
    if (port.trim().isEmpty) throw ArgumentError.value(port, 'port');
    final channel = channels.control(direction);
    if (direction == SdrDirection.tx) await _requireTxPoweredDown();
    await _iio.writeString(channel.id, channel.output, 'rf_port_select', port);
    if (direction == SdrDirection.tx) await _requireTxPoweredDown();
  }
}
