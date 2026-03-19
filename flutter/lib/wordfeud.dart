import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

// --- DATA MODELS ---

class Move {
  final String word;
  final int row;
  final int col;
  final String direction;
  int score;

  Move({
    required this.word,
    required this.row,
    required this.col,
    required this.direction,
    this.score = 0,
  });

  @override
  String toString() => '$word at ($col, $row) [$direction] - Score: $score';

  // Helper for unique sets
  String get uniqueKey => '${word}_${row}_${col}_$direction';
}

class TrieNode {
  final Map<String, TrieNode> children = {};
  bool isEndOfWord = false;
}

class Trie {
  final TrieNode root = TrieNode();

  void insert(String word) {
    TrieNode node = root;
    for (int i = 0; i < word.length; i++) {
      String char = word[i].toUpperCase();
      node.children.putIfAbsent(char, () => TrieNode());
      node = node.children[char]!;
    }
    node.isEndOfWord = true;
  }

  bool search(String word) {
    TrieNode node = root;
    for (int i = 0; i < word.length; i++) {
      String char = word[i].toUpperCase();
      if (!node.children.containsKey(char)) return false;
      node = node.children[char]!;
    }
    return node.isEndOfWord;
  }
}

// --- THE ENGINE ---

class WordfeudEngine {
  final Trie _dictionaryTrie = Trie();
  Map<String, int> _pointValues = {};
  cv.Net? _classifierNet;
  List<String> _tileTypeLabels = [];
  List<String> _modifierLabels = [];
  List<String> _letterLabels = [];
  static const int _modelInputSize = 40;

  List<List<String>> lastParsedBoard = [];
  List<String> lastParsedRack = [];

  bool get isReady =>
      _pointValues.isNotEmpty &&
      _classifierNet != null &&
      _tileTypeLabels.isNotEmpty &&
      _modifierLabels.isNotEmpty &&
      _letterLabels.isNotEmpty;

  /// Initializes the engine using raw bytes passed from the main thread.
  void initializeFromRawData({
    required String dictionaryText,
    required String letterValuesText,
    required Uint8List modelOnnxBytes,
    required String modelLabelsJson,
  }) {
    List<String> dictWords = dictionaryText
        .split('\n')
        .where((w) => w.trim().isNotEmpty)
        .toList();

    Map<String, int> points = {};
    for (var line in letterValuesText.split('\n')) {
      var parts = line.split(',');
      if (parts.length >= 2) {
        points[parts[0].trim().toUpperCase()] =
            int.tryParse(parts[1].trim()) ?? 0;
      }
    }

    final labelsObject = jsonDecode(modelLabelsJson) as Map<String, dynamic>;
    final tileTypeToIdx =
        (labelsObject['tile_type_to_idx'] as Map<String, dynamic>);
    final modifierToIdx =
        (labelsObject['modifier_to_idx'] as Map<String, dynamic>);
    final letterToIdx = (labelsObject['letter_to_idx'] as Map<String, dynamic>);

    final loadedNet = _loadClassifierNetFromOnnxBytes(modelOnnxBytes);

    _initialize(
      dictionaryWords: dictWords,
      letterValues: points,
      classifierNet: loadedNet,
      tileTypeToIdx: tileTypeToIdx,
      modifierToIdx: modifierToIdx,
      letterToIdx: letterToIdx,
    );
  }

  void _initialize({
    required List<String> dictionaryWords,
    required Map<String, int> letterValues,
    required cv.Net classifierNet,
    required Map<String, dynamic> tileTypeToIdx,
    required Map<String, dynamic> modifierToIdx,
    required Map<String, dynamic> letterToIdx,
  }) {
    for (var word in dictionaryWords) {
      _dictionaryTrie.insert(word.trim());
    }
    _pointValues = letterValues;
    _pointValues['?'] = 0; // Wildcard
    _classifierNet = classifierNet;
    _tileTypeLabels = _indexToLabel(tileTypeToIdx);
    _modifierLabels = _indexToLabel(modifierToIdx);
    _letterLabels = _indexToLabel(letterToIdx);
  }

  List<String> _indexToLabel(Map<String, dynamic> labelToIndex) {
    final maxIndex = labelToIndex.values
        .map((value) => value as int)
        .reduce((a, b) => a > b ? a : b);
    final labels = List<String>.filled(maxIndex + 1, '?');
    labelToIndex.forEach((label, index) {
      labels[index as int] = label;
    });
    return labels;
  }

  cv.Net _loadClassifierNetFromOnnxBytes(Uint8List modelOnnxBytes) {
    final modelFile = File(
      '${Directory.systemTemp.path}/wf_tile_classifier.onnx',
    );
    modelFile.writeAsBytesSync(modelOnnxBytes, flush: true);
    return cv.Net.fromOnnx(modelFile.path);
  }

  // --- MAIN ENTRY POINT ---

  /// Call this with an XFile.path or any valid local file path.
  List<Move> solveFromImage(String imagePath) {
    if (!isReady) throw Exception("Engine not initialized with assets.");

    cv.Mat image = cv.imread(imagePath);
    if (image.isEmpty) throw Exception("Failed to load image at $imagePath");

    // 1. Parse Image
    List<List<String>> board = _parseBoard(image);
    List<String> rack = _parseRack(image);
    image.dispose();

    lastParsedBoard = board;
    lastParsedRack = rack;

    // 2. Solve Board
    List<Move> allMoves = _findAllMoves(board, rack);

    // 3. Score & Rank
    for (var move in allMoves) {
      move.score = _calculateScore(move, board);
    }

    allMoves.sort((a, b) => b.score.compareTo(a.score));

    return allMoves;
  }

  // --- PARSER LOGIC ---

  List<List<String>> _parseBoard(cv.Mat image) {
    cv.Mat gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    var threshResult = cv.threshold(gray, 40, 255, cv.THRESH_BINARY_INV);
    cv.Mat thresh = threshResult.$2;

    var contoursResult = cv.findContours(
      thresh,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    var contours = contoursResult.$1;

    if (contours.isEmpty) throw Exception("No contours found.");

    double maxArea = 0;
    cv.VecPoint largestContour = contours.first;
    for (var c in contours) {
      double area = cv.contourArea(c);
      if (area > maxArea) {
        maxArea = area;
        largestContour = c;
      }
    }

    double epsilon = 0.02 * cv.arcLength(largestContour, true);
    cv.VecPoint approx = cv.approxPolyDP(largestContour, epsilon, true);

    if (approx.length != 4) {
      throw Exception("Could not find exactly 4 corners for the board.");
    }

    cv.VecPoint srcPts = _orderPoints(approx);
    int boardSize = 600;
    cv.VecPoint dstPts = cv.VecPoint.fromList([
      cv.Point(0, 0),
      cv.Point(boardSize, 0),
      cv.Point(boardSize, boardSize),
      cv.Point(0, boardSize),
    ]);

    cv.Mat matrix = cv.getPerspectiveTransform(srcPts, dstPts);

    cv.Mat flatBoard = cv.warpPerspective(image, matrix, (
      boardSize,
      boardSize,
    ));

    cv.Mat flatGray = cv.cvtColor(flatBoard, cv.COLOR_BGR2GRAY);

    int gridSize = 15;
    int cellSize = boardSize ~/ gridSize;
    List<List<String>> parsedBoard = List.generate(
      gridSize,
      (_) => List.filled(gridSize, ''),
    );
    final cells = <cv.Mat>[];

    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        cv.Mat cell = flatGray.region(
          cv.Rect(c * cellSize, r * cellSize, cellSize, cellSize),
        );
        cells.add(cell);
      }
    }

    final predictions = _predictCellsBatch(cells);
    for (int i = 0; i < predictions.length; i++) {
      parsedBoard[i ~/ gridSize][i % gridSize] = predictions[i];
      cells[i].dispose();
    }

