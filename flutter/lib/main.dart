import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:wf_solvr/wordfeud.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
  final WordfeudEngine _engine = WordfeudEngine();
  XFile? _selectedImage;

  bool _isInitializing = true;
  bool _isSolving = false;
  List<Move> _solutions = [];

  @override
  void initState() {
    super.initState();
    _setupEngine();
  }

  Future<Map<String, List<String>>> _buildTemplateMapDynamically() async {
    // Load the auto-generated asset manifest
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

    // Get a list of ALL files bundled in the app
    final allAssets = manifest.listAssets();

    Map<String, List<String>> templatePaths = {};

    // Filter only the files in your templates directory
    final templateAssets = allAssets.where(
      (path) => path.startsWith('assets/static/templates/'),
    );

    for (String path in templateAssets) {
      // path looks like: "assets/static/templates/A/1.png"
      final parts = path.split('/');

      // The second to last part is the folder name (the label)
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
      await _engine.initializeFromAssets(
        dictionaryPath:
            'assets/static/dictionaries/swedish/swedish/dictionary.txt',
        letterValuesPath:
            'assets/static/dictionaries/swedish/swedish/letter_values.csv',
        templateAssetPaths: await _buildTemplateMapDynamically(),
      );

      setState(() {
        _isInitializing = false;
      });

      if (kDebugMode) {
        print("Engine is locked and loaded.");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Failed to initialize engine: $e");
      }
    }
  }

  Future<void> _openImagePicker() async {
    if (!_engine.isReady) return;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) {
      if (kDebugMode) {
        print("No image selected.");
      }
      return;
    }

    setState(() {
      _isSolving = true;
      _solutions = [];
      _selectedImage = image;
    });

    try {
      final moves = _engine.solveFromImage(image.path);

      setState(() {
        _solutions = moves;
        _isSolving = false;
      });

      if (kDebugMode) {
        print("Found ${moves.length} valid moves.");
        for (var i = 0; i < moves.length && i < 3; i++) {
          print("${i + 1}. ${moves[i]}");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error solving image: $e");
      }

      setState(() {
        _isSolving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: _isInitializing
            ? const CircularProgressIndicator()
            : _solutions.isNotEmpty
            ? ListView.builder(
                itemCount: _solutions.length,
                itemBuilder: (context, index) {
                  final move = _solutions[index];
                  return ListTile(
                    title: Text(move.word),
                    subtitle: Text(move.score.toString()),
                  );
                },
              )
            : _isSolving
            ? const CircularProgressIndicator()
            : _selectedImage != null
            ? Image.file(File(_selectedImage!.path))
            : const Text('No image selected.'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openImagePicker,
        tooltip: 'Increment',
        child: const Icon(Icons.image),
      ),
    );
  }
}
