# ml-training

Training setup for a Wordfeud tile classifier using PyTorch.

This project trains a single shared CNN with three output heads:

1. `tile_type`: `EMPTY`, `MODIFIER`, `LETTER`
2. `modifier`: `DL`, `TL`, `DW`, `TW` (only when tile type is modifier)
3. `letter`: all discovered letter folders + `WILDCARD` (only when tile type is letter)

Current default dataset path is:

- `../flutter/assets/static/templates/`

## 1) Create and activate a virtual environment

From `ml-training/`:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

## 2) Train

Basic training run:

```bash
python train.py
```

Useful flags:

```bash
python train.py \
  --data-dir ../flutter/assets/static/templates \
  --epochs 60 \
  --batch-size 32 \
  --val-ratio 0.2 \
  --seed 42 \
  --output-dir checkpoints
```

Outputs are saved in a timestamped run directory, for example:

- `checkpoints/20260317-123456/best.pt`
- `checkpoints/20260317-123456/history.json`
- `checkpoints/20260317-123456/labels.json`

## 3) Evaluate

Run evaluation against the validation split:

```bash
python eval.py --checkpoint checkpoints/<run-id>/best.pt
```

Optional output path:

```bash
python eval.py \
  --checkpoint checkpoints/<run-id>/best.pt \
  --output runs/eval_report.json
```

## 4) Export for inference

Export TorchScript (recommended first integration artifact):

```bash
python export.py --checkpoint checkpoints/<run-id>/best.pt
```

This creates:

- `exports/tile_classifier.torchscript.pt`
- `exports/labels.json`

Export ONNX as well:

```bash
python export.py --checkpoint checkpoints/<run-id>/best.pt --export-onnx
```

## 5) Predict a single tile image

Run one-off inference on an image crop and print top-k predictions per head:

```bash
python predict.py \
  --checkpoint checkpoints/<run-id>/best.pt \
  --image ../flutter/assets/static/templates/A/<file>.png \
  --top-k 3
```

Output is JSON with:

- `predictions.tile_type` (top-k)
- `predictions.modifier` (top-k)
- `predictions.letter` (top-k)
- `best` (best label per head)

## 6) Predict using exported TorchScript

Run inference directly with the exported model artifact:

```bash
python predict_torchscript.py \
  --model exports/tile_classifier.torchscript.pt \
  --labels exports/labels.json \
  --image ../flutter/assets/static/templates/A/<file>.png \
  --image-size 40 \
  --top-k 3
```

This is useful to validate that export artifacts work before Flutter integration.

## Notes on current data

- The current dataset is class-imbalanced; training uses weighted sampling and class-weighted losses.
- `WILDCARD` is always included in the letter head label map. If no wildcard examples exist yet, that class remains present but untrained until data is added.
- For best generalization, add more screenshots from varied lighting, zoom levels, and board states.

## Suggested next data additions

- Add explicit wildcard tile samples under a folder named `WILDCARD`.
- Increase low-count classes (for example letters with <10 examples).
- Keep source images as PNG crops at roughly the same scale as current templates.
