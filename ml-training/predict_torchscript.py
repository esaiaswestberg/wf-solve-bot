from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from PIL import Image
from torchvision import transforms


def invert_mapping(mapping: dict[str, int]) -> dict[int, str]:
    return {v: k for k, v in mapping.items()}


def topk_from_logits(logits: torch.Tensor, idx_to_label: dict[int, str], k: int) -> list[dict[str, float | str]]:
    probs = torch.softmax(logits, dim=0)
    values, indices = torch.topk(probs, k=min(k, probs.numel()))
    return [
        {"label": idx_to_label[int(i.item())], "probability": float(v.item())}
        for v, i in zip(values, indices, strict=True)
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Run TorchScript inference on one tile image")
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("exports/tile_classifier.torchscript.pt"),
    )
    parser.add_argument("--labels", type=Path, default=Path("exports/labels.json"))
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--image-size", type=int, default=40)
    parser.add_argument("--top-k", type=int, default=3)
    args = parser.parse_args()

    if not args.model.exists():
        raise FileNotFoundError(f"Model not found: {args.model}")
    if not args.labels.exists():
        raise FileNotFoundError(f"Labels file not found: {args.labels}")
    if not args.image.exists():
        raise FileNotFoundError(f"Image not found: {args.image}")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = torch.jit.load(str(args.model), map_location=device)
    model.eval()

    schema = json.loads(args.labels.read_text())
    tile_idx_to_label = invert_mapping(schema["tile_type_to_idx"])
    mod_idx_to_label = invert_mapping(schema["modifier_to_idx"])
    letter_idx_to_label = invert_mapping(schema["letter_to_idx"])

    transform = transforms.Compose(
        [
            transforms.Grayscale(num_output_channels=1),
            transforms.Resize((args.image_size, args.image_size)),
            transforms.ToTensor(),
        ]
    )

    image = Image.open(args.image).convert("L")
    x = transform(image).unsqueeze(0).to(device)

    with torch.no_grad():
        tile_logits, mod_logits, letter_logits = model(x)

    tile_top = topk_from_logits(tile_logits[0].cpu(), tile_idx_to_label, args.top_k)
    mod_top = topk_from_logits(mod_logits[0].cpu(), mod_idx_to_label, args.top_k)
    letter_top = topk_from_logits(letter_logits[0].cpu(), letter_idx_to_label, args.top_k)

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
