import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'libiio_library.dart';
import 'libiio_transport.dart';

final class _IioContext extends Opaque {}
final class _IioDevice extends Opaque {}
final class _IioChannel extends Opaque {}
final class _IioAttr extends Opaque {}

typedef _CreateContextNative = Pointer<_IioContext> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef _CreateContextDart = Pointer<_IioContext> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef _DestroyContextNative = Void Function(Pointer<_IioContext>);
typedef _DestroyContextDart = void Function(Pointer<_IioContext>);
typedef _FindDeviceNative = Pointer<_IioDevice> Function(
    Pointer<_IioContext>, Pointer<Utf8>);
typedef _FindDeviceDart = Pointer<_IioDevice> Function(
    Pointer<_IioContext>, Pointer<Utf8>);
typedef _FindChannelNative = Pointer<_IioChannel> Function(
    Pointer<_IioDevice>, Pointer<Utf8>, Bool);
typedef _FindChannelDart = Pointer<_IioChannel> Function(
    Pointer<_IioDevice>, Pointer<Utf8>, bool);
typedef _FindAttrNative = Pointer<_IioAttr> Function(
    Pointer<_IioChannel>, Pointer<Utf8>);
typedef _FindAttrDart = Pointer<_IioAttr> Function(
    Pointer<_IioChannel>, Pointer<Utf8>);
typedef _ReadLongNative = Int32 Function(Pointer<_IioAttr>, Pointer<Int64>);
typedef _ReadLongDart = int Function(Pointer<_IioAttr>, Pointer<Int64>);
typedef _WriteLongNative = Int32 Function(Pointer<_IioAttr>, Int64);
typedef _WriteLongDart = int Function(Pointer<_IioAttr>, int);
typedef _ReadDoubleNative = Int32 Function(Pointer<_IioAttr>, Pointer<Double>);
typedef _ReadDoubleDart = int Function(Pointer<_IioAttr>, Pointer<Double>);
typedef _WriteDoubleNative = Int32 Function(Pointer<_IioAttr>, Double);
typedef _WriteDoubleDart = int Function(Pointer<_IioAttr>, double);
typedef _ReadRawNative = IntPtr Function(
    Pointer<_IioAttr>, Pointer<Uint8>, IntPtr);
typedef _ReadRawDart = int Function(
    Pointer<_IioAttr>, Pointer<Uint8>, int);
typedef _WriteStringNative = IntPtr Function(
    Pointer<_IioAttr>, Pointer<Utf8>);
typedef _WriteStringDart = int Function(Pointer<_IioAttr>, Pointer<Utf8>);

/// Minimal direct FFI transport for libiio 1.x.
///
/// It connects to one URI, finds one IIO device, and accesses channel
/// attributes. TX safety policy is enforced by [SdrDevice], above this layer.
class LibiioFfiTransport implements LibiioTransport {
  LibiioFfiTransport({required this.uri, this.deviceName = 'ad9361-phy'})
      : _lib = openLibiio() {
    _createContext = _lib.lookupFunction<_CreateContextNative,
        _CreateContextDart>('iio_create_context');
    _destroyContext = _lib.lookupFunction<_DestroyContextNative,
        _DestroyContextDart>('iio_context_destroy');
    _findDevice = _lib.lookupFunction<_FindDeviceNative, _FindDeviceDart>(
        'iio_context_find_device');
    _findChannel = _lib.lookupFunction<_FindChannelNative, _FindChannelDart>(
        'iio_device_find_channel');
    _findAttr = _lib.lookupFunction<_FindAttrNative, _FindAttrDart>(
        'iio_channel_find_attr');
    _readLong = _lib.lookupFunction<_ReadLongNative, _ReadLongDart>(
        'iio_attr_read_longlong');
    _writeLong = _lib.lookupFunction<_WriteLongNative, _WriteLongDart>(
        'iio_attr_write_longlong');
    _readDouble = _lib.lookupFunction<_ReadDoubleNative, _ReadDoubleDart>(
        'iio_attr_read_double');
    _writeDouble = _lib.lookupFunction<_WriteDoubleNative, _WriteDoubleDart>(
        'iio_attr_write_double');
    _readRaw = _lib.lookupFunction<_ReadRawNative, _ReadRawDart>(
        'iio_attr_read_raw');
    _writeString = _lib.lookupFunction<_WriteStringNative, _WriteStringDart>(
        'iio_attr_write_string');
  }

