import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wf_solvr/models/dictionary_metadata.dart';
import 'package:wf_solvr/services/dictionary_assets_repository.dart';
import 'package:wf_solvr/services/dictionary_selection_store.dart';
import 'package:wf_solvr/widgets/solver_board_grid.dart';
import 'package:wf_solvr/widgets/solver_results_list.dart';
import 'package:wf_solvr/wordfeud.dart';

class SolverHomePage extends StatefulWidget {
  const SolverHomePage({
    super.key,
    required this.title,
    this.worker,
    this.assetsRepository,
    this.selectionStore,
  });

  final String title;
  final SolverWorker? worker;
  final DictionaryAssetsRepository? assetsRepository;
  final DictionarySelectionStore? selectionStore;

  @override
  State<SolverHomePage> createState() => _SolverHomePageState();
}

class _SolverHomePageState extends State<SolverHomePage> {
  late final SolverWorker _worker;
  late final DictionaryAssetsRepository _assetsRepository;
  late final DictionarySelectionStore _selectionStore;

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
    _worker = widget.worker ?? WordfeudWorker();
    _assetsRepository =
        widget.assetsRepository ?? RootBundleDictionaryAssetsRepository();
    _selectionStore =
        widget.selectionStore ??
        const SharedPreferencesDictionarySelectionStore();
    _setupEngine();
  }

  Future<void> _setupEngine() async {
    try {
      final loadResult = await _assetsRepository.load();
      final selectedDictionaryId = await _selectionStore
          .loadSelectedDictionaryId();
      final initialDictionary = resolveInitialDictionary(
        dictionaries: loadResult.dictionaries,
        selectedDictionaryId: selectedDictionaryId,
      );

      if (initialDictionary == null) {
        throw Exception('No dictionaries found in assets!');
      }

      final initialDictionaryData = await _assetsRepository.loadDictionaryData(
        initialDictionary,
      );

      await _worker.initialize(
        dictText: initialDictionaryData.dictText,
        csvText: initialDictionaryData.csvText,
        modelOnnxBytes: loadResult.modelOnnxBytes,
        modelLabelsJson: loadResult.modelLabelsJson,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _availableDictionaries = loadResult.dictionaries;
        _activeDictionary = initialDictionary;
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

    final previousDictionary = _activeDictionary;

    setState(() {
      _isChangingDictionary = true;
      _solutions = [];
      _selectedMove = null;
    });

    try {
      final dictionaryData = await _assetsRepository.loadDictionaryData(
        newDictionary,
      );

      await _worker.changeDictionary(
        dictionaryData.dictText,
        dictionaryData.csvText,
      );
      await _selectionStore.saveSelectedDictionaryId(newDictionary.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _activeDictionary = newDictionary;
      });

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
      if (mounted) {
        setState(() {
          _activeDictionary = previousDictionary;
        });
      }
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
