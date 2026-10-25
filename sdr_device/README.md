# SdrDevice skeleton

Minimal Dart package scaffold for controlling an IIO SDR through libiio FFI.

## Bring-up boundary

- The confirmed maximum TX power is 20 dBm (`SdrDevice.maxTxPowerDbm`). The default TX power limit is 2 dBm (`SdrDevice.defaultTxPowerLimitDbm`). These are metadata only.
- On connect, the driver writes `TX_LO.powerdown = 1` and reads it back. The
  connection is considered ready only if the device confirms `1`.
- TX transmission cannot be activated through this API. TX frequency, gain,
  bandwidth, and port may be configured only while `powerdown` reads back as
  `1`; the state is checked around TX changes. TX gain is limited to -89.75 to
  -5 dB by the current policy. The FFI layer rejects every TX powerdown value
  except `1`.
- Initial checks can read attributes and write RX frequency and gain. Use
  `readFrequencyRangeHz(SdrDirection.tx)` to re-read the TX_LO-advertised range;
  it reads `frequency_available` and does not change the LO.
- Sample-rate, bandwidth, and port controls are available for RX/TX. The AD9361
  sample rate is shared and is written to both RX and TX channel views while
  TX_LO is confirmed down.
- RX gain is switched to manual mode before a requested RX gain change, because
  the connected device initially reported `slow_attack` automatic gain mode.
- Read-only libiio inspection of the connected radio identified PlutoSDR Rev.C
  (Z7010-AD9361), serial `104473023196000bf5ff1a00aae12c3ca8`, firmware `v0.38`.
  The bundled firmware files were labeled `v0.39`; the connected radio reports
  `v0.38`.
- The radio reports TX_LO `frequency_available` from 46,875,000 Hz to
  6,000,000,000 Hz. This lower TX frequency bound is **46.875 MHz**, not zero.
  RX_LO reports 70,000,000 Hz to 6,000,000,000 Hz.
- `iio_info --uri ip:192.168.2.1 --read-debug-attr` read these attributes over
  Ethernet. No attributes were written and no TX enable operation was issued.
- `LibiioFfiTransport` calls libiio 1.x directly. Example: create it with
  `uri: 'ip:192.168.2.1'`, then pass it to `SdrDevice`.
- The native library loader is in `lib/src/libiio_library.dart`; the host must
  install libiio. This package does not bundle the native library.

## Observed TX lower frequency limit

The connected unit's `ad9361-phy` `TX_LO` channel reported
`frequency_available` with a minimum of 46,875,000 Hz and maximum of
6,000,000,000 Hz. This is a frequency range, distinct from the TX power
metadata above. TX output activation remains unavailable; configuration while
the LO is powered down is supported.




