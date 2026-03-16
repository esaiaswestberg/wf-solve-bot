import cv2
import sys
from parse import parse_wordfeud_board, print_board, load_existing_templates, parse_wordfeud_rack
from solver import find_all_moves
from scorer import rank_moves, load_point_values
from visualizer import draw_board

if __name__ == "__main__":
    base_dir = "templates"
    print("Loading templates into memory...")
    my_templates = load_existing_templates(base_dir)
    
    if not my_templates:
        print("Template loading failed. Exiting.")
        exit()

    dictionary_path = "dictionaries/swedish/swedish/dictionary.txt"
    with open(dictionary_path, 'r') as file:
        dictionary_array = file.readlines()
    
    points_dict = load_point_values("dictionaries/swedish/swedish/letter_values.csv")
    
    try:
        # Load image
        target_image = cv2.imread(sys.argv[1])

        # Parse the board
        board_state = parse_wordfeud_board(target_image, my_templates)
        print_board(board_state)

        # Parse the rack
        player_rack = parse_wordfeud_rack(target_image, my_templates)
        print("Player Rack:", player_rack)

        # Find all valid moves
        moves = find_all_moves(board_state, player_rack, dictionary_array)
        print("Valid Moves:", len(moves))

        # Score and rank moves
        top_moves = rank_moves(moves, board_state, points_dict)
        #print("Ranked Moves:", top_moves)

        # Visualize the best move
        if top_moves:
            best_move = top_moves[0]
            print(f"Visualizing the best move: {best_move['word']} for {best_move['score']} points.")
            draw_board(board_state, best_move)
        else:
            print("No valid moves found for this rack and board state.")
        
    except ValueError as e:
        print(f"Failed to parse board: {e}")