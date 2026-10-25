import 'dart:convert';

class SavedFrequency {
  const SavedFrequency({required this.name, required this.frequencyHz});

  final String name;
  final int frequencyHz;

  double get frequencyMHz => frequencyHz / 1000000;

  String encode() => jsonEncode({
        'name': name,
        'frequencyHz': frequencyHz,
      });

  static SavedFrequency? decode(String value) {
    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      final name = map['name'] as String?;
      final frequencyHz = map['frequencyHz'] as int?;
      if (name == null || name.trim().isEmpty || frequencyHz == null) {
        return null;
      }
      return SavedFrequency(name: name, frequencyHz: frequencyHz);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
