import 'package:flutter/material.dart';

import 'screens/pluto_home_page.dart';

void main() {
  runApp(const PlutoSdrApp());
}

class PlutoSdrApp extends StatelessWidget {
  const PlutoSdrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlutoSDR',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const PlutoHomePage(),
    );
  }
}
