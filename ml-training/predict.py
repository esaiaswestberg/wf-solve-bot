from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from PIL import Image
from torchvision import transforms

from model import TileClassifier


def load_model(checkpoint_path: Path, device: torch.device):
    checkpoint = torch.load(checkpoint_path, map_location=device)
    schema = checkpoint["schema"]
    image_size = checkpoint["image_size"]

    model = TileClassifier(
        num_tile_types=len(schema["tile_type_to_idx"]),
        num_modifiers=len(schema["modifier_to_idx"]),
        num_letters=len(schema["letter_to_idx"]),
    ).to(device)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()
    return model, schema, image_size


def build_transform(image_size: int) -> transforms.Compose:
    return transforms.Compose(
        [
            transforms.Grayscale(num_output_channels=1),
            transforms.Resize((image_size, image_size)),
            transforms.ToTensor(),
        ]
    )


def topk_from_logits(logits: torch.Tensor, idx_to_label: dict[int, str], k: int) -> list[dict[str, float | str]]:
    probs = torch.softmax(logits, dim=0)
    values, indices = torch.topk(probs, k=min(k, probs.numel()))
    return [
        {"label": idx_to_label[int(i.item())], "probability": float(v.item())}
        for v, i in zip(values, indices, strict=True)
    ]


def invert_mapping(mapping: dict[str, int]) -> dict[int, str]:
    return {v: k for k, v in mapping.items()}


def main() -> None:
    parser = argparse.ArgumentParser(description="Run checkpoint inference on one tile image")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--top-k", type=int, default=3)
    args = parser.parse_args()

    if not args.image.exists():
        raise FileNotFoundError(f"Image not found: {args.image}")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model, schema, image_size = load_model(args.checkpoint, device)
    transform = build_transform(image_size)

    image = Image.open(args.image).convert("L")
    x = transform(image).unsqueeze(0).to(device)

    with torch.no_grad():
        outputs = model(x)

    tile_idx_to_label = invert_mapping(schema["tile_type_to_idx"])
    mod_idx_to_label = invert_mapping(schema["modifier_to_idx"])
    letter_idx_to_label = invert_mapping(schema["letter_to_idx"])

    tile_top = topk_from_logits(outputs["tile_type"][0].cpu(), tile_idx_to_label, args.top_k)
    mod_top = topk_from_logits(outputs["modifier"][0].cpu(), mod_idx_to_label, args.top_k)
    letter_top = topk_from_logits(outputs["letter"][0].cpu(), letter_idx_to_label, args.top_k)

    result = {
        "image": str(args.image),
        "predictions": {
            "tile_type": tile_top,
            "modifier": mod_top,
            "letter": letter_top,
        },
        "best": {
            "tile_type": tile_top[0]["label"] if tile_top else None,
            "modifier": mod_top[0]["label"] if mod_top else None,
            "letter": letter_top[0]["label"] if letter_top else None,
        },
    }

    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
