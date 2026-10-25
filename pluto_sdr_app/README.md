# PlutoSDR Android app source

Flutter app source for Android. The first screen connects to the Pluto by IP,
confirms TX_LO powerdown on connect, reads RX frequency/gain/RSSI and the
advertised RX/TX frequency ranges, and offers free RX frequency entry in MHz,
a slider, RX gain, and a stepped RX frequency scan with an RSSI graph. It also
exposes shared sample rate, RX/TX bandwidth and port, plus TX frequency/gain
setup. TX settings can only be changed while TX_LO powerdown is confirmed; the
app has no TX-on control. A true spectrum/waterfall view still needs IQ buffer
streaming and FFT processing.

The screen also has named RX frequency favorites that persist on the phone,
three quick sweep widths centered around the current frequency, and CSV export
of sweep frequency/RSSI rows to the clipboard. The CSV can be pasted into a
spreadsheet or analysis tool. The sweep is RSSI-based and is not a spectrum.

Initial phone target: Samsung Galaxy S8 with Exynos, packaged for the 64-bit
ARM Android ABI (`arm64-v8a`).

## Phone connection

Chosen phone connection: direct USB-C OTG from the Galaxy S8 to PlutoSDR. The
current screen code is still an IP prototype; USB support is not implemented
yet. Android must enumerate the Pluto, request the user's USB permission, open
the device, and pass its file descriptor to native libusb. The native libiio
USB backend then needs to use that descriptor. See [Android USB host
permissions](https://developer.android.com/develop/connectivity/usb/host) and
[libusb on Android](https://github.com/libusb/libusb/wiki/Android). RX range
is queried from IIO at runtime; on the connected unit it was 70 MHz–6 GHz.

## Where to make changes

- `lib/main.dart` starts the app and chooses its theme.
- `lib/screens/pluto_home_page.dart` contains the screen and its button actions.
- `lib/models/scan_point.dart` is the data for one point in an RX sweep.
- `lib/models/saved_frequency.dart` stores a named RX frequency favorite.
- `lib/widgets/rssi_chart.dart` draws the sweep graph.
- `../sdr_device/lib/sdr_device.dart` contains radio operations and safety
  checks; `lib/src/libiio_ffi_transport.dart` is the small native bridge.

The app uses ordinary Flutter widgets and direct methods; it does not depend on
a state-management framework. A new control can follow the existing pattern:
read its value, add a field/button, and call one `SdrDevice` method.

## Signal recordings

The planned recorder will capture received complex IQ samples, not just audio,
so they can be examined later. Store the data and its frequency, sample rate,
gain, and capture time as a portable SigMF recording (`.sigmf-data` plus
`.sigmf-meta`). SigMF describes IQ samples in a binary dataset with a separate
JSON metadata file ([SigMF specification](https://sigmf.org/)).

At the current 30.72 MS/s setting, raw 16-bit I/Q data is about 123 MB/s, or
7.4 GB per minute. The app should therefore let the user choose duration and
show an estimated file size before recording. IQ buffer streaming and saving
are not implemented yet.

## Analysis in the app

Add a simple **Analyse** screen that uses the same analyzer for live RX data
and saved SigMF recordings. The first useful tools are:

- live spectrum and waterfall views from IQ samples;
- peak frequency and signal level;
- bandwidth estimate and movable frequency markers;
- reopening an earlier recording and comparing it with another capture.

The stepped RSSI graph is only a coarse signal-strength scan, not a spectrum
analyzer. Spectrum and recording depend on RX IQ buffer streaming, which is
the next native libiio layer. Modulation decoding can be added later without
changing the recording format or basic screen layout.

## APK build status

The Android project files have been generated and an arm64 release APK builds
with:

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The
current 17.4 MB APK is a debug-signed preview that can open the UI. It cannot
connect to the Pluto yet: an Android `arm64-v8a` `libiio.so` is not bundled,
and direct USB-C OTG support is not implemented. The current transport remains
IP/libiio. The phone must also authorize USB debugging before ADB can install
the APK directly.

The next hardware step is to package Android libiio/libusb and implement the
Android USB permission/file-descriptor bridge. IQ streaming, SigMF recording,
and spectrum analysis still depend on that native transport.
