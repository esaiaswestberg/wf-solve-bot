class DictionaryMetadata {
  final String title;
  final String language;
  final String dictionaryName;
  final String dictPath;
  final String csvPath;

  DictionaryMetadata({
    required this.title,
    required this.language,
    required this.dictionaryName,
    required this.dictPath,
    required this.csvPath,
  });

  String get id => dictPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DictionaryMetadata &&
          title == other.title &&
          dictionaryName == other.dictionaryName;

  @override
  int get hashCode => title.hashCode ^ dictionaryName.hashCode;
}
