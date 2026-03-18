import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:wf_solvr/models/dictionary_metadata.dart';

class DictionaryLoadResult {
  DictionaryLoadResult({
    required this.dictionaries,
    required this.modelOnnxBytes,
    required this.modelLabelsJson,
  });

  final List<DictionaryMetadata> dictionaries;
  final Uint8List modelOnnxBytes;
  final String modelLabelsJson;
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

    final modelData = await _assetBundle.load(
      'assets/static/models/tile_classifier.onnx',
    );
    final modelOnnxBytes = modelData.buffer.asUint8List();
    final modelLabelsJson = await _assetBundle.loadString(
      'assets/static/models/labels.json',
    );

    return DictionaryLoadResult(
      dictionaries: loadedDictionaries,
      modelOnnxBytes: modelOnnxBytes,
      modelLabelsJson: modelLabelsJson,
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
