import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdr_device/sdr_device.dart';

import '../models/saved_frequency.dart';
import '../models/scan_point.dart';
import '../widgets/rssi_chart.dart';

class PlutoHomePage extends StatefulWidget {
  const PlutoHomePage({super.key});

  @override
  State<PlutoHomePage> createState() => _PlutoHomePageState();
}

class _PlutoHomePageState extends State<PlutoHomePage> {
  static const _favoritesKey = 'rx_frequency_favorites';

  final _hostController = TextEditingController(text: '192.168.2.1');
  final _rxFrequencyController = TextEditingController();
  final _rxGainController = TextEditingController();
  final _txFrequencyController = TextEditingController();
  final _txGainController = TextEditingController();
  final _sampleRateController = TextEditingController();
  final _rxBandwidthController = TextEditingController();
  final _txBandwidthController = TextEditingController();
  final _scanStartController = TextEditingController();
  final _scanStopController = TextEditingController();
  final _scanStepController = TextEditingController(text: '1');
  final _preferences = SharedPreferencesAsync();

  SdrDevice? _device;
  String _status = 'Ikke tilkoblet';
  String _txFrequencyRange = '—';
  SdrFrequencyRangeHz? _rxFrequencyRange;
  double? _rxRssiDb;
  String _rxPort = 'A_BALANCED';
  String _txPort = 'A';
  List<ScanPoint> _scanPoints = [];
  List<SavedFrequency> _favorites = [];
  bool _scanning = false;
  bool _cancelScan = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final saved = await _preferences.getStringList(_favoritesKey) ?? [];
      final favorites = saved
          .map(SavedFrequency.decode)
          .whereType<SavedFrequency>()
          .toList();
      if (mounted) setState(() => _favorites = favorites);
    } catch (error) {
      if (mounted) _showError('Favorittene kunne ikke leses: $error');
    }
  }

  Future<void> _storeFavorites() async {
    await _preferences.setStringList(
      _favoritesKey,
      _favorites.map((favorite) => favorite.encode()).toList(),
    );
  }

  Future<void> _addFavorite() async {
    final mhz = double.tryParse(_rxFrequencyController.text.trim());
    if (mhz == null || mhz <= 0) {
      _showError('Skriv inn en RX-frekvens før du lagrer den.');
      return;
    }
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lagre RX-frekvens'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Navn',
            hintText: '${mhz.toStringAsFixed(6)} MHz',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    nameController.dispose();
    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) return;

    final hz = (mhz * 1000000).round();
    final range = _rxFrequencyRange;
    if (range != null && (hz < range.minimum || hz > range.maximum)) {
      _showError('Frekvensen er utenfor radioens annonserte RX-område.');
      return;
    }
    if (_favorites.any((favorite) => favorite.frequencyHz == hz)) {
      _showError('Denne frekvensen ligger allerede i favorittene.');
      return;
    }
    setState(() => _favorites = [
          ..._favorites,
          SavedFrequency(name: trimmedName, frequencyHz: hz),
        ]);
    try {
      await _storeFavorites();
    } catch (error) {
      _showError('Favoritten kunne ikke lagres: $error');
    }
  }

  Future<void> _tuneFavorite(SavedFrequency favorite) async {
    final range = _rxFrequencyRange;
    if (range != null &&
        (favorite.frequencyHz < range.minimum ||
            favorite.frequencyHz > range.maximum)) {
      _showError('Favoritten ligger utenfor radioens RX-område.');
      return;
    }
    await _run(() async {
      await _device!.setFrequencyHz(SdrDirection.rx, favorite.frequencyHz);
      await _readValues();
    });
  }

  Future<void> _removeFavorite(SavedFrequency favorite) async {
    setState(() => _favorites = _favorites
        .where((item) => item.frequencyHz != favorite.frequencyHz)
        .toList());
    try {
      await _storeFavorites();
    } catch (error) {
      _showError('Favoritten kunne ikke fjernes: $error');
    }
  }

  void _applyScanPreset(double spanMHz, double stepMHz) {
    final range = _rxFrequencyRange;
    if (range == null) return;
    final minimumMHz = range.minimum / 1000000;
    final maximumMHz = range.maximum / 1000000;
    final currentMHz = double.tryParse(_rxFrequencyController.text.trim()) ??
        (minimumMHz + maximumMHz) / 2;
    final startMHz = (currentMHz - spanMHz).clamp(minimumMHz, maximumMHz);
    final stopMHz = (currentMHz + spanMHz).clamp(minimumMHz, maximumMHz);
    setState(() {
      _scanStartController.text = startMHz.toStringAsFixed(3);
      _scanStopController.text = stopMHz.toStringAsFixed(3);
      _scanStepController.text = stepMHz.toStringAsFixed(3);
    });
  }

  Future<void> _copyScanCsv() async {
    if (_scanPoints.isEmpty) return;
    final csv = StringBuffer('frequency_mhz,rssi_db\n');
    for (final point in _scanPoints) {
      csv.writeln(
          '${point.frequencyMHz.toStringAsFixed(6)},${point.rssiDb.toStringAsFixed(2)}');
    }
    await Clipboard.setData(ClipboardData(text: csv.toString()));
    if (mounted) {
      _showMessage('Sveipresultatet er kopiert som CSV.');
    }
  }

  Future<void> _connect() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      _showError('Skriv inn PlutoSDR-adressen.');
      return;
    }
    await _run(() async {
      await _device?.close();
      final device = SdrDevice(
        LibiioFfiTransport(uri: 'ip:$host'),
      );
      _device = device;
      await device.connect(); // Sets TX_LO powerdown=1 and confirms readback.
      if (!mounted) return;
      setState(() => _status = 'Tilkoblet · TX-LO powerdown bekreftet');
      await _readValues();
    });
  }

  Future<void> _disconnect() async {
    await _run(() async {
      await _device?.close();
      _device = null;
      if (mounted) {
        setState(() {
          _status = 'Ikke tilkoblet';
          _txFrequencyRange = '—';
          _rxFrequencyRange = null;
          _rxRssiDb = null;
          _scanPoints = [];
        });
      }
    });
  }

  Future<void> _readValues() async {
    final device = _device;
    if (device == null) return;
    final rxFrequency = await device.readFrequencyHz(SdrDirection.rx);
    final rxGain = await device.readGainDb(SdrDirection.rx);
    final rxRange = await device.readFrequencyRangeHz(SdrDirection.rx);
    final rssi = await device.readRxRssiDb();
    final txRange = await device.readFrequencyRangeHz(SdrDirection.tx);
    final txFrequency = await device.readFrequencyHz(SdrDirection.tx);
    final txGain = await device.readGainDb(SdrDirection.tx);
    final sampleRate = await device.readSampleRateHz(SdrDirection.rx);
    final rxBandwidth = await device.readBandwidthHz(SdrDirection.rx);
    final txBandwidth = await device.readBandwidthHz(SdrDirection.tx);
    final rxPort = await device.readPort(SdrDirection.rx);
    final txPort = await device.readPort(SdrDirection.tx);
    if (!mounted) return;
    setState(() {
      _rxFrequencyController.text =
          (rxFrequency / 1000000).toStringAsFixed(6);
      _rxGainController.text = rxGain.toStringAsFixed(2);
      _rxFrequencyRange = rxRange;
      _rxRssiDb = rssi;
      _txFrequencyController.text =
          (txFrequency / 1000000).toStringAsFixed(6);
      _txGainController.text = txGain.toStringAsFixed(2);
      _sampleRateController.text =
          (sampleRate / 1000000).toStringAsFixed(3);
      _rxBandwidthController.text =
          (rxBandwidth / 1000000).toStringAsFixed(3);
      _txBandwidthController.text =
          (txBandwidth / 1000000).toStringAsFixed(3);
      _rxPort = rxPort;
      _txPort = txPort;
      if (_scanStartController.text.isEmpty ||
          _scanStopController.text.isEmpty) {
        final currentMHz = rxFrequency / 1000000;
        final minMHz = rxRange.minimum / 1000000;
        final maxMHz = rxRange.maximum / 1000000;
        _scanStartController.text =
            (currentMHz - 5).clamp(minMHz, maxMHz).toStringAsFixed(3);
        _scanStopController.text =
            (currentMHz + 5).clamp(minMHz, maxMHz).toStringAsFixed(3);
      }
      _txFrequencyRange = '${(txRange.minimum / 1000000).toStringAsFixed(3)}–'
          '${(txRange.maximum / 1000000).toStringAsFixed(3)} MHz';
    });
  }

  Future<void> _refresh() => _run(_readValues);

  Future<void> _setRxFrequency() async {
    final mhz = double.tryParse(_rxFrequencyController.text.trim());
    if (mhz == null || mhz <= 0) {
      _showError('RX-frekvens må være et positivt tall i MHz.');
      return;
    }
    final hz = (mhz * 1000000).round();
    final range = _rxFrequencyRange;
    if (range != null && (hz < range.minimum || hz > range.maximum)) {
      _showError('Frekvensen er utenfor radioens annonserte RX-område.');
      return;
    }
    await _run(() async {
      await _device!.setFrequencyHz(SdrDirection.rx, hz);
      await _readValues();
    });
  }

  Future<void> _setRxGain() async {
    final db = double.tryParse(_rxGainController.text.trim());
    if (db == null) {
      _showError('RX-gain må være en verdi i dB.');
      return;
    }
    await _run(() async {
      await _device!.setGainDb(SdrDirection.rx, db);
      await _readValues();
    });
  }

  Future<void> _setTxFrequency() async {
    final mhz = double.tryParse(_txFrequencyController.text.trim());
    if (mhz == null || mhz <= 0) {
      _showError('TX-frekvens må være et positivt tall i MHz.');
      return;
    }
    final hz = (mhz * 1000000).round();
    await _run(() async {
      final range = await _device!.readFrequencyRangeHz(SdrDirection.tx);
      if (hz < range.minimum || hz > range.maximum) {
        throw RangeError('TX-frekvensen er utenfor radioens annonserte område.');
      }
      await _device!.setFrequencyHz(SdrDirection.tx, hz);
      await _readValues();
    });
  }

  Future<void> _setTxGain() async {
    final db = double.tryParse(_txGainController.text.trim());
    if (db == null || db < SdrDevice.minTxGainDb || db > SdrDevice.maxTxGainDb) {
      _showError(
          'TX-gain må være ${SdrDevice.minTxGainDb} til ${SdrDevice.maxTxGainDb} dB.');
      return;
    }
    await _run(() async {
      await _device!.setGainDb(SdrDirection.tx, db);
      await _readValues();
    });
  }

  Future<void> _setSampleRate() async {
    final rateMsps = double.tryParse(_sampleRateController.text.trim());
    if (rateMsps == null || rateMsps <= 0) {
      _showError('Samplerate må være et positivt tall i MS/s.');
      return;
    }
    await _run(() async {
      await _device!.setSampleRateHz(
          SdrDirection.rx, (rateMsps * 1000000).round());
      await _readValues();
    });
  }

  Future<void> _setBandwidth(
      SdrDirection direction, TextEditingController controller) async {
    final bandwidthMHz = double.tryParse(controller.text.trim());
    if (bandwidthMHz == null || bandwidthMHz <= 0) {
      _showError('Båndbredde må være et positivt tall i MHz.');
      return;
    }
    await _run(() async {
      await _device!.setBandwidthHz(
          direction, (bandwidthMHz * 1000000).round());
      await _readValues();
    });
  }

  Future<void> _setPort(SdrDirection direction, String port) async {
    await _run(() async {
      await _device!.setPort(direction, port);
      await _readValues();
    });
  }

  Future<void> _startScan() async {
    final startMHz = double.tryParse(_scanStartController.text.trim());
    final stopMHz = double.tryParse(_scanStopController.text.trim());
    final stepMHz = double.tryParse(_scanStepController.text.trim());
    final range = _rxFrequencyRange;
    final device = _device;
    if (startMHz == null || stopMHz == null || stepMHz == null ||
        startMHz < 0 || stopMHz <= startMHz || stepMHz <= 0) {
      _showError('Kontroller start, stopp og positivt trinn for sveipet.');
      return;
    }
    if (range == null || device == null) return;
    final startHz = (startMHz * 1000000).round();
    final stopHz = (stopMHz * 1000000).round();
    final stepHz = (stepMHz * 1000000).round();
    if (startHz < range.minimum || stopHz > range.maximum || stepHz < 1) {
      _showError('Sveipet må være innenfor radioens RX-område.');
      return;
    }
    final pointCount = ((stopHz - startHz) ~/ stepHz) + 1;
    if (pointCount > 1000) {
      _showError('Sveipet kan ha maks 1000 målepunkter. Øk trinnet.');
      return;
    }

    await _run(() async {
      final originalHz = await device.readFrequencyHz(SdrDirection.rx);
      _cancelScan = false;
      if (mounted) {
        setState(() {
          _scanning = true;
          _scanPoints = [];
          _status = 'Starter RX-sveip';
        });
      }
      try {
        for (var hz = startHz; hz <= stopHz; hz += stepHz) {
          if (_cancelScan) break;
          await device.setFrequencyHz(SdrDirection.rx, hz);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final rssi = await device.readRxRssiDb();
          if (mounted) {
            setState(() {
              _scanPoints = [
                ..._scanPoints,
                ScanPoint(hz / 1000000, rssi),
              ];
              _status = 'Måler ${_scanPoints.length} av $pointCount punkter';
            });
          }
        }
      } finally {
        await device.setFrequencyHz(SdrDirection.rx, originalHz);
        if (mounted) {
          setState(() {
            _scanning = false;
            _status = _cancelScan ? 'RX-sveip stoppet' : 'RX-sveip ferdig';
          });
        }
        await _readValues();
      }
    });
  }

  void _stopScan() => _cancelScan = true;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) _showError(error.toString());
      if (_device?.isConnected != true && mounted) {
        setState(() => _status = 'Tilkobling feilet');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _hostController.dispose();
    _rxFrequencyController.dispose();
    _rxGainController.dispose();
    _txFrequencyController.dispose();
    _txGainController.dispose();
    _sampleRateController.dispose();
    _rxBandwidthController.dispose();
    _txBandwidthController.dispose();
    _scanStartController.dispose();
    _scanStopController.dispose();
    _scanStepController.dispose();
    _device?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _device?.isConnected == true;
    return Scaffold(
      appBar: AppBar(title: const Text('PlutoSDR kontroll')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_status, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'PlutoSDR IP-adresse',
              hintText: '192.168.2.1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: _busy || connected ? null : _connect,
              child: const Text('Koble til'),
            ),
            OutlinedButton(
              onPressed: _busy || !connected ? null : _disconnect,
              child: const Text('Koble fra'),
            ),
            OutlinedButton(
              onPressed: _busy || !connected ? null : _refresh,
              child: const Text('Les verdier'),
            ),
          ]),
          const Divider(height: 32),
          TextField(
            controller: _rxFrequencyController,
            enabled: connected && !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'RX-frekvens (MHz)',
              helperText: 'Skriv inn en frekvens innenfor radioens område.',
              border: OutlineInputBorder(),
            ),
          ),
          if (connected && _rxFrequencyRange != null) ...[
            Slider(
              value: (_rxFrequencyController.text.isEmpty
                      ? _rxFrequencyRange!.minimum / 1000000
                      : (double.tryParse(_rxFrequencyController.text) ??
                              _rxFrequencyRange!.minimum / 1000000))
                  .clamp(
                    _rxFrequencyRange!.minimum / 1000000,
                    _rxFrequencyRange!.maximum / 1000000,
                  )
                  .toDouble(),
              min: _rxFrequencyRange!.minimum / 1000000,
              max: _rxFrequencyRange!.maximum / 1000000,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _rxFrequencyController.text = value.toStringAsFixed(3);
                      }),
              onChangeEnd: _busy ? null : (_) => _setRxFrequency(),
            ),
            Text(
              'RX-område: ${(_rxFrequencyRange!.minimum / 1000000).toStringAsFixed(3)}–${(_rxFrequencyRange!.maximum / 1000000).toStringAsFixed(3)} MHz',
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: connected && !_busy ? _setRxFrequency : null,
              child: const Text('Sett RX-frekvens'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: connected && !_busy ? _addFavorite : null,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Lagre som favoritt'),
            ),
          ),
          if (_favorites.isNotEmpty) ...[
            Text('Favoritter', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ..._favorites.map((favorite) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(favorite.name),
                    subtitle:
                        Text('${favorite.frequencyMHz.toStringAsFixed(6)} MHz'),
                    onTap: connected && !_busy
                        ? () => _tuneFavorite(favorite)
                        : null,
                    trailing: IconButton(
                      tooltip: 'Fjern favoritt',
                      onPressed: _busy ? null : () => _removeFavorite(favorite),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                )),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _rxGainController,
            enabled: connected && !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'RX-gain (dB)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: connected && !_busy ? _setRxGain : null,
              child: const Text('Sett RX-gain'),
            ),
          ),
          const Divider(height: 32),
          Text('RX RSSI (IIO): ${_rxRssiDb?.toStringAsFixed(2) ?? '—'} dB'),
          const SizedBox(height: 8),
          Text('RX-frekvenssveip',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('Raske oppsett fra gjeldende RX-frekvens:'),
          Wrap(spacing: 8, children: [
            ActionChip(
              label: const Text('Nært · ±1 MHz'),
              onPressed: connected && !_busy
                  ? () => _applyScanPreset(1, 0.1)
                  : null,
            ),
            ActionChip(
              label: const Text('Vanlig · ±5 MHz'),
              onPressed: connected && !_busy
                  ? () => _applyScanPreset(5, 0.5)
                  : null,
            ),
            ActionChip(
              label: const Text('Bredt · ±20 MHz'),
              onPressed: connected && !_busy
                  ? () => _applyScanPreset(20, 1)
                  : null,
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _scanStartController,
                enabled: connected && !_busy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Fra (MHz)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _scanStopController,
                enabled: connected && !_busy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Til (MHz)', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _scanStepController,
                enabled: connected && !_busy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Trinn (MHz)', border: OutlineInputBorder()),
              ),
            ),
          ]),
          Wrap(spacing: 8, children: [
            FilledButton.tonal(
              onPressed: connected && !_busy ? _startScan : null,
              child: const Text('Start RX-sveip'),
            ),
            OutlinedButton(
              onPressed: _scanning ? _stopScan : null,
              child: const Text('Stopp'),
            ),
          ]),
          if (_scanPoints.isNotEmpty) ...[
            Text('${_scanPoints.length} målepunkter · RSSI fra IIO'),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _copyScanCsv,
                icon: const Icon(Icons.copy),
                label: const Text('Kopier målinger som CSV'),
              ),
            ),
            const SizedBox(
              height: 220,
              child: RssiChart(points: _scanPoints),
            ),
          ],
          const Divider(height: 32),
          Text('TX_LO frekvensområde: $_txFrequencyRange'),
          Text('TX klargjøring (TX-LO holdes av)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _txFrequencyController,
            enabled: connected && !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'TX-frekvens (MHz)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: connected && !_busy ? _setTxFrequency : null,
            child: const Text('Sett TX-frekvens mens TX-LO er av'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _txGainController,
            enabled: connected && !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'TX-gain (dB)',
              helperText:
                  'Policygrense ${SdrDevice.minTxGainDb} til ${SdrDevice.maxTxGainDb} dB',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: connected && !_busy ? _setTxGain : null,
            child: const Text('Sett TX-gain mens TX-LO er av'),
          ),
          const Divider(height: 32),
          Text('Samlet digital innstilling',
              style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _sampleRateController,
            enabled: connected && !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Samplerate (MS/s)',
              helperText: 'Gjelder RX- og TX-datakjeden.',
              border: OutlineInputBorder(),
            ),
          ),
          OutlinedButton(
            onPressed: connected && !_busy ? _setSampleRate : null,
            child: const Text('Sett samplerate'),
          ),
          Text('RX-innstillinger',
              style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _rxBandwidthController,
            enabled: connected && !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'RX-båndbredde (MHz)',
              border: OutlineInputBorder(),
            ),
          ),
          OutlinedButton(
            onPressed: connected && !_busy
                ? () => _setBandwidth(SdrDirection.rx, _rxBandwidthController)
                : null,
            child: const Text('Sett RX-båndbredde'),
          ),
          DropdownButtonFormField<String>(
            value: _rxPort,
            decoration: const InputDecoration(labelText: 'RX-port'),
            items: const [
              'A_BALANCED', 'B_BALANCED', 'C_BALANCED', 'A_N', 'A_P', 'B_N',
              'B_P', 'C_N', 'C_P', 'TX_MONITOR1', 'TX_MONITOR2',
              'TX_MONITOR1_2'
            ].map((port) => DropdownMenuItem(value: port, child: Text(port)))
                .toList(),
            onChanged: !connected || _busy
                ? null
                : (port) {
                    if (port == null) return;
                    setState(() => _rxPort = port);
                    _setPort(SdrDirection.rx, port);
                  },
          ),
          Text('TX-innstillinger (TX-LO av)',
              style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _txBandwidthController,
            enabled: connected && !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'TX-båndbredde (MHz)',
              border: OutlineInputBorder(),
            ),
          ),
          OutlinedButton(
            onPressed: connected && !_busy
                ? () => _setBandwidth(SdrDirection.tx, _txBandwidthController)
                : null,
            child: const Text('Sett TX-båndbredde mens TX-LO er av'),
          ),
          DropdownButtonFormField<String>(
            value: _txPort,
            decoration: const InputDecoration(labelText: 'TX-port'),
            items: const ['A', 'B']
                .map((port) => DropdownMenuItem(value: port, child: Text(port)))
                .toList(),
            onChanged: !connected || _busy
                ? null
                : (port) {
                    if (port == null) return;
                    setState(() => _txPort = port);
                    _setPort(SdrDirection.tx, port);
                  },
          ),
          const SizedBox(height: 8),
          const Text(
              'TX-aktivering finnes ikke i appen. TX-frekvens, gain, båndbredde og port endres bare mens TX-LO bekreftes av.'),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}


