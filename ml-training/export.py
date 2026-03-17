from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import torch
from torch import nn

from model import TileClassifier


class ExportWrapper(nn.Module):
    def __init__(self, model: TileClassifier) -> None:
        super().__init__()
        self.model = model

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        outputs = self.model(x)
        return outputs["tile_type"], outputs["modifier"], outputs["letter"]


def benchmark_inference(model: nn.Module, image_size: int, device: torch.device) -> float:
    model.eval()
    dummy = torch.randn(1, 1, image_size, image_size, device=device)
    with torch.no_grad():
        for _ in range(20):
            _ = model(dummy)
        start = time.perf_counter()
        for _ in range(200):
            _ = model(dummy)
        elapsed = time.perf_counter() - start
    return (elapsed / 200.0) * 1000.0


def main() -> None:
    parser = argparse.ArgumentParser(description="Export trained model for inference")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("exports"))
    parser.add_argument("--export-onnx", action="store_true")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    checkpoint = torch.load(args.checkpoint, map_location=device)
    schema = checkpoint["schema"]
    image_size = checkpoint["image_size"]

    model = TileClassifier(
        num_tile_types=len(schema["tile_type_to_idx"]),
        num_modifiers=len(schema["modifier_to_idx"]),
        num_letters=len(schema["letter_to_idx"]),
    ).to(device)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()
    export_model = ExportWrapper(model).to(device)
    export_model.eval()

    dummy = torch.randn(1, 1, image_size, image_size, device=device)
    traced = torch.jit.trace(export_model, dummy)
    ts_path = args.output_dir / "tile_classifier.torchscript.pt"
    traced.save(str(ts_path))

    metadata_path = args.output_dir / "labels.json"
    metadata_path.write_text(json.dumps(schema, indent=2, ensure_ascii=False) + "\n")

    benchmark_ms = benchmark_inference(export_model, image_size, device)
    print(f"Saved TorchScript model to: {ts_path}")
    print(f"Saved labels to: {metadata_path}")
    print(f"Approx single-image inference: {benchmark_ms:.3f} ms")

    if args.export_onnx:
        onnx_path = args.output_dir / "tile_classifier.onnx"
        torch.onnx.export(
            export_model,
            dummy,
            onnx_path,
            input_names=["image"],
            output_names=["tile_type", "modifier", "letter"],
            dynamic_axes={"image": {0: "batch"}},
            opset_version=17,
        )
        print(f"Saved ONNX model to: {onnx_path}")


if __name__ == "__main__":
    main()
