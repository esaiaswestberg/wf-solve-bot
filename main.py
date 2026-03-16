import cv2
import sys
from parse import parse_wordfeud_board, print_board, load_existing_templates, parse_wordfeud_rack
from solver import find_all_moves

if __name__ == "__main__":
    base_dir = "templates"
    print("Loading templates into memory...")
    my_templates = load_existing_templates(base_dir)
    
    if not my_templates:
        print("Template loading failed. Exiting.")
        exit()

    dictionary_path = "dictionaries/sowpods.txt"
    with open(dictionary_path, 'r') as file:
        dictionary_array = file.readlines()

    target_image = cv2.imread(sys.argv[1])
    
    try:
        final_board_array = parse_wordfeud_board(target_image, my_templates)
        print_board(final_board_array)

        player_rack = parse_wordfeud_rack(target_image, my_templates)
        print("Player Rack:", player_rack)

        movies = find_all_moves(final_board_array, player_rack, dictionary_array)
        print("Valid Moves:", movies)
        
    except ValueError as e:
        print(f"Failed to parse board: {e}")