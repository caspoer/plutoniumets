/// Conservative TX-gain limits provided for the current PlutoSDR policy.
const double sdrTxGainMinimumDb = -89.75;
const double sdrTxGainMaximumDb = -5.0;

/// Hardware-facing boundary backed by libiio.
abstract interface class LibiioTransport {
  Future<void> connect();
  Future<void> close();

  Future<int> readLong(String channel, bool output, String attribute);
  Future<void> writeLong(
      String channel, bool output, String attribute, int value);
  Future<double> readDouble(String channel, bool output, String attribute);
  Future<void> writeDouble(
      String channel, bool output, String attribute, double value);
  Future<String> readString(String channel, bool output, String attribute);
  Future<void> writeString(
      String channel, bool output, String attribute, String value);
}
