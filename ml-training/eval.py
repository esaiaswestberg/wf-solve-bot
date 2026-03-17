from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from sklearn.metrics import classification_report

from data import IGNORE_INDEX, create_dataloaders
from metrics import confusion_matrix, save_json, task_metrics
from model import TileClassifier


@torch.no_grad()
def run_eval(model, loader, device, schema):
    model.eval()
    true_labels = {"tile_type": [], "modifier": [], "letter": []}
    pred_labels = {"tile_type": [], "modifier": [], "letter": []}

    for batch in loader:
        images = batch["image"].to(device, non_blocking=True)
        outputs = model(images)

        for task in ("tile_type", "modifier", "letter"):
            preds = outputs[task].argmax(dim=1).cpu()
            targets = batch[task]
            mask = torch.ones_like(targets, dtype=torch.bool) if task == "tile_type" else targets != IGNORE_INDEX
            if mask.any():
                true_labels[task].extend(targets[mask].tolist())
                pred_labels[task].extend(preds[mask].tolist())

    reports = {}
    metrics = {}

    for task in ("tile_type", "modifier", "letter"):
        metrics[task] = task_metrics(true_labels[task], pred_labels[task])
        if task == "tile_type":
            target_names = [k for k, _ in sorted(schema.tile_type_to_idx.items(), key=lambda kv: kv[1])]
            n_classes = len(schema.tile_type_to_idx)
        elif task == "modifier":
            target_names = [k for k, _ in sorted(schema.modifier_to_idx.items(), key=lambda kv: kv[1])]
            n_classes = len(schema.modifier_to_idx)
        else:
            target_names = [k for k, _ in sorted(schema.letter_to_idx.items(), key=lambda kv: kv[1])]
            n_classes = len(schema.letter_to_idx)

        if true_labels[task]:
            reports[task] = classification_report(
                true_labels[task],
                pred_labels[task],
                labels=list(range(n_classes)),
                target_names=target_names,
                zero_division=0,
            )
            metrics[task]["confusion_matrix"] = confusion_matrix(
                true_labels[task], pred_labels[task], n_classes=n_classes
            ).tolist()
        else:
            reports[task] = "No valid samples for this head in evaluation split."
            metrics[task]["confusion_matrix"] = []

    metrics["overall_macro_f1"] = (
        metrics["tile_type"]["macro_f1"]
        + metrics["modifier"]["macro_f1"]
        + metrics["letter"]["macro_f1"]
    ) / 3.0
    return reports, metrics


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate Wordfeud tile classifier")
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path("../flutter/assets/static/templates"),
    )
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--val-ratio", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--output", type=Path, default=Path("runs/eval_report.json"))
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    checkpoint = torch.load(args.checkpoint, map_location=device)

    _, val_loader, schema, _, _ = create_dataloaders(
        dataset_dir=args.data_dir,
        image_size=checkpoint["image_size"],
        batch_size=args.batch_size,
        val_ratio=args.val_ratio,
        seed=args.seed,
        num_workers=args.num_workers,
    )

    model = TileClassifier(
        num_tile_types=len(schema.tile_type_to_idx),
        num_modifiers=len(schema.modifier_to_idx),
        num_letters=len(schema.letter_to_idx),
    ).to(device)
    model.load_state_dict(checkpoint["model_state_dict"])

    reports, metrics = run_eval(model, val_loader, device, schema)

    print("\nEvaluation metrics")
    print(json.dumps(metrics, indent=2, ensure_ascii=False))
    print("\nDetailed reports")
    for task, report in reports.items():
        print(f"\n[{task}]\n{report}")

    save_json({"metrics": metrics, "reports": reports}, args.output)
    print(f"\nSaved evaluation report to: {args.output}")


if __name__ == "__main__":
    main()
