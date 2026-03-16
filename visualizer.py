import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

def get_bg_color(cell_val):
    if cell_val == 'EMPTY' or cell_val == '': return (240, 240, 240)
    if cell_val == 'DL': return (255, 200, 150)
    if cell_val == 'TL': return (255, 100, 50)
    if cell_val == 'DW': return (150, 150, 255)
    if cell_val == 'TW': return (50, 50, 255)
    return (200, 230, 255)

def get_system_fonts():
    """Attempts to load a clean TTF font, checking common paths for Mac and Arch Linux."""
    possible_fonts = [
        # macOS paths
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        # Arch Linux paths
        "/usr/share/fonts/TTF/OpenSans-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/liberation/LiberationSans-Bold.ttf"
    ]

    for font_path in possible_fonts:
        try:
            large = ImageFont.truetype(font_path, 24)
            small = ImageFont.truetype(font_path, 14)
            return large, small
        except IOError:
            continue
            
    print("\nWARNING: No valid system font found. Falling back to default PIL font.")
    return ImageFont.load_default(), ImageFont.load_default()

def draw_board(board, move):
    board_size = 600
    grid_size = 15
    cell_size = board_size // grid_size

    # Create a blank white canvas
    img = np.ones((board_size, board_size, 3), dtype=np.uint8) * 255

    # --- 1. Draw all Rectangles (OpenCV) ---
    for r in range(grid_size):
        for c in range(grid_size):
            y1, x1 = r * cell_size, c * cell_size
            y2, x2 = y1 + cell_size, x1 + cell_size

            bg_color = get_bg_color(board[r][c])
            cv2.rectangle(img, (x1, y1), (x2, y2), bg_color, -1)
            cv2.rectangle(img, (x1, y1), (x2, y2), (0, 0, 0), 1)

    word = move['word']
    start_r = move['row']
    start_c = move['col']
    direction = move['direction']

    # Draw highlight rectangles for the new move
    for i, char in enumerate(word):
        r = start_r + i if direction == 'V' else start_r
        c = start_c + i if direction == 'H' else start_c

        if len(board[r][c]) > 1 or board[r][c] == 'EMPTY':
            y1, x1 = r * cell_size, c * cell_size
            y2, x2 = y1 + cell_size, x1 + cell_size

            cv2.rectangle(img, (x1, y1), (x2, y2), (0, 215, 255), -1)
            cv2.rectangle(img, (x1, y1), (x2, y2), (0, 0, 0), 1)

    # --- 2. Draw all Text (Pillow) ---
    # Convert OpenCV BGR to Pillow RGB
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(img_rgb)
    draw = ImageDraw.Draw(pil_img)
    
    # Pre-calculate coordinates covered by the new move
    move_coords = set()
    for i in range(len(word)):
        r = start_r + i if direction == 'V' else start_r
        c = start_c + i if direction == 'H' else start_c
        move_coords.add((r, c))
    
    font_large, font_small = get_system_fonts()

    # Draw base board text (existing tiles and bonus labels)
    for r in range(grid_size):
        for c in range(grid_size):
            cell_val = board[r][c]
            
            # Draw text ONLY if the square isn't EMPTY
            if cell_val != 'EMPTY':
                # targeted check: Is this a bonus label (TW, DL, etc. len > 1) 
                # that will be covered?
                is_bonus_label = len(cell_val) > 1
                will_be_covered = (r, c) in move_coords
                
                # If it's a bonus label being covered, skip drawing its text. 
                # Let the second loop draw the new tile's letter instead.
                if is_bonus_label and will_be_covered:
                    continue

                # Otherwise, proceed to draw text (existing A-Z tiles, 
                # or TW/DL on other squares)
                x1, y1 = c * cell_size, r * cell_size
                font = font_small if len(cell_val) > 1 else font_large
                
                # Center the text
                bbox = draw.textbbox((0, 0), cell_val, font=font)
                tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
                tx = x1 + (cell_size - tw) / 2
                ty = y1 + (cell_size - th) / 2 - bbox[1]
                
                draw.text((tx, ty), cell_val, font=font, fill=(0, 0, 0))

    # Draw the new move text
    for i, char in enumerate(word):
        r = start_r + i if direction == 'V' else start_r
        c = start_c + i if direction == 'H' else start_c

        if len(board[r][c]) > 1 or board[r][c] == 'EMPTY':
            x1, y1 = c * cell_size, r * cell_size
            
            # If it's a lowercase letter, it's a wildcard! Let's make it red to stand out.
            text_color = (255, 0, 0) if char.islower() else (0, 0, 0)
            display_char = char.upper()

            bbox = draw.textbbox((0, 0), display_char, font=font_large)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            tx = x1 + (cell_size - tw) / 2
            ty = y1 + (cell_size - th) / 2 - bbox[1]
            
            draw.text((tx, ty), display_char, font=font_large, fill=text_color)

    # Convert back to OpenCV BGR
    final_img = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)

    # --- 3. Render Window ---
    # Strip non-ASCII chars just for the OS window title bar to prevent OpenCV crashes
    safe_word = word.encode('ascii', 'ignore').decode('ascii')
    window_title = f"Suggestion: {safe_word} ({move.get('score', '?')} pts)"
    cv2.imshow(window_title, final_img)
    print("Showing visualizer. Press any key in the image window to close it...")
    cv2.waitKey(0)
    cv2.destroyAllWindows()