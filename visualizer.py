import cv2
import numpy as np

def get_bg_color(cell_val):
    """
    Returns the background BGR (Blue, Green, Red) color for a given square.
    Note: OpenCV uses BGR, not standard RGB!
    """
    if cell_val == 'EMPTY' or cell_val == '': 
        return (240, 240, 240)  # Off-white / Light gray
    if cell_val == 'DL': 
        return (255, 200, 150)  # Light Blue
    if cell_val == 'TL': 
        return (255, 100, 50)   # Dark Blue
    if cell_val == 'DW': 
        return (150, 150, 255)  # Light Red / Pink
    if cell_val == 'TW': 
        return (50, 50, 255)    # Dark Red
    
    # If it's a single letter, it's an existing tile on the board
    return (200, 230, 255)      # Tan / Wood color

def draw_board(board, move):
    """
    Generates an image of the board and overlays the suggested move.
    """
    board_size = 600
    grid_size = 15
    cell_size = board_size // grid_size

    # Create a blank white canvas (600x600 pixels, 3 color channels)
    img = np.ones((board_size, board_size, 3), dtype=np.uint8) * 255

    # --- 1. Draw the Base Board ---
    for r in range(grid_size):
        for c in range(grid_size):
            cell_val = board[r][c]
            
            # Calculate pixel coordinates for this cell
            y1, x1 = r * cell_size, c * cell_size
            y2, x2 = y1 + cell_size, x1 + cell_size

            # Draw the square background
            bg_color = get_bg_color(cell_val)
            cv2.rectangle(img, (x1, y1), (x2, y2), bg_color, -1)
            
            # Draw the black grid border
            cv2.rectangle(img, (x1, y1), (x2, y2), (0, 0, 0), 1) 

            # Draw the text (either 'DW', 'TL', or an existing letter)
            if cell_val != 'EMPTY':
                font = cv2.FONT_HERSHEY_SIMPLEX
                # Make multiplier text smaller than actual letter tiles
                font_scale = 0.5 if len(cell_val) > 1 else 0.8
                thickness = 1 if len(cell_val) > 1 else 2
                
                # Math to roughly center the text inside the square
                text_size = cv2.getTextSize(cell_val, font, font_scale, thickness)[0]
                tx = x1 + (cell_size - text_size[0]) // 2
                ty = y1 + (cell_size + text_size[1]) // 2
                
                cv2.putText(img, cell_val, (tx, ty), font, font_scale, (0, 0, 0), thickness)

    # --- 2. Overlay the Suggested Move ---
    word = move['word']
    start_r = move['row']
    start_c = move['col']
    direction = move['direction']

    for i, char in enumerate(word):
        # Calculate where this specific letter lands
        r = start_r + i if direction == 'V' else start_r
        c = start_c + i if direction == 'H' else start_c

        # We only want to highlight NEW tiles from our rack, 
        # not the existing tiles we are anchoring to.
        if len(board[r][c]) > 1 or board[r][c] == 'EMPTY':
            y1, x1 = r * cell_size, c * cell_size
            y2, x2 = y1 + cell_size, x1 + cell_size

            # Highlight new tiles in Bright Yellow
            highlight_color = (0, 215, 255) 
            cv2.rectangle(img, (x1, y1), (x2, y2), highlight_color, -1)
            cv2.rectangle(img, (x1, y1), (x2, y2), (0, 0, 0), 1)

            font = cv2.FONT_HERSHEY_SIMPLEX
            font_scale = 0.8
            thickness = 2
            
            text_size = cv2.getTextSize(char, font, font_scale, thickness)[0]
            tx = x1 + (cell_size - text_size[0]) // 2
            ty = y1 + (cell_size + text_size[1]) // 2
            
            # Draw the newly placed letter
            cv2.putText(img, char, (tx, ty), font, font_scale, (0, 0, 0), thickness)

    # --- 3. Render the Window ---
    # Add the score and word to the window title for context
    window_title = f"Suggestion: {word} ({move.get('score', '?')} pts)"
    cv2.imshow(window_title, img)
    
    print(f"Showing visualizer. Press any key in the image window to close it...")
    cv2.waitKey(0)
    cv2.destroyAllWindows()