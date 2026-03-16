# solver.py

class TrieNode:
    def __init__(self):
        self.children = {}
        self.is_end_of_word = False

class Trie:
    def __init__(self):
        self.root = TrieNode()

    def insert(self, word):
        node = self.root
        for char in word:
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        node.is_end_of_word = True
    
    def search(self, word):
        """Returns True if the exact word exists in the Trie."""
        node = self.root
        for char in word:
            if char not in node.children:
                return False
            node = node.children[char]
        return node.is_end_of_word

def build_trie(dictionary_array):
    """Converts a standard array of strings into a searchable Trie."""
    trie = Trie()
    for word in dictionary_array:
        # Ensure everything is uppercase to match your OpenCV parsed board
        trie.insert(word.strip().upper()) 
    return trie

def is_empty(square_value):
    """
    A square is empty if it's not a single played letter (A-Z).
    Our template names for empty/bonus squares are 'EMPTY', 'DL', 'TL', 'DW', 'TW'.
    """
    return len(square_value) != 1

def get_cross_checks(board, trie):
    """
    Returns a 15x15 grid containing sets of valid letters for each empty square.
    """
    # Create a 15x15 grid of empty sets
    cross_checks = [[set() for _ in range(15)] for _ in range(15)]
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    for r in range(15):
        for c in range(15):
            # If there is already a tile here, it doesn't need a cross-check
            if not is_empty(board[r][c]):
                continue

            # 1. Look UP to find a prefix
            prefix = ""
            row_up = r - 1
            while row_up >= 0 and not is_empty(board[row_up][c]):
                prefix = board[row_up][c] + prefix
                row_up -= 1

            # 2. Look DOWN to find a suffix
            suffix = ""
            row_down = r + 1
            while row_down < 15 and not is_empty(board[row_down][c]):
                suffix += board[row_down][c]
                row_down += 1

            # 3. Determine valid letters
            if prefix == "" and suffix == "":
                # No tiles above or below; any letter is valid vertically
                cross_checks[r][c] = set(alphabet)
            else:
                # Tiles exist above or below; test all 26 letters
                valid_letters = set()
                for char in alphabet:
                    test_word = prefix + char + suffix
                    if trie.search(test_word):
                        valid_letters.add(char)
                
                cross_checks[r][c] = valid_letters

    return cross_checks

def left_part(board, row, anchor_col, limit, rack, current_node, prefix, cross_checks, results, start_col):
    # First, always try to extend right from the anchor using whatever prefix we've built so far
    extend_right(board, row, anchor_col, rack, current_node, prefix, cross_checks, results, start_col)
    
    # If we still have empty spaces to the left, try placing more tiles from the rack
    if limit > 0:
        # We use set(rack) so we don't test duplicate letters (like two 'E's) twice
        for char in set(rack): 
            if char in current_node.children:
                # Remove the tile from the rack to "play" it
                rack.remove(char)
                
                # Recurse deeper into the Trie and move one space left
                left_part(board, row, anchor_col, limit - 1, rack, current_node.children[char], prefix + char, cross_checks, results, start_col - 1)
                
                # "Backtrack": Put the tile back on the rack so the next loop can use it
                rack.append(char)

def extend_right(board, row, col, rack, current_node, prefix, cross_checks, results, start_col):
    # Base Case: We hit the right edge of the board
    if col == 15:
        if current_node.is_end_of_word:
            results.append((row, start_col, prefix))
        return
        
    if is_empty(board[row][col]):
        # If the Trie says this prefix is a valid word, log it!
        # (We will filter out invalid plays, like playing zero tiles, later)
        if current_node.is_end_of_word:
            results.append((row, start_col, prefix))
            
        # Try placing tiles from the rack onto this empty square
        for char in set(rack):
            # The letter must be valid in the Trie AND pass the vertical cross-check
            if char in current_node.children and char in cross_checks[row][col]:
                rack.remove(char)
                extend_right(board, row, col + 1, rack, current_node.children[char], prefix + char, cross_checks, results, start_col)
                rack.append(char) # Backtrack
    else:
        # There is already a tile on the board here! We MUST use it.
        existing_char = board[row][col]
        if existing_char in current_node.children:
            extend_right(board, row, col + 1, rack, current_node.children[existing_char], prefix + existing_char, cross_checks, results, start_col)

