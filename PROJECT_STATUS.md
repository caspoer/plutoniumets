# PlutoSDR app prototype

This repository contains the current Flutter UI prototype and a reusable Dart SdrDevice package for PlutoSDR configuration through libiio.

## Current state

- Flutter UI prototype and Dart device package are included.
- TX LO is required to remain powered down; the app does not provide a TX enable control.
- The current UI transport is still an IP/libiio prototype. Direct USB-C OTG support for Android is not implemented yet.
- IQ streaming, SigMF recording, and in-app signal analysis are planned, not implemented.
- No APK has been built yet.

See [pluto_sdr_app/README.md](pluto_sdr_app/README.md) and [sdr_device/README.md](sdr_device/README.md) for setup and design notes.
