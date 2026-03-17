import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wf_solvr/models/dictionary_metadata.dart';
import 'package:wf_solvr/widgets/solver_board_grid.dart';
import 'package:wf_solvr/widgets/solver_results_list.dart';
import 'package:wf_solvr/wordfeud.dart';

class SolverHomePage extends StatefulWidget {
  const SolverHomePage({super.key, required this.title});

  final String title;

  @override
  State<SolverHomePage> createState() => _SolverHomePageState();
}

class _SolverHomePageState extends State<SolverHomePage> {
  final WordfeudWorker _worker = WordfeudWorker();

  XFile? _selectedImage;
  bool _isInitializing = true;
  bool _isSolving = false;
  List<Move> _solutions = [];
  List<List<String>> _boardState = [];
  Move? _selectedMove;
  List<DictionaryMetadata> _availableDictionaries = [];
  DictionaryMetadata? _activeDictionary;
  bool _isChangingDictionary = false;

  @override
  void initState() {
    super.initState();
    _setupEngine();
  }

  Future<Map<String, List<String>>> _buildTemplateMapDynamically() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
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

  Future<void> _setupEngine() async {
    try {
      final templatePaths = await _buildTemplateMapDynamically();
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final metaAssets = manifest.listAssets().where(
        (path) =>
            path.startsWith('assets/static/dictionaries/') &&
            path.endsWith('metadata.json'),
      );

      final loadedDictionaries = <DictionaryMetadata>[];
      for (final metaPath in metaAssets) {
        final jsonStr = await rootBundle.loadString(metaPath);
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

      final firstDictionary = loadedDictionaries.isNotEmpty
          ? loadedDictionaries.first
          : null;
      if (firstDictionary == null) {
        throw Exception('No dictionaries found in assets!');
      }

      final dictText = await rootBundle.loadString(firstDictionary.dictPath);
      final csvText = await rootBundle.loadString(firstDictionary.csvPath);

      final templateBytes = <String, List<Uint8List>>{};
      for (final entry in templatePaths.entries) {
        templateBytes[entry.key] = [];
        for (final path in entry.value) {
          final data = await rootBundle.load(path);
          templateBytes[entry.key]!.add(data.buffer.asUint8List());
        }
      }

      await _worker.initialize(
        dictText: dictText,
        csvText: csvText,
        templateBytes: templateBytes,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _availableDictionaries = loadedDictionaries;
        _activeDictionary = firstDictionary;
        _isInitializing = false;
      });
    } catch (error) {
      debugPrint('Failed to initialize worker: $error');
    }
  }

  Future<void> _handleDictionaryChange(
    DictionaryMetadata? newDictionary,
  ) async {
    if (newDictionary == null ||
        newDictionary == _activeDictionary ||
        !_worker.isReady) {
      return;
    }

    setState(() {
      _isChangingDictionary = true;
      _activeDictionary = newDictionary;
      _solutions = [];
      _selectedMove = null;
    });

    try {
      final dictText = await rootBundle.loadString(newDictionary.dictPath);
      final csvText = await rootBundle.loadString(newDictionary.csvPath);

      await _worker.changeDictionary(dictText, csvText);

      if (_selectedImage != null) {
        final response = await _worker.solve(_selectedImage!.path);
        if (!mounted) {
          return;
        }

        setState(() {
          _solutions = response.moves;
          _boardState = response.board;
          if (_solutions.isNotEmpty) {
            _selectedMove = _solutions.first;
          }
        });
      }
    } catch (error) {
      debugPrint('Failed to swap dictionary: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isChangingDictionary = false;
        });
      }
    }
  }

  Future<void> _openImagePicker() async {
    if (!_worker.isReady) {
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      return;
    }

    setState(() {
      _isSolving = true;
      _solutions = [];
      _boardState = [];
      _selectedMove = null;
      _selectedImage = image;
    });

    try {
      final response = await _worker.solve(image.path);
      if (!mounted) {
        return;
      }

      setState(() {
        _solutions = response.moves;
        _boardState = response.board;
        if (_solutions.isNotEmpty) {
          _selectedMove = _solutions.first;
        }
        _isSolving = false;
      });
    } catch (error) {
      debugPrint('Error solving image: $error');
      if (!mounted) {
        return;
      }
      setState(() => _isSolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          if (_isChangingDictionary)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else if (_availableDictionaries.isNotEmpty &&
              _activeDictionary != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButton<DictionaryMetadata>(
                value: _activeDictionary,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                dropdownColor: Theme.of(context).colorScheme.surface,
                underline: const SizedBox(),
                onChanged: _handleDictionaryChange,
                selectedItemBuilder: (context) {
                  return _availableDictionaries.map<Widget>((dictionary) {
                    return Center(
                      child: Text(
                        dictionary.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    );
                  }).toList();
                },
                items: _availableDictionaries.map((dictionary) {
                  return DropdownMenuItem<DictionaryMetadata>(
                    value: dictionary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dictionary.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          dictionary.dictionaryName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : _isSolving
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SolverBoardGrid(
                    boardState: _boardState,
                    selectedMove: _selectedMove,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SolverResultsList(
                    solutions: _solutions,
                    selectedMove: _selectedMove,
                    onMoveSelected: (move) {
                      setState(() {
                        _selectedMove = move;
                      });
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openImagePicker,
        tooltip: 'Pick Screenshot',
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
