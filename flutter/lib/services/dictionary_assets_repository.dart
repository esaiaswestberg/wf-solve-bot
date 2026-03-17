import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:wf_solvr/models/dictionary_metadata.dart';

class DictionaryLoadResult {
  DictionaryLoadResult({
    required this.dictionaries,
    required this.templateBytes,
  });

  final List<DictionaryMetadata> dictionaries;
  final Map<String, List<Uint8List>> templateBytes;
}

class DictionaryData {
  DictionaryData({required this.dictText, required this.csvText});

  final String dictText;
  final String csvText;
}

abstract class DictionaryAssetsRepository {
  Future<DictionaryLoadResult> load();
  Future<DictionaryData> loadDictionaryData(DictionaryMetadata dictionary);
}

class RootBundleDictionaryAssetsRepository
    implements DictionaryAssetsRepository {
  RootBundleDictionaryAssetsRepository({AssetBundle? assetBundle})
    : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;

  @override
  Future<DictionaryLoadResult> load() async {
    final templatePaths = await _buildTemplateMapDynamically();
    final manifest = await AssetManifest.loadFromAssetBundle(_assetBundle);
    final metaAssets = manifest.listAssets().where(
      (path) =>
          path.startsWith('assets/static/dictionaries/') &&
          path.endsWith('metadata.json'),
    );

    final loadedDictionaries = <DictionaryMetadata>[];
    for (final metaPath in metaAssets) {
      final jsonStr = await _assetBundle.loadString(metaPath);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final dirPath = metaPath.substring(0, metaPath.lastIndexOf('/'));

      loadedDictionaries.add(
        DictionaryMetadata(
          title: json['title'] ?? 'Unknown',
          language: json['language'] ?? 'unknown',
          dictionaryName: json['dictionary'] ?? 'Unknown',
          dictPath: '$dirPath/dictionary.txt',
          csvPath: '$dirPath/letter_values.csv',
        ),
      );
    }

    final templateBytes = <String, List<Uint8List>>{};
    for (final entry in templatePaths.entries) {
      templateBytes[entry.key] = [];
      for (final path in entry.value) {
        final data = await _assetBundle.load(path);
        templateBytes[entry.key]!.add(data.buffer.asUint8List());
      }
    }

    return DictionaryLoadResult(
      dictionaries: loadedDictionaries,
      templateBytes: templateBytes,
    );
  }

  @override
  Future<DictionaryData> loadDictionaryData(
    DictionaryMetadata dictionary,
  ) async {
    final dictText = await _assetBundle.loadString(dictionary.dictPath);
    final csvText = await _assetBundle.loadString(dictionary.csvPath);
    return DictionaryData(dictText: dictText, csvText: csvText);
  }

  Future<Map<String, List<String>>> _buildTemplateMapDynamically() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_assetBundle);
    final allAssets = manifest.listAssets();
    final templatePaths = <String, List<String>>{};

    final templateAssets = allAssets.where(
      (path) => path.startsWith('assets/static/templates/'),
    );

    for (final path in templateAssets) {
      final parts = path.split('/');
      if (parts.length >= 2) {
        final label = parts[parts.length - 2];
        templatePaths.putIfAbsent(label, () => []);
        templatePaths[label]!.add(path);
      }
    }

    return templatePaths;
  }
}

DictionaryMetadata? resolveInitialDictionary({
  required List<DictionaryMetadata> dictionaries,
  required String? selectedDictionaryId,
}) {
  if (dictionaries.isEmpty) {
    return null;
  }

  if (selectedDictionaryId != null) {
    for (final dictionary in dictionaries) {
      if (dictionary.id == selectedDictionaryId) {
        return dictionary;
      }
    }
  }

  return dictionaries.first;
}
