import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:wf_solvr/wordfeud.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DictionaryMetadata &&
          title == other.title &&
          dictionaryName == other.dictionaryName;

  @override
  int get hashCode => title.hashCode ^ dictionaryName.hashCode;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wordfeud Solver',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Wordfeud Solver'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final WordfeudWorker _worker = WordfeudWorker();

  XFile? _selectedImage;
  bool _isInitializing = true;
  bool _isSolving = false;
  List<Move> _solutions = [];
  List<List<String>> _boardState = [];
  Move? _selectedMove;

  // New state variables for the dictionary selector
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
    Map<String, List<String>> templatePaths = {};

    final templateAssets = allAssets.where(
      (path) => path.startsWith('assets/static/templates/'),
    );

    for (String path in templateAssets) {
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

      // 1. Scan the manifest for all metadata.json files
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final metaAssets = manifest.listAssets().where(
        (p) =>
            p.startsWith('assets/static/dictionaries/') &&
            p.endsWith('metadata.json'),
      );

      List<DictionaryMetadata> loadedDicts = [];
      for (String metaPath in metaAssets) {
        String jsonStr = await rootBundle.loadString(metaPath);
        Map<String, dynamic> json = jsonDecode(jsonStr);

        String dirPath = metaPath.substring(0, metaPath.lastIndexOf('/'));

        loadedDicts.add(
          DictionaryMetadata(
            title: json['title'] ?? 'Unknown',
            language: json['language'] ?? 'unknown',
            dictionaryName: json['dictionary'] ?? 'Unknown',
            dictPath: '$dirPath/dictionary.txt',
            csvPath: '$dirPath/letter_values.csv',
          ),
        );
      }

      // Default to the first dictionary we found
      final firstDict = loadedDicts.isNotEmpty ? loadedDicts.first : null;

      if (firstDict == null)
        throw Exception("No dictionaries found in assets!");

      String dictText = await rootBundle.loadString(firstDict.dictPath);
      String csvText = await rootBundle.loadString(firstDict.csvPath);

      // Load Templates
      Map<String, List<Uint8List>> templateBytes = {};
      for (var entry in templatePaths.entries) {
        templateBytes[entry.key] = [];
        for (var path in entry.value) {
          ByteData data = await rootBundle.load(path);
          templateBytes[entry.key]!.add(data.buffer.asUint8List());
        }
      }

      await _worker.initialize(
        dictText: dictText,
        csvText: csvText,
        templateBytes: templateBytes,
      );

      setState(() {
        _availableDictionaries = loadedDicts;
        _activeDictionary = firstDict;
        _isInitializing = false;
      });
    } catch (e) {
      print("Failed to initialize worker: $e");
    }
  }

  Future<void> _handleDictionaryChange(DictionaryMetadata? newDict) async {
    if (newDict == null || newDict == _activeDictionary || !_worker.isReady)
      return;

    setState(() {
      _isChangingDictionary = true;
      _activeDictionary = newDict;
      _solutions = []; // Clear old solutions that no longer apply
      _selectedMove = null;
    });

    try {
      // Load the new strings
      String dictText = await rootBundle.loadString(newDict.dictPath);
      String csvText = await rootBundle.loadString(newDict.csvPath);

      // Tell the background thread to swap them
      await _worker.changeDictionary(dictText, csvText);

      // If we already have an image loaded, automatically re-solve it!
      if (_selectedImage != null) {
        final response = await _worker.solve(_selectedImage!.path);
        setState(() {
          _solutions = response.moves;
          _boardState = response.board;
          if (_solutions.isNotEmpty) _selectedMove = _solutions.first;
        });
      }
    } catch (e) {
      print("Failed to swap dictionary: $e");
    } finally {
      setState(() {
        _isChangingDictionary = false;
      });
    }
  }

  Future<void> _openImagePicker() async {
    if (!_worker.isReady) return;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() {
      _isSolving = true;
      _solutions = [];
      _boardState = [];
      _selectedMove = null;
      _selectedImage = image;
    });

    try {
      final response = await _worker.solve(image.path);

      setState(() {
        _solutions = response.moves;
        _boardState = response.board;
        if (_solutions.isNotEmpty) {
          _selectedMove = _solutions.first;
        }
        _isSolving = false;
      });
    } catch (e) {
      print("Error solving image: $e");
      setState(() => _isSolving = false);
    }
  }

  // --- UI BUILDERS ---

  Color _getTileColor(String cellValue, bool isHighlight) {
    if (isHighlight) return Colors.yellowAccent.shade400; // The selected move
    if (cellValue.length == 1 && cellValue != '?')
      return Colors.orange.shade100; // Existing standard tile

    switch (cellValue) {
      case 'DL':
        return Colors.green.shade300;
      case 'TL':
        return Colors.green.shade700;
      case 'DW':
        return Colors.red.shade300;
      case 'TW':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade200; // EMPTY
    }
  }

  Widget _buildBoardGrid() {
    if (_boardState.isEmpty) {
      return const Center(child: Text("Load an image to see the board."));
    }

    return AspectRatio(
      aspectRatio: 1, // Keep it a perfect square
      child: Container(
        padding: const EdgeInsets.all(4),
        color: Colors.black, // Grid border color
        child: GridView.builder(
          physics:
              const NeverScrollableScrollPhysics(), // Disable internal scroll
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 15,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
          ),
          itemCount: 225,
          itemBuilder: (context, index) {
            int row = index ~/ 15;
            int col = index % 15;

            String cellValue = _boardState[row][col];
            String displayChar = cellValue;
            bool isPartOfMove = false;

            // Overlay the selected move
            if (_selectedMove != null) {
              int r = _selectedMove!.row;
              int c = _selectedMove!.col;
              int len = _selectedMove!.word.length;
              String dir = _selectedMove!.direction;

              if (dir == 'H' && row == r && col >= c && col < c + len) {
                isPartOfMove = true;
                displayChar = _selectedMove!.word[col - c];
              } else if (dir == 'V' && col == c && row >= r && row < r + len) {
                isPartOfMove = true;
                displayChar = _selectedMove!.word[row - r];
              }
            }

            // Cleanup display for empty/multiplier squares if no tile is played there
            if (!isPartOfMove && cellValue.length > 2) {
              displayChar = ''; // Hide 'EMPTY' text
            }

            return Container(
              alignment: Alignment.center,
              color: _getTileColor(cellValue, isPartOfMove),
              child: Text(
                displayChar,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color:
                      (cellValue == 'TL' || cellValue == 'TW') && !isPartOfMove
                      ? Colors.white
                      : Colors.black,
                ),
              ),
            );
          },
        ),
      ),
    );
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
              padding: EdgeInsets.symmetric(horizontal: 16.0),
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
              padding: const EdgeInsets.only(right: 8.0),
              child: DropdownButton<DictionaryMetadata>(
                value: _activeDictionary,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                dropdownColor: Theme.of(context).colorScheme.surface,
                underline: const SizedBox(), // Hides the default underline
                onChanged: _handleDictionaryChange,
                // 1. What to show when the menu is CLOSED (in the AppBar)
                selectedItemBuilder: (BuildContext context) {
                  return _availableDictionaries.map<Widget>((
                    DictionaryMetadata dict,
                  ) {
                    return Center(
                      child: Text(
                        dict.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // Matches typical AppBar text
                        ),
                      ),
                    );
                  }).toList();
                },
                // 2. What to show when the menu is OPEN (the list items)
                items: _availableDictionaries.map((DictionaryMetadata dict) {
                  return DropdownMenuItem<DictionaryMetadata>(
                    value: dict,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dict.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          dict.dictionaryName,
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
                // TOP HALF: The Game Board
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _buildBoardGrid(),
                ),
                const Divider(height: 1),

                // BOTTOM HALF: The Scrollable Solutions List
                Expanded(
                  child: _solutions.isNotEmpty
                      ? ListView.separated(
                          itemCount: _solutions.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final move = _solutions[index];
                            final isSelected = _selectedMove == move;

                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: Colors.green.shade50,
                              leading: CircleAvatar(
                                backgroundColor: isSelected
                                    ? Colors.green
                                    : Colors.grey.shade300,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              title: Text(
                                move.word,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                'Dir: ${move.direction == 'H' ? 'Across' : 'Down'} | Row: ${move.row}, Col: ${move.col}',
                              ),
                              trailing: Text(
                                '${move.score} pts',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green,
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedMove = move;
                                });
                              },
                            );
                          },
                        )
                      : const Center(
                          child: Text(
                            'No solutions found or no image selected.',
                          ),
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
