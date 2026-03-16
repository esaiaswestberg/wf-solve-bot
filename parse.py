import cv2
import os
import numpy as np

def order_points(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect

def load_existing_templates(base_path):
    templates = {}
    if not os.path.exists(base_path):
        print(f"Error: Could not find the '{base_path}' directory.")
        return templates
        
    for folder_name in os.listdir(base_path):
        folder_path = os.path.join(base_path, folder_name)
        if os.path.isdir(folder_path):
            templates[folder_name] = []
            for file in os.listdir(folder_path):
                if file.endswith('.png'):
                    img_path = os.path.join(folder_path, file)
                    tpl_img = cv2.imread(img_path, 0)
                    if tpl_img is not None:
                        templates[folder_name].append(tpl_img)
    return templates

def predict_cell_absolute(cell_img, templates):
    best_match = "?"
    highest_confidence = -1.0
    
    for label, tpl_list in templates.items():
        for tpl_img in tpl_list:
            tpl_img = cv2.resize(tpl_img, (cell_img.shape[1], cell_img.shape[0]))
            result = cv2.matchTemplate(cell_img, tpl_img, cv2.TM_CCOEFF_NORMED)
            _, max_val, _, _ = cv2.minMaxLoc(result)
            
            if max_val > highest_confidence:
                highest_confidence = max_val
                best_match = label
                
    return best_match

def parse_wordfeud_board(image, templates):
    """
    Takes a cv2 image object of a Wordfeud screenshot and a dictionary of templates.
    Returns a 15x15 2D list representing the parsed board.
    """
    if image is None:
        raise ValueError("Provided image is None.")

    original = image.copy()
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 40, 255, cv2.THRESH_BINARY_INV)

    # Grid Detection
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        raise ValueError("Could not find any contours in the image.")
        
    largest_contour = max(contours, key=cv2.contourArea)
    epsilon = 0.02 * cv2.arcLength(largest_contour, True)
    approx_corners = cv2.approxPolyDP(largest_contour, epsilon, True)
    
    if len(approx_corners) != 4:
        raise ValueError("Could not identify exactly 4 corners for the board.")

    raw_points = np.float32([point[0] for point in approx_corners])
    ordered_pts1 = order_points(raw_points)

    # Perspective Warp
    board_size = 600 
    pts2 = np.float32([
        [0, 0], [board_size, 0], 
        [board_size, board_size], [0, board_size]
    ])

    matrix = cv2.getPerspectiveTransform(ordered_pts1, pts2)
    flat_board = cv2.warpPerspective(original, matrix, (board_size, board_size))
    flat_board_gray = cv2.cvtColor(flat_board, cv2.COLOR_BGR2GRAY)

    # Cell Slicing & Classification
    grid_size = 15
    cell_size = board_size // grid_size
    parsed_board = []

    for row in range(grid_size):
        board_row = []
        for col in range(grid_size):
            y_start = row * cell_size
            y_end = (row + 1) * cell_size
            x_start = col * cell_size
            x_end = (col + 1) * cell_size
            
            # Extract and immediately predict the cell
            current_cell = flat_board_gray[y_start:y_end, x_start:x_end]
            best_match = predict_cell_absolute(current_cell, templates)
            board_row.append(best_match)
            
        parsed_board.append(board_row)
        
    return parsed_board

def parse_wordfeud_rack(image, templates):
    """
    Isolates the bottom UI area of the screen, finds up to 7 player tiles, 
    and classifies them. Returns a list of strings (e.g., ['A', 'B', 'C']).
    """
    if image is None:
        raise ValueError("Provided image is None.")

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 40, 255, cv2.THRESH_BINARY_INV)

    # 1. Find the main board to establish our dynamic sizing and Y-cutoff
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        raise ValueError("Could not find any contours in the image.")
        
    largest_contour = max(contours, key=cv2.contourArea)
    x, y, w, h = cv2.boundingRect(largest_contour)
    
    # Calculate what a "valid tile" should look like mathematically
    expected_area = w * 155

    # 2. Crop the image to just the area BELOW the game board
    bottom_ui_top = y + h
    bottom_ui_gray = gray[bottom_ui_top:, :]
    _, ui_thresh = cv2.threshold(bottom_ui_gray, 40, 255, cv2.THRESH_BINARY_INV)

    # 3. Find all contours in the bottom UI
    # We use RETR_LIST here instead of RETR_EXTERNAL just in case the tiles 
    # are sitting inside a larger "rack container" contour.
    ui_contours, _ = cv2.findContours(ui_thresh, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

    rack_bounding_box = (0,0,0,0)

    for cnt in ui_contours:
        cnt_x, cnt_y, cnt_w, cnt_h = cv2.boundingRect(cnt)
        aspect_ratio = float(cnt_w) / cnt_h

        area = cnt_w * cnt_h
        
        # 4. Filter: Must be roughly square and close to the expected tile area
        is_square = 6.1 <= aspect_ratio <= 6.6
        is_right_size = (0.6 * expected_area) < area < (1.4 * expected_area)
        
        if is_square and is_right_size:
            # We add the bounding box to our list
            rack_bounding_box = (cnt_x, cnt_y, cnt_w, cnt_h)
    
    # 4. Split into seven equal tiles
    rack_img = gray[bottom_ui_top + rack_bounding_box[1]:bottom_ui_top + rack_bounding_box[1] + rack_bounding_box[3], 
                    rack_bounding_box[0]:rack_bounding_box[0] + rack_bounding_box[2]]
    
    tile_width = rack_bounding_box[2] // 7
    tiles = []
    for i in range(7):
        start_column = i * tile_width

        if i == 6:
            end_column = rack_bounding_box[2]
        else:
            end_column = (i + 1) * tile_width

        tile_img = rack_img[:, start_column:end_column]
        tiles.append(tile_img)

    # 5. Classify the Rack Tiles
    parsed_rack = []
    for tile in tiles:
        best_match = predict_cell_absolute(tile, templates)

        if best_match == 'EMPTY':
            parsed_rack.append("?")
        else:
            parsed_rack.append(best_match)


    return parsed_rack

def print_board(parsed_board):
    """Prints the 15x15 parsed board array in an aligned console grid."""
    for row in parsed_board:
        formatted_row = []
        for tile in row:
            if tile == 'EMPTY':
                formatted_row.append("..") 
            elif len(tile) == 1:
                formatted_row.append(f" {tile}") 
            else:
                formatted_row.append(tile) 
                
        print(" ".join(formatted_row))