  final String uri;
  final String deviceName;
  final DynamicLibrary _lib;

  late final _CreateContextDart _createContext;
  late final _DestroyContextDart _destroyContext;
  late final _FindDeviceDart _findDevice;
  late final _FindChannelDart _findChannel;
  late final _FindAttrDart _findAttr;
  late final _ReadLongDart _readLong;
  late final _WriteLongDart _writeLong;
  late final _ReadDoubleDart _readDouble;
  late final _WriteDoubleDart _writeDouble;
  late final _ReadRawDart _readRaw;
  late final _WriteStringDart _writeString;

  Pointer<_IioContext>? _context;
  Pointer<_IioDevice>? _device;

  @override
  Future<void> connect() async {
    if (_context != null) return;
    final uriPtr = uri.toNativeUtf8();
    try {
      final context = _createContext(nullptr, uriPtr);
      if (context == nullptr) {
        throw StateError('Could not create libiio context for $uri.');
      }
      final namePtr = deviceName.toNativeUtf8();
      try {
        final device = _findDevice(context, namePtr);
        if (device == nullptr) {
          _destroyContext(context);
          throw StateError('IIO device "$deviceName" was not found at $uri.');
        }
        _context = context;
        _device = device;
      } finally {
        malloc.free(namePtr);
      }
    } finally {
      malloc.free(uriPtr);
    }
  }

  @override
  Future<void> close() async {
    final context = _context;
    if (context == null) return;
    _device = null;
    _context = null;
    _destroyContext(context);
  }

  Pointer<_IioAttr> _attribute(String channelName, bool output, String name) {
    final device = _device;
    if (device == null) throw StateError('Libiio transport is not connected.');
    final channelPtr = channelName.toNativeUtf8();
    final attrPtr = name.toNativeUtf8();
    try {
      final channel = _findChannel(device, channelPtr, output);
      if (channel == nullptr) {
        throw StateError(
            'IIO channel "$channelName" (${output ? 'output' : 'input'}) not found.');
      }
      final attr = _findAttr(channel, attrPtr);
      if (attr == nullptr) {
        throw StateError('IIO attribute "$name" not found on "$channelName".');
      }
      return attr;
    } finally {
      malloc.free(channelPtr);
      malloc.free(attrPtr);
    }
  }

  Future<void> _requireTxPoweredDown() async {
    final attr = _attribute('altvoltage1', true, 'powerdown');
    final value = calloc<Int64>();
    try {
      final result = _readLong(attr, value);
      if (result < 0 || value.value != 1) {
        throw StateError(
            'TX_LO powerdown is not confirmed; TX write was rejected.');
      }
    } finally {
      calloc.free(value);
    }
  }

  @override
  Future<int> readLong(String channel, bool output, String attribute) async {
    final attr = _attribute(channel, output, attribute);
    final value = calloc<Int64>();
    try {
      final result = _readLong(attr, value);
      if (result < 0) {
        throw StateError('libiio read "$attribute" failed ($result).');
      }
      return value.value;
    } finally {
      calloc.free(value);
    }
  }

