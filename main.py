import cv2
import sys
from parse import parse_wordfeud_board, print_board, load_existing_templates

if __name__ == "__main__":
    # 1. Load templates into memory ONCE
    base_dir = "templates"
    print("Loading templates into memory...")
    my_templates = load_existing_templates(base_dir)
    
    if not my_templates:
        print("Template loading failed. Exiting.")
        exit()

    # 2. Load your image using cv2
    target_image = cv2.imread(sys.argv[1])
    
    # 3. Call your function
    try:
        final_board_array = parse_wordfeud_board(target_image, my_templates)
        
        # 4. Do something with the output
        print_board(final_board_array)
        
    except ValueError as e:
        print(f"Failed to parse board: {e}")