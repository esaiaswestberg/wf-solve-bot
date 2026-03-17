from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.optim import AdamW
from tqdm import tqdm

from data import IGNORE_INDEX, create_dataloaders
from metrics import save_json, task_metrics
from model import TileClassifier


def set_seed(seed: int) -> None:
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)


def compute_loss(
    logits: dict[str, torch.Tensor],
    batch: dict[str, torch.Tensor],
    criteria: dict[str, nn.CrossEntropyLoss],
) -> tuple[torch.Tensor, dict[str, float]]:
    tile_loss = criteria["tile_type"](logits["tile_type"], batch["tile_type"])

    modifier_target = batch["modifier"]
    letter_target = batch["letter"]
    modifier_loss = criteria["modifier"](logits["modifier"], modifier_target)
    letter_loss = criteria["letter"](logits["letter"], letter_target)

    total = tile_loss + modifier_loss + letter_loss
    details = {
        "tile": float(tile_loss.item()),
        "modifier": float(modifier_loss.item()),
        "letter": float(letter_loss.item()),
    }
    return total, details


@torch.no_grad()
def evaluate(model: TileClassifier, loader, device: torch.device) -> dict[str, dict[str, float]]:
    model.eval()
    y_true = {"tile_type": [], "modifier": [], "letter": []}
    y_pred = {"tile_type": [], "modifier": [], "letter": []}

    for batch in loader:
        images = batch["image"].to(device, non_blocking=True)
        outputs = model(images)

        for task in ("tile_type", "modifier", "letter"):
            pred = outputs[task].argmax(dim=1).cpu()
            target = batch[task]
            if task == "tile_type":
                mask = torch.ones_like(target, dtype=torch.bool)
            else:
                mask = target != IGNORE_INDEX

            if mask.any():
                y_true[task].extend(target[mask].tolist())
                y_pred[task].extend(pred[mask].tolist())

    metrics = {task: task_metrics(y_true[task], y_pred[task]) for task in y_true}
    metrics["overall"] = {
        "macro_f1": float(
            np.mean(
                [
                    metrics["tile_type"]["macro_f1"],
                    metrics["modifier"]["macro_f1"],
                    metrics["letter"]["macro_f1"],
                ]
            )
        )
    }
    return metrics


def main() -> None:
    parser = argparse.ArgumentParser(description="Train Wordfeud tile classifier")
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path("./dataset"),
        help="Path to template class directories",
    )
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--image-size", type=int, default=40)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--val-ratio", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--patience", type=int, default=8)
    parser.add_argument("--output-dir", type=Path, default=Path("checkpoints"))
    args = parser.parse_args()

    set_seed(args.seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    train_loader, val_loader, schema, class_weights, stats = create_dataloaders(
        dataset_dir=args.data_dir,
        image_size=args.image_size,
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

    criteria = {
        "tile_type": nn.CrossEntropyLoss(weight=class_weights["tile_type"].to(device)),
        "modifier": nn.CrossEntropyLoss(
            weight=class_weights["modifier"].to(device), ignore_index=IGNORE_INDEX
        ),
        "letter": nn.CrossEntropyLoss(
            weight=class_weights["letter"].to(device), ignore_index=IGNORE_INDEX
        ),
    }

    optimizer = AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)

    run_name = time.strftime("%Y%m%d-%H%M%S")
    run_dir = args.output_dir / run_name
    run_dir.mkdir(parents=True, exist_ok=True)

    history = []
    best_score = -1.0
    best_epoch = -1
    epochs_without_improvement = 0

    print(f"Device: {device}")
    print(f"Samples: {stats}")
    print(f"Run dir: {run_dir}")

    for epoch in range(1, args.epochs + 1):
        model.train()
        running_loss = 0.0
        progress = tqdm(train_loader, desc=f"Epoch {epoch}/{args.epochs}", leave=False)

        for batch in progress:
            images = batch["image"].to(device, non_blocking=True)
            targets = {
                "tile_type": batch["tile_type"].to(device, non_blocking=True),
                "modifier": batch["modifier"].to(device, non_blocking=True),
                "letter": batch["letter"].to(device, non_blocking=True),
            }

            optimizer.zero_grad(set_to_none=True)
            outputs = model(images)
            loss, loss_parts = compute_loss(outputs, targets, criteria)
            loss.backward()
            optimizer.step()

            running_loss += loss.item()
            progress.set_postfix(loss=f"{loss.item():.4f}", tile=f"{loss_parts['tile']:.3f}")

        train_loss = running_loss / max(1, len(train_loader))
        val_metrics = evaluate(model, val_loader, device)

        epoch_metrics = {
            "epoch": epoch,
            "train_loss": train_loss,
            "val": val_metrics,
        }
        history.append(epoch_metrics)

        current_score = val_metrics["overall"]["macro_f1"]
        print(
            f"Epoch {epoch:03d} | train_loss={train_loss:.4f} "
            f"| val_tile_f1={val_metrics['tile_type']['macro_f1']:.4f} "
            f"| val_mod_f1={val_metrics['modifier']['macro_f1']:.4f} "
            f"| val_letter_f1={val_metrics['letter']['macro_f1']:.4f} "
            f"| val_overall_f1={current_score:.4f}"
        )

        if current_score > best_score:
            best_score = current_score
            best_epoch = epoch
            epochs_without_improvement = 0
            checkpoint_path = run_dir / "best.pt"
            torch.save(
                {
                    "model_state_dict": model.state_dict(),
                    "image_size": args.image_size,
                    "schema": {
                        "tile_type_to_idx": schema.tile_type_to_idx,
                        "modifier_to_idx": schema.modifier_to_idx,
                        "letter_to_idx": schema.letter_to_idx,
                    },
                    "metrics": epoch_metrics,
                    "seed": args.seed,
                },
                checkpoint_path,
            )
        else:
            epochs_without_improvement += 1

        if epochs_without_improvement >= args.patience:
            print(f"Early stopping after epoch {epoch} (patience {args.patience}).")
            break

    save_json({"history": history, "best_epoch": best_epoch, "best_score": best_score}, run_dir / "history.json")
    (run_dir / "labels.json").write_text(
        json.dumps(
            {
                "tile_type_to_idx": schema.tile_type_to_idx,
                "modifier_to_idx": schema.modifier_to_idx,
                "letter_to_idx": schema.letter_to_idx,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n"
    )

    print(f"Best epoch: {best_epoch} | best overall macro-F1: {best_score:.4f}")
    print(f"Saved checkpoint: {run_dir / 'best.pt'}")


if __name__ == "__main__":
    main()