  @override
  Future<void> writeLong(
      String channel, bool output, String attribute, int value) async {
    final rxFrequencyWrite =
        channel == 'altvoltage0' && output && attribute == 'frequency';
    final txFrequencyWrite =
        channel == 'altvoltage1' && output && attribute == 'frequency';
    final txPowerdownWrite = channel == 'altvoltage1' &&
        output &&
        attribute == 'powerdown' &&
        value == 1;
    final sampleRateWrite =
        channel == 'voltage0' && attribute == 'sampling_frequency';
    final bandwidthWrite =
        channel == 'voltage0' && attribute == 'rf_bandwidth';
    if (!rxFrequencyWrite &&
        !txFrequencyWrite &&
        !txPowerdownWrite &&
        !sampleRateWrite &&
        !bandwidthWrite) {
      throw StateError(
          'IIO write is not included in the SDR control policy.');
    }
    if (txFrequencyWrite || sampleRateWrite || (bandwidthWrite && output)) {
      await _requireTxPoweredDown();
    }
    final attr = _attribute(channel, output, attribute);
    final result = _writeLong(attr, value);
    if (result < 0) {
      throw StateError('libiio write "$attribute" failed ($result).');
    }
    if (txFrequencyWrite || sampleRateWrite || (bandwidthWrite && output)) {
      await _requireTxPoweredDown();
    }
  }

  @override
  Future<double> readDouble(
      String channel, bool output, String attribute) async {
    final attr = _attribute(channel, output, attribute);
    final value = calloc<Double>();
    try {
      final result = _readDouble(attr, value);
      if (result < 0) {
        throw StateError('libiio read "$attribute" failed ($result).');
      }
      return value.value;
    } finally {
      calloc.free(value);
    }
  }

  @override
  Future<void> writeDouble(
      String channel, bool output, String attribute, double value) async {
    final rxGainWrite =
        channel == 'voltage0' && !output && attribute == 'hardwaregain';
    final txGainWrite =
        channel == 'voltage0' && output && attribute == 'hardwaregain';
    if (!rxGainWrite && !txGainWrite) {
      throw StateError(
          'FFI policy only allows RX gain and TX gain while powered down.');
    }
    if (txGainWrite) {
      if (value < sdrTxGainMinimumDb || value > sdrTxGainMaximumDb) {
        throw RangeError.value(
            value, 'value',
            'TX gain must be between $sdrTxGainMinimumDb and '
                '$sdrTxGainMaximumDb dB.');
      }
      await _requireTxPoweredDown();
    }
    final attr = _attribute(channel, output, attribute);
    final result = _writeDouble(attr, value);
    if (result < 0) {
      throw StateError('libiio write "$attribute" failed ($result).');
    }
    if (txGainWrite) await _requireTxPoweredDown();
  }

  @override
  Future<String> readString(
      String channel, bool output, String attribute) async {
    final attr = _attribute(channel, output, attribute);
    final buffer = calloc<Uint8>(4096);
    try {
      final result = _readRaw(attr, buffer, 4095);
      if (result < 0) {
        throw StateError('libiio read "$attribute" failed ($result).');
      }
      return String.fromCharCodes(buffer.asTypedList(result))
          .trim()
          .replaceAll('\u0000', '');
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  Future<void> writeString(
      String channel, bool output, String attribute, String value) async {
    final rxGainModeWrite = channel == 'voltage0' &&
        !output &&
        attribute == 'gain_control_mode' &&
        const {'manual', 'fast_attack', 'slow_attack', 'hybrid'}.contains(value);
    final rxPortWrite = channel == 'voltage0' &&
        !output &&
        attribute == 'rf_port_select' &&
        const {
          'A_BALANCED', 'B_BALANCED', 'C_BALANCED', 'A_N', 'A_P', 'B_N', 'B_P',
          'C_N', 'C_P', 'TX_MONITOR1', 'TX_MONITOR2', 'TX_MONITOR1_2'
        }.contains(value);
    final txPortWrite = channel == 'voltage0' &&
        output &&
        attribute == 'rf_port_select' &&
        const {'A', 'B'}.contains(value);
    if (!rxGainModeWrite && !rxPortWrite && !txPortWrite) {
      throw StateError('IIO string write is not included in the SDR policy.');
    }
    if (txPortWrite) await _requireTxPoweredDown();
    final attr = _attribute(channel, output, attribute);
    final valuePtr = value.toNativeUtf8();
    try {
      final result = _writeString(attr, valuePtr);
      if (result < 0) {
        throw StateError('libiio write "$attribute" failed ($result).');
      }
    } finally {
      malloc.free(valuePtr);
    }
    if (txPortWrite) await _requireTxPoweredDown();
  }
}
