import cv2
import os
import uuid
import numpy as np
import hashlib

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
    existing_hashes = set()
    
    if not os.path.exists(base_path):
        return templates, existing_hashes
        
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
                        # Generate and store the hash for the loaded template
                        existing_hashes.add(hashlib.md5(tpl_img.tobytes()).hexdigest())
                        
    return templates, existing_hashes

def predict_cell(cell_img, templates, threshold=0.92):
    best_match = None
    highest_confidence = 0.0
    
    for label, tpl_list in templates.items():
        for tpl_img in tpl_list:
            tpl_img = cv2.resize(tpl_img, (cell_img.shape[1], cell_img.shape[0]))
            result = cv2.matchTemplate(cell_img, tpl_img, cv2.TM_CCOEFF_NORMED)
            _, max_val, _, _ = cv2.minMaxLoc(result)
            
            if max_val > highest_confidence:
                highest_confidence = max_val
                best_match = label
                
    if highest_confidence >= threshold:
        return best_match, highest_confidence
    return None, highest_confidence

# --- Main Configuration ---
base_dir = "templates"
examples_dir = "examples"

print("Loading existing templates and calculating checksums...")
existing_templates, existing_hashes = load_existing_templates(base_dir)

print("\nStarting interactive classification...")
print("- Press the corresponding letter key for a tile (A-Z).")
print("- Press the SPACEBAR for an empty standard board square.")
print("- Press '1' for Double Letter (DL)")
print("- Press '2' for Triple Letter (TL)")
print("- Press '3' for Double Word (DW) or the Center Star")
print("- Press '4' for Triple Word (TW)")
print("- Press ESC to save and quit entirely.")

quit_all = False

# Loop through every file in the examples directory
for filename in os.listdir(examples_dir):
    if quit_all:
        break
        
    if not filename.lower().endswith(('.png', '.jpg', '.jpeg')):
        continue

    img_path = os.path.join(examples_dir, filename)
    print(f"\n--- Processing: {filename} ---")
    
    image = cv2.imread(img_path)
    if image is None:
        print(f"Failed to load {filename}, skipping.")
        continue

    original = image.copy()
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 40, 255, cv2.THRESH_BINARY_INV)

    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        print("No contours found. Skipping image.")
        continue
        
    largest_contour = max(contours, key=cv2.contourArea)
    epsilon = 0.02 * cv2.arcLength(largest_contour, True)
    approx_corners = cv2.approxPolyDP(largest_contour, epsilon, True)

    # Make sure we actually found 4 corners before proceeding
    if len(approx_corners) != 4:
        print("Could not find exactly 4 corners for the board. Skipping image.")
        continue

    raw_points = np.float32([point[0] for point in approx_corners])
    ordered_pts1 = order_points(raw_points)

    board_size = 600 
    pts2 = np.float32([
        [0, 0], [board_size, 0], 
        [board_size, board_size], [0, board_size]
    ])

    matrix = cv2.getPerspectiveTransform(ordered_pts1, pts2)
    flat_board = cv2.warpPerspective(original, matrix, (board_size, board_size))
    flat_board_gray = cv2.cvtColor(flat_board, cv2.COLOR_BGR2GRAY)

    grid_size = 15
    cell_size = board_size // grid_size
    cells = []

    for row in range(grid_size):
        cell_row = []
        for col in range(grid_size):
            y_start = row * cell_size
            y_end = (row + 1) * cell_size
            x_start = col * cell_size
            x_end = (col + 1) * cell_size
            cell_img = flat_board_gray[y_start:y_end, x_start:x_end]
            cell_row.append(cell_img)
        cells.append(cell_row)

    flat_cells = [cell for row in cells for cell in row]

    for index, cell_img in enumerate(flat_cells):
        # Calculate checksum upfront
        cell_hash = hashlib.md5(cell_img.tobytes()).hexdigest()
        
        # 1. First, check if we already have this EXACT image saved
        if cell_hash in existing_hashes:
            print(f"[{index}/225] Skipping exact duplicate tile.")
            continue
            
        # 2. If it's not an exact pixel duplicate, try to auto-classify it
        predicted_label, confidence = predict_cell(cell_img, existing_templates, threshold=0.92)
        
        if predicted_label:
            print(f"[{index}/225] Auto-classified as {predicted_label} (Confidence: {confidence:.2f})")
            
            # Since it confidently classified it, we should save it as a new variation 
            # to make the model even more robust for future screenshots.
            folder_name = predicted_label
            
        else:
            # 3. Manual Classification Fallback
            display_img = cv2.resize(cell_img, (200, 200), interpolation=cv2.INTER_NEAREST)
            cv2.imshow("Classify Tile", display_img)
            key = cv2.waitKey(0)
            
            if key == 27: # ESC key
                print("Exiting classification completely.")
                quit_all = True
                break
                
            char = chr(key & 255).upper()
            
            if char == ' ': folder_name = 'EMPTY'
            elif char == '1': folder_name = 'DL'
            elif char == '2': folder_name = 'TL'
            elif char == '3': folder_name = 'DW'
            elif char == '4': folder_name = 'TW'
            elif char.isalpha(): folder_name = char
            else:
                print(f"[{index}/225] Invalid key pressed. Skipping this cell.")
                continue

        # --- Save the Image ---
        save_dir = os.path.join(base_dir, folder_name)
        os.makedirs(save_dir, exist_ok=True)
        
        filename = f"{uuid.uuid4().hex}.png"
        filepath = os.path.join(save_dir, filename)
        cv2.imwrite(filepath, cell_img)
        print(f"[{index}/225] Saved: {folder_name}/{filename}")
        
        # Add the new hash to our set so we don't save it again later
        existing_hashes.add(cell_hash)
        
        # Reload templates only when a new image is actually saved
        existing_templates, _ = load_existing_templates(base_dir)

cv2.destroyAllWindows()