    gray.dispose();
    thresh.dispose();
    matrix.dispose();
    flatBoard.dispose();
    flatGray.dispose();
    return parsedBoard;
  }

  List<String> _parseRack(cv.Mat image) {
    cv.Mat gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    var threshResult = cv.threshold(gray, 40, 255, cv.THRESH_BINARY_INV);
    cv.Mat thresh = threshResult.$2;

    // 1. Find the main board to establish our dynamic sizing and Y-cutoff
    var contoursResult = cv.findContours(
      thresh,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    var contours = contoursResult.$1;

    if (contours.isEmpty) {
      throw Exception("Could not find any contours in the image.");
    }

    double maxArea = 0;
    cv.VecPoint largestContour = contours.first;
    for (var c in contours) {
      double area = cv.contourArea(c);
      if (area > maxArea) {
        maxArea = area;
        largestContour = c;
      }
    }

    cv.Rect boardBoundingBox = cv.boundingRect(largestContour);

    // Calculate what a "valid tile" should look like mathematically
    double expectedArea = boardBoundingBox.width * 155.0;

    // 2. Crop the image to just the area BELOW the game board
    int bottomUiTop = boardBoundingBox.y + boardBoundingBox.height;
    if (bottomUiTop >= gray.rows) {
      throw Exception(
        "Board extends to the bottom of the image, no rack found.",
      );
    }

    cv.Mat bottomUiGray = gray.region(
      cv.Rect(0, bottomUiTop, gray.cols, gray.rows - bottomUiTop),
    );

    var uiThreshResult = cv.threshold(
      bottomUiGray,
      40,
      255,
      cv.THRESH_BINARY_INV,
    );
    cv.Mat uiThresh = uiThreshResult.$2;

    // 3. Find all contours in the bottom UI (RETR_LIST)
    var uiContoursResult = cv.findContours(
      uiThresh,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_SIMPLE,
    );
    var uiContours = uiContoursResult.$1;

    cv.Rect rackBoundingBox = cv.Rect(0, 0, 0, 0);

    for (var cnt in uiContours) {
      cv.Rect cntRect = cv.boundingRect(cnt);
      double aspectRatio = cntRect.width / cntRect.height;
      double area = (cntRect.width * cntRect.height).toDouble();

      // 4. Filter: Must be roughly square and close to the expected tile area
      bool isSquare = 6.1 <= aspectRatio && aspectRatio <= 6.6;
      bool isRightSize =
          (0.6 * expectedArea) < area && area < (1.4 * expectedArea);

      if (isSquare && isRightSize) {
        rackBoundingBox = cntRect;
        break; // Found the rack container
      }
    }

    if (rackBoundingBox.width == 0) {
      print("Warning: Could not perfectly isolate the rack bounds.");
      return List.filled(7, "?");
    }

    // 4. Split into seven equal tiles
    cv.Mat rackImg = bottomUiGray.region(rackBoundingBox);
    int tileWidth = rackBoundingBox.width ~/ 7;
    List<cv.Mat> tiles = [];

    for (int i = 0; i < 7; i++) {
      int startColumn = i * tileWidth;
      int width = (i == 6) ? rackBoundingBox.width - startColumn : tileWidth;

      cv.Mat tileImg = rackImg.region(
        cv.Rect(startColumn, 0, width, rackBoundingBox.height),
      );
      tiles.add(tileImg);
    }

    // 5. Classify the Rack Tiles
    final predictions = _predictCellsBatch(tiles);
    final parsedRack = <String>[];
    for (int i = 0; i < predictions.length; i++) {
      final prediction = predictions[i];
      final mappedPrediction = prediction == 'EMPTY' ? '' : prediction;
      parsedRack.add(mappedPrediction);
      tiles[i].dispose();
    }

    // Cleanup Mats
    gray.dispose();
    thresh.dispose();
    bottomUiGray.dispose();
    uiThresh.dispose();
    rackImg.dispose();

    return parsedRack;
  }

  List<String> _predictCellsBatch(List<cv.Mat> cells) {
    if (cells.isEmpty) {
      return [];
    }
    final inferenceStopwatch = Stopwatch()..start();

    final net = _classifierNet;
    if (net == null) {
      throw Exception('Classifier model has not been loaded.');
    }

    final normalizedCells = <cv.Mat>[];
    for (final cell in cells) {
      final resized = cv.resize(cell, (_modelInputSize, _modelInputSize));
      final normalized = resized.convertTo(
        cv.MatType.CV_32FC1,
        alpha: 1.0 / 255.0,
      );
      resized.dispose();
      normalizedCells.add(normalized);
    }

    final vec = cv.VecMat.fromList(normalizedCells);
    final blob = cv.blobFromImages(
      vec,
      size: (_modelInputSize, _modelInputSize),
      ddepth: cv.MatType.CV_32F,
    );
    vec.dispose();
    for (final normalizedCell in normalizedCells) {
      normalizedCell.dispose();
    }

    net.setInput(blob);
    final outputs = net.forwardLayers(['tile_type', 'modifier', 'letter']);
    blob.dispose();

    final tileLogits = _reshapeLogits(
      outputs[0],
      batchSize: cells.length,
      classCount: _tileTypeLabels.length,
      headName: 'tile_type',
    );
    final modifierLogits = _reshapeLogits(
      outputs[1],
      batchSize: cells.length,
      classCount: _modifierLabels.length,
      headName: 'modifier',
    );
    final letterLogits = _reshapeLogits(
      outputs[2],
      batchSize: cells.length,
      classCount: _letterLabels.length,
      headName: 'letter',
    );
    outputs.dispose();

    final predictions = List<String>.filled(cells.length, 'EMPTY');
    for (int i = 0; i < cells.length; i++) {
      final tileType = _tileTypeLabels[_argmax(tileLogits[i])];

      if (tileType == 'EMPTY') {
        predictions[i] = 'EMPTY';
      } else if (tileType == 'MODIFIER') {
        predictions[i] = _modifierLabels[_argmax(modifierLogits[i])];
      } else {
        final letter = _letterLabels[_argmax(letterLogits[i])];
        predictions[i] = letter == 'WILDCARD' ? '?' : letter;
      }
    }

    inferenceStopwatch.stop();
    developer.log(
      'WordfeudEngine: Tile inference: ${cells.length} cells in '
      '${inferenceStopwatch.elapsedMilliseconds}ms',
      name: 'WordfeudEngine',
    );

    return predictions;
  }

  List<List<double>> _reshapeLogits(
    cv.Mat output, {
    required int batchSize,
    required int classCount,
    required String headName,
  }) {
    final rawBytes = output.data;
    if (rawBytes.lengthInBytes % Float32List.bytesPerElement != 0) {
      throw Exception('Unexpected output byte length for $headName head.');
    }

    final floatCount = rawBytes.lengthInBytes ~/ Float32List.bytesPerElement;
    final floatView = rawBytes.buffer.asFloat32List(
      rawBytes.offsetInBytes,
      floatCount,
    );
    final logits = floatView.toList(growable: false);
    final expected = batchSize * classCount;
    if (logits.length != expected) {
      throw Exception(
        'Unexpected output shape for $headName head: expected $expected '
        'values but got ${logits.length}.',
      );
    }

    return List<List<double>>.generate(
      batchSize,
      (i) => logits.sublist(i * classCount, (i + 1) * classCount),
      growable: false,
    );
  }

  int _argmax(List<double> values) {
    int bestIndex = 0;
    double bestValue = values[0];
    for (int i = 1; i < values.length; i++) {
      if (values[i] > bestValue) {
        bestValue = values[i];
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  cv.VecPoint _orderPoints(cv.VecPoint pts) {
    List<cv.Point> list = pts.toList();
    list.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    cv.Point tl = list.first;
    cv.Point br = list.last;

    list.sort((a, b) => (a.x - a.y).compareTo(b.x - b.y));
    cv.Point tr = list.last;
    cv.Point bl = list.first;

    return cv.VecPoint.fromList([tl, tr, br, bl]);
  }

  // --- SOLVER LOGIC ---

  bool _isEmpty(String sq) => sq.length != 1;

  List<List<Set<String>>> _getCrossChecks(List<List<String>> board) {
    List<List<Set<String>>> crossChecks = List.generate(
      15,
      (_) => List.generate(15, (_) => <String>{}),
    );
    String alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

    for (int r = 0; r < 15; r++) {
      for (int c = 0; c < 15; c++) {
        if (!_isEmpty(board[r][c])) continue;

        String prefix = "";
        int rowUp = r - 1;
        while (rowUp >= 0 && !_isEmpty(board[rowUp][c])) {
          prefix = board[rowUp][c] + prefix;
          rowUp--;
        }

        String suffix = "";
        int rowDown = r + 1;
        while (rowDown < 15 && !_isEmpty(board[rowDown][c])) {
          suffix += board[rowDown][c];
          rowDown++;
        }

        if (prefix.isEmpty && suffix.isEmpty) {
          crossChecks[r][c] = alphabet.split('').toSet();
        } else {
          Set<String> valid = {};
          for (String char in alphabet.split('')) {
            if (_dictionaryTrie.search(prefix + char + suffix)) {
              valid.add(char);
            }
          }
          crossChecks[r][c] = valid;
        }
      }
    }
    return crossChecks;
  }

  List<List<int>> _getAnchors(List<List<String>> board) {
    List<List<int>> anchors = [];
    bool isFirstTurn = true;

    for (int r = 0; r < 15; r++) {
      for (int c = 0; c < 15; c++) {
        if (!_isEmpty(board[r][c])) {
          isFirstTurn = false;
          continue;
        }

        if ((r > 0 && !_isEmpty(board[r - 1][c])) ||
            (r < 14 && !_isEmpty(board[r + 1][c])) ||
            (c > 0 && !_isEmpty(board[r][c - 1])) ||
            (c < 14 && !_isEmpty(board[r][c + 1]))) {
          anchors.add([r, c]);
        }
      }
    }

    if (isFirstTurn) anchors.add([7, 7]);
    return anchors;
  }

  void _extendRight(
    List<List<String>> board,
    int row,
    int col,
    List<String> rack,
    TrieNode currentNode,
    String prefix,
    List<List<Set<String>>> crossChecks,
    List<Move> results,
    int startCol,
    int anchorCol,
    bool isTransposed,
  ) {
    if (col == 15) {
      if (currentNode.isEndOfWord && col > anchorCol) {
        results.add(
          Move(
            word: prefix,
            row: isTransposed ? startCol : row,
            col: isTransposed ? row : startCol,
            direction: isTransposed ? 'V' : 'H',
          ),
        );
      }
      return;
    }

    if (_isEmpty(board[row][col])) {
      if (currentNode.isEndOfWord && col > anchorCol) {
        results.add(
          Move(
            word: prefix,
            row: isTransposed ? startCol : row,
            col: isTransposed ? row : startCol,
            direction: isTransposed ? 'V' : 'H',
          ),
        );
      }

      for (String char in rack.toSet()) {
        if (char == '?') {
          List<String> newRack = List.from(rack)..remove('?');
          for (String validChar in currentNode.children.keys) {
            if (crossChecks[row][col].contains(validChar)) {
              _extendRight(
                board,
                row,
                col + 1,
                newRack,
                currentNode.children[validChar]!,
                prefix + validChar.toLowerCase(),
                crossChecks,
                results,
                startCol,
                anchorCol,
                isTransposed,
              );
            }
          }
        } else {
          if (currentNode.children.containsKey(char) &&
              crossChecks[row][col].contains(char)) {
            List<String> newRack = List.from(rack)..remove(char);
            _extendRight(
              board,
              row,
              col + 1,
              newRack,
              currentNode.children[char]!,
              prefix + char,
              crossChecks,
              results,
              startCol,
              anchorCol,
              isTransposed,
            );
          }
        }
      }
    } else {
      String existing = board[row][col].toUpperCase();
      if (currentNode.children.containsKey(existing)) {
        _extendRight(
          board,
          row,
          col + 1,
          rack,
          currentNode.children[existing]!,
          prefix + board[row][col],
          crossChecks,
          results,
          startCol,
          anchorCol,
          isTransposed,
        );
      }
    }
  }

  void _leftPart(
    List<List<String>> board,
    int row,
    int anchorCol,
    int limit,
    List<String> rack,
    TrieNode currentNode,
    String prefix,
    List<List<Set<String>>> crossChecks,
    List<Move> results,
    int startCol,
    bool isTransposed,
  ) {
    _extendRight(
      board,
      row,
      anchorCol,
      rack,
      currentNode,
      prefix,
      crossChecks,
      results,
      startCol,
      anchorCol,
      isTransposed,
    );

    if (limit > 0) {
      for (String char in rack.toSet()) {
        if (char == '?') {
          List<String> newRack = List.from(rack)..remove('?');
          for (String validChar in currentNode.children.keys) {
            _leftPart(
              board,
              row,
              anchorCol,
              limit - 1,
              newRack,
              currentNode.children[validChar]!,
              prefix + validChar.toLowerCase(),
              crossChecks,
              results,
              startCol - 1,
              isTransposed,
            );
          }
        } else {
          if (currentNode.children.containsKey(char)) {
            List<String> newRack = List.from(rack)..remove(char);
            _leftPart(
              board,
              row,
              anchorCol,
              limit - 1,
              newRack,
              currentNode.children[char]!,
              prefix + char,
              crossChecks,
              results,
              startCol - 1,
              isTransposed,
            );
          }
        }
      }
    }
  }

  List<Move> _findAllMoves(List<List<String>> board, List<String> rack) {
    List<String> cleanRack = rack
        .where((t) => RegExp(r'^[A-Za-z?]$').hasMatch(t))
        .map((t) => t.toUpperCase())
        .toList();

    List<Move> allMoves = [];

    void scan(List<List<String>> currentBoard, bool isTransposed) {
      var crossChecks = _getCrossChecks(currentBoard);
      var anchors = _getAnchors(currentBoard);

      for (int r = 0; r < 15; r++) {
        List<int> rowAnchors = anchors
            .where((a) => a[0] == r)
            .map((a) => a[1])
            .toList();

        for (int i = 0; i < rowAnchors.length; i++) {
          int anchorCol = rowAnchors[i];

          if (anchorCol > 0 && !_isEmpty(currentBoard[r][anchorCol - 1])) {
            String prefix = "";
            int currC = anchorCol - 1;
            while (currC >= 0 && !_isEmpty(currentBoard[r][currC])) {
              prefix = currentBoard[r][currC] + prefix;
              currC--;
            }

            TrieNode? node = _dictionaryTrie.root;
            bool validPrefix = true;
            for (int j = 0; j < prefix.length; j++) {
              String char = prefix[j].toUpperCase();
              if (node!.children.containsKey(char)) {
                node = node.children[char];
              } else {
                validPrefix = false;
                break;
              }
            }

            if (validPrefix) {
              _extendRight(
                currentBoard,
                r,
                anchorCol,
                List.from(cleanRack),
                node!,
                prefix,
                crossChecks,
                allMoves,
                anchorCol - prefix.length,
                anchorCol,
                isTransposed,
              );
            }
          } else {
            int prevAnchor = i > 0 ? rowAnchors[i - 1] : -1;
            int limit = 0;
            int currC = anchorCol - 1;
            while (currC > prevAnchor && _isEmpty(currentBoard[r][currC])) {
              limit++;
              currC--;
            }

            _leftPart(
              currentBoard,
              r,
              anchorCol,
              limit,
              List.from(cleanRack),
              _dictionaryTrie.root,
              "",
              crossChecks,
              allMoves,
              anchorCol,
              isTransposed,
            );
          }
        }
      }
    }

    // Horizontal scan
    scan(board, false);

    // Vertical scan (Transpose board)
    List<List<String>> transposed = List.generate(
      15,
      (c) => List.generate(15, (r) => board[r][c]),
    );
    scan(transposed, true);

    // Filter unique moves
    Map<String, Move> uniqueMoves = {};
    for (var move in allMoves) {
      if (move.word.length > 1) {
        uniqueMoves[move.uniqueKey] = move;
      }
    }

    return uniqueMoves.values.toList();
  }

  // --- SCORER LOGIC ---

  int _calculateScore(Move move, List<List<String>> board) {
    int baseScore = 0;
    int wordMultiplier = 1;
    int tilesPlayed = 0;

    for (int i = 0; i < move.word.length; i++) {
      String char = move.word[i].toUpperCase();
      int r = move.direction == 'V' ? move.row + i : move.row;
      int c = move.direction == 'H' ? move.col + i : move.col;

      String sq = board[r][c];
      int val = _pointValues[char] ?? 0;

      if (!_isEmpty(sq)) {
        baseScore += val;
      } else {
        tilesPlayed++;
        if (sq == 'DL') {
          baseScore += (val * 2);
        } else if (sq == 'TL')
          baseScore += (val * 3);
        else
          baseScore += val;

        if (sq == 'DW') {
          wordMultiplier *= 2;
        } else if (sq == 'TW')
          wordMultiplier *= 3;
      }
    }

    int total = baseScore * wordMultiplier;
    if (tilesPlayed == 7) total += 40;
    return total;
  }

  /// Swaps the active dictionary and point values without reloading image templates.
  void updateDictionary({
    required String dictionaryText,
    required String letterValuesText,
  }) {
    // Clear the old Trie
    _dictionaryTrie.root.children.clear();

    // Load the new one
    List<String> dictWords = dictionaryText
        .split('\n')
        .where((w) => w.trim().isNotEmpty)
        .toList();
    for (var word in dictWords) {
      _dictionaryTrie.insert(word.trim());
    }

    // Load the new point values
    Map<String, int> points = {};
    for (var line in letterValuesText.split('\n')) {
      var parts = line.split(',');
      if (parts.length >= 2) {
        points[parts[0].trim().toUpperCase()] =
            int.tryParse(parts[1].trim()) ?? 0;
      }
    }

    _pointValues = points;
    _pointValues['?'] = 0;
  }
}

class SolveResponse {
  final List<Move> moves;
  final List<List<String>> board;
  final List<String> rack;

  SolveResponse(this.moves, this.board, this.rack);
}

abstract class SolverWorker {
  bool get isReady;
  Future<void> initialize({
    required String dictText,
    required String csvText,
    required Uint8List modelOnnxBytes,
    required String modelLabelsJson,
  });
  Future<SolveResponse> solve(String imagePath);
  Future<void> changeDictionary(String dictText, String csvText);
}

class WordfeudWorker implements SolverWorker {
  SendPort? _backgroundSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  @override
  bool isReady = false;

  /// Spawns the isolate and passes the raw asset data into it.
  @override
  Future<void> initialize({
    required String dictText,
    required String csvText,
    required Uint8List modelOnnxBytes,
    required String modelLabelsJson,
  }) async {
    // 1. Spawn the background thread
    await Isolate.spawn(_isolateEntry, _mainReceivePort.sendPort);
    final broadcastStream = _mainReceivePort.asBroadcastStream();

    // 2. Grab the port to talk to the background thread
    _backgroundSendPort = await broadcastStream.first as SendPort;

    // 3. Send the raw data
    _backgroundSendPort!.send({
      'type': 'INIT',
      'dictText': dictText,
      'csvText': csvText,
      'modelOnnxBytes': modelOnnxBytes,
      'modelLabelsJson': modelLabelsJson,
    });

    // 4. Wait for it to finish building the Trie and OpenCV Mats
    await broadcastStream.firstWhere((msg) => msg == 'READY');
    isReady = true;
  }

  /// Sends an image path to the background thread and waits for the solution.
  @override
  Future<SolveResponse> solve(String imagePath) async {
    if (!isReady || _backgroundSendPort == null) {
      throw Exception("Worker not ready.");
    }

    final responsePort = ReceivePort();
    _backgroundSendPort!.send({
      'type': 'SOLVE',
      'path': imagePath,
      'replyTo': responsePort.sendPort,
    });

    final result = await responsePort.first;
    responsePort.close();
    return result as SolveResponse;
  }

  // --- THE ISOLATE MEMORY SPACE ---
  // This function runs in a completely separate thread.
  // It cannot access anything from the main app state.
  static void _isolateEntry(SendPort mainSendPort) {
    final backgroundReceivePort = ReceivePort();
    mainSendPort.send(backgroundReceivePort.sendPort);

    final engine = WordfeudEngine();

    backgroundReceivePort.listen((message) {
      if (message is Map) {
        if (message['type'] == 'INIT') {
          // Build the engine in the background
          engine.initializeFromRawData(
            dictionaryText: message['dictText'],
            letterValuesText: message['csvText'],
            modelOnnxBytes: message['modelOnnxBytes'],
            modelLabelsJson: message['modelLabelsJson'],
          );
          mainSendPort.send('READY');
        } else if (message['type'] == 'CHANGE_DICT') {
          // Swap the dictionary in the background
          engine.updateDictionary(
            dictionaryText: message['dictText'],
            letterValuesText: message['csvText'],
          );
          message['replyTo'].send('DONE');
        } else if (message['type'] == 'SOLVE') {
          // Solve the image in the background
          String path = message['path'];
          SendPort replyTo = message['replyTo'];

          try {
            final moves = engine.solveFromImage(path);
            final board = engine.lastParsedBoard;
            final rack = engine.lastParsedRack;
            replyTo.send(SolveResponse(moves, board, rack));
          } catch (e) {
            print("Background Isolate Error: $e");
            replyTo.send(SolveResponse([], [], [])); // Return empty on fail
          }
        }
      }
    });
  }

  /// Tells the background isolate to swap out the active dictionary.
  @override
  Future<void> changeDictionary(String dictText, String csvText) async {
    if (!isReady || _backgroundSendPort == null) return;

    final responsePort = ReceivePort();
    _backgroundSendPort!.send({
      'type': 'CHANGE_DICT',
      'dictText': dictText,
      'csvText': csvText,
      'replyTo': responsePort.sendPort,
    });

    // Wait for the background thread to finish building the new Trie
    await responsePort.first;
    responsePort.close();
  }
}
