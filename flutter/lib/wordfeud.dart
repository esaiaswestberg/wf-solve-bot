import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
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
  Map<String, List<cv.Mat>> _templates = {};

  bool get isReady => _pointValues.isNotEmpty && _templates.isNotEmpty;

  // --- ASSET LOADING HELPER ---

  /// Reads dictionary, CSV, and image templates directly from Flutter's rootBundle.
  ///
  /// [templateAssetPaths] should look like:
  /// { 'A': ['assets/templates/A/1.png', 'assets/templates/A/2.png'], 'EMPTY': [...] }
  Future<void> initializeFromAssets({
    required String dictionaryPath,
    required String letterValuesPath,
    required Map<String, List<String>> templateAssetPaths,
  }) async {
    // 1. Load Dictionary
    String dictText = await rootBundle.loadString(dictionaryPath);
    List<String> dictWords = dictText
        .split('\n')
        .where((w) => w.trim().isNotEmpty)
        .toList();

    // 2. Load Letter Values (CSV)
    String csvText = await rootBundle.loadString(letterValuesPath);
    Map<String, int> points = {};
    for (var line in csvText.split('\n')) {
      var parts = line.split(',');
      if (parts.length >= 2) {
        points[parts[0].trim().toUpperCase()] =
            int.tryParse(parts[1].trim()) ?? 0;
      }
    }

    // 3. Load Templates into OpenCV Mats
    Map<String, List<cv.Mat>> loadedTemplates = {};
    for (var entry in templateAssetPaths.entries) {
      String label = entry.key;
      List<cv.Mat> mats = [];
      for (var path in entry.value) {
        ByteData data = await rootBundle.load(path);
        Uint8List bytes = data.buffer.asUint8List();

        // Decode bytes directly into a grayscale Mat
        cv.Mat mat = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
        if (!mat.isEmpty) {
          mats.add(mat);
        }
      }
      loadedTemplates[label] = mats;
    }

    // Pass the decoded assets into memory
    _initialize(
      dictionaryWords: dictWords,
      letterValues: points,
      preloadedTemplates: loadedTemplates,
    );
  }

  void _initialize({
    required List<String> dictionaryWords,
    required Map<String, int> letterValues,
    required Map<String, List<cv.Mat>> preloadedTemplates,
  }) {
    for (var word in dictionaryWords) {
      _dictionaryTrie.insert(word.trim());
    }
    _pointValues = letterValues;
    _pointValues['?'] = 0; // Wildcard
    _templates = preloadedTemplates;
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

    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        cv.Mat cell = flatGray.region(
          cv.Rect(c * cellSize, r * cellSize, cellSize, cellSize),
        );
        parsedBoard[r][c] = _predictCell(cell);
        cell.dispose();
      }
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
    List<String> parsedRack = [];
    for (var tile in tiles) {
      String bestMatch = _predictCell(tile);

      if (bestMatch == 'EMPTY') {
        parsedRack.add("?");
      } else {
        parsedRack.add(bestMatch);
      }
      tile.dispose(); // Free memory
    }

    // Cleanup Mats
    gray.dispose();
    thresh.dispose();
    bottomUiGray.dispose();
    uiThresh.dispose();
    rackImg.dispose();

    return parsedRack;
  }

  String _predictCell(cv.Mat cell) {
    String bestMatch = "?";
    double highestConfidence = -1.0;

    _templates.forEach((label, tplList) {
      for (var tpl in tplList) {
        cv.Mat resizedTpl = cv.resize(tpl, (cell.cols, cell.rows));

        cv.Mat result = cv.matchTemplate(cell, resizedTpl, cv.TM_CCOEFF_NORMED);
        var minMaxLocResult = cv.minMaxLoc(result);

        if (minMaxLocResult.$2 > highestConfidence) {
          highestConfidence = minMaxLocResult.$2;
          bestMatch = label;
        }
        resizedTpl.dispose();
        result.dispose();
      }
    });

    return bestMatch;
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
        .where((t) => RegExp(r'[A-Za-z?]').hasMatch(t))
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
}