def get_anchors(board):
    anchors = []
    is_first_turn = True
    
    for r in range(15):
        for c in range(15):
            if not is_empty(board[r][c]):
                is_first_turn = False
                continue
            
            # Check up, down, left, right for adjacent tiles
            if (r > 0 and not is_empty(board[r-1][c])) or \
               (r < 14 and not is_empty(board[r+1][c])) or \
               (c > 0 and not is_empty(board[r][c-1])) or \
               (c < 14 and not is_empty(board[r][c+1])):
                anchors.append((r, c))
                
    if is_first_turn:
        anchors.append((7, 7)) # The center tile
        
    return anchors

def transpose_board(board):
    """Flips the board across its diagonal to check vertical moves using horizontal logic."""
    return [list(row) for row in zip(*board)]

def find_all_moves(board, rack, dictionary_array):
    print("Building dictionary Trie...")
    trie = build_trie(dictionary_array)
    
    # Ensure rack only contains valid uppercase characters (ignore empty strings from a short rack)
    clean_rack = [tile.upper() for tile in rack if tile.isalpha()]
    all_moves = []
    
    def scan_board(current_board, is_transposed):
        cross_checks = get_cross_checks(current_board, trie)
        anchors = get_anchors(current_board)
        results = []
        
        for r in range(15):
            # Isolate the anchors for just this specific row
            row_anchors = [c for (ar, c) in anchors if ar == r]
            
            for i, anchor_col in enumerate(row_anchors):
                # RULE 1: There is an existing tile immediately to the left
                if anchor_col > 0 and not is_empty(current_board[r][anchor_col - 1]):
                    # Read the existing word chunk backwards
                    prefix = ""
                    curr_c = anchor_col - 1
                    while curr_c >= 0 and not is_empty(current_board[r][curr_c]):
                        prefix = current_board[r][curr_c] + prefix
                        curr_c -= 1
                    
                    # Trace this existing prefix down the Trie
                    node = trie.root
                    valid_prefix = True
                    for char in prefix:
                        if char in node.children:
                            node = node.children[char]
                        else:
                            valid_prefix = False
                            break
                            
                    # If the prefix is a valid start to a word, jump to extend_right
                    if valid_prefix:
                        extend_right(current_board, r, anchor_col, clean_rack.copy(), node, prefix, cross_checks, results, anchor_col - len(prefix))
                
                # RULE 2: The space to the left is empty
                else:
                    # Calculate the limit: empty spaces up to the previous anchor or the board edge
                    prev_anchor = row_anchors[i - 1] if i > 0 else -1
                    limit = 0
                    curr_c = anchor_col - 1
                    while curr_c > prev_anchor and is_empty(current_board[r][curr_c]):
                        limit += 1
                        curr_c -= 1
                        
                    left_part(current_board, r, anchor_col, limit, clean_rack.copy(), trie.root, "", cross_checks, results, anchor_col)
        
        # Format the results and map coordinates back if we were scanning vertically
        for row, start_col, word in set(results):
            # Filter out single-letter words (must be 2+ letters in Wordfeud)
            if len(word) > 1:
                if is_transposed:
                    # Flip coordinates back: (row, start_col) -> (start_col, row)
                    all_moves.append({
                        'word': word, 
                        'row': start_col, 
                        'col': row, 
                        'direction': 'V'
                    })
                else:
                    all_moves.append({
                        'word': word, 
                        'row': row, 
                        'col': start_col, 
                        'direction': 'H'
                    })

    # --- Execute Horizontal Scan ---
    print("Scanning horizontally...")
    scan_board(board, is_transposed=False)
    
    # --- Execute Vertical Scan ---
    print("Scanning vertically...")
    transposed_board = transpose_board(board)
    scan_board(transposed_board, is_transposed=True)
    
    # Deduplicate in case a move was theoretically found via two different anchor paths
    unique_moves = { (m['word'], m['row'], m['col'], m['direction']): m for m in all_moves }
    
    return list(unique_moves.values())