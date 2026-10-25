import 'dart:ffi';
import 'dart:io' show Platform;

/// Loads the installed native libiio shared library. The operating system
/// package for libiio must be installed separately.
DynamicLibrary openLibiio() {
  if (Platform.isWindows) return DynamicLibrary.open('libiio.dll');
  if (Platform.isMacOS) return DynamicLibrary.open('libiio.1.dylib');
  if (Platform.isAndroid) return DynamicLibrary.open('libiio.so');
  return DynamicLibrary.open('libiio.so.1');
}
