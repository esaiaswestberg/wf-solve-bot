from __future__ import annotations

import random
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import torch
from PIL import Image
from torch.utils.data import DataLoader, Dataset, WeightedRandomSampler
from torchvision import transforms

from label_schema import (
    EMPTY_LABELS,
    MODIFIER_LABELS,
    LabelSchema,
    build_schema,
    folder_to_tile_type,
    normalize_letter_label,
)

IGNORE_INDEX = -100


@dataclass(frozen=True)
class TileSample:
    image_path: Path
    source_label: str


class TileDataset(Dataset):
    def __init__(
        self,
        samples: list[TileSample],
        schema: LabelSchema,
        image_size: int,
        train: bool,
    ) -> None:
        self.samples = samples
        self.schema = schema
        self.transform = self._build_transform(image_size=image_size, train=train)

    @staticmethod
    def _build_transform(image_size: int, train: bool) -> transforms.Compose:
        if train:
            return transforms.Compose(
                [
                    transforms.Grayscale(num_output_channels=1),
                    transforms.Resize((image_size, image_size)),
                    transforms.RandomAffine(
                        degrees=3,
                        translate=(0.05, 0.05),
                        scale=(0.95, 1.05),
                    ),
                    transforms.ColorJitter(brightness=0.15, contrast=0.15),
                    transforms.GaussianBlur(kernel_size=3, sigma=(0.1, 1.0)),
                    transforms.ToTensor(),
                ]
            )

        return transforms.Compose(
            [
                transforms.Grayscale(num_output_channels=1),
                transforms.Resize((image_size, image_size)),
                transforms.ToTensor(),
            ]
        )

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int) -> dict[str, torch.Tensor]:
        sample = self.samples[idx]
        image = Image.open(sample.image_path).convert("L")
        image_tensor = self.transform(image)

        tile_type = folder_to_tile_type(sample.source_label)
        tile_type_idx = self.schema.tile_type_to_idx[tile_type]

        modifier_idx = IGNORE_INDEX
        letter_idx = IGNORE_INDEX

        if sample.source_label in MODIFIER_LABELS:
            modifier_idx = self.schema.modifier_to_idx[sample.source_label]
        elif sample.source_label not in EMPTY_LABELS:
            normalized_letter = normalize_letter_label(sample.source_label)
            letter_idx = self.schema.letter_to_idx[normalized_letter]

        return {
            "image": image_tensor,
            "tile_type": torch.tensor(tile_type_idx, dtype=torch.long),
            "modifier": torch.tensor(modifier_idx, dtype=torch.long),
            "letter": torch.tensor(letter_idx, dtype=torch.long),
        }


def discover_samples(dataset_dir: Path) -> list[TileSample]:
    if not dataset_dir.exists():
        raise FileNotFoundError(f"Dataset directory not found: {dataset_dir}")

    samples: list[TileSample] = []
    for class_dir in sorted(dataset_dir.iterdir()):
        if not class_dir.is_dir():
            continue
        for image_path in sorted(class_dir.glob("*.png")):
            samples.append(TileSample(image_path=image_path, source_label=class_dir.name))

    if not samples:
        raise ValueError(f"No .png files found under {dataset_dir}")

    return samples


def split_samples(
    samples: list[TileSample],
    val_ratio: float,
    seed: int,
) -> tuple[list[TileSample], list[TileSample]]:
    by_label: dict[str, list[TileSample]] = {}
    for sample in samples:
        by_label.setdefault(sample.source_label, []).append(sample)

    rng = random.Random(seed)
    train: list[TileSample] = []
    val: list[TileSample] = []

    for label_samples in by_label.values():
        rng.shuffle(label_samples)
        if len(label_samples) < 2:
            train.extend(label_samples)
            continue

        n_val = max(1, int(round(len(label_samples) * val_ratio)))
        if n_val >= len(label_samples):
            n_val = len(label_samples) - 1

        val.extend(label_samples[:n_val])
        train.extend(label_samples[n_val:])

    rng.shuffle(train)
    rng.shuffle(val)
    return train, val


def compute_class_weights(labels: list[int], num_classes: int) -> torch.Tensor:
    counts = Counter(labels)
    weights = []
    for i in range(num_classes):
        count = counts.get(i, 0)
        weight = 0.0 if count == 0 else 1.0 / float(count)
        weights.append(weight)

    weights_tensor = torch.tensor(weights, dtype=torch.float32)
    non_zero = weights_tensor > 0
    if non_zero.any():
        weights_tensor[non_zero] = weights_tensor[non_zero] / weights_tensor[non_zero].mean()
    return weights_tensor


def compute_training_weights(dataset: TileDataset) -> dict[str, torch.Tensor]:
    tile_labels: list[int] = []
    modifier_labels: list[int] = []
    letter_labels: list[int] = []

    for sample in dataset.samples:
        tile_labels.append(dataset.schema.tile_type_to_idx[folder_to_tile_type(sample.source_label)])
        if sample.source_label in MODIFIER_LABELS:
            modifier_labels.append(dataset.schema.modifier_to_idx[sample.source_label])
        elif sample.source_label not in EMPTY_LABELS:
            letter_labels.append(dataset.schema.letter_to_idx[normalize_letter_label(sample.source_label)])

    return {
        "tile_type": compute_class_weights(tile_labels, len(dataset.schema.tile_type_to_idx)),
        "modifier": compute_class_weights(modifier_labels, len(dataset.schema.modifier_to_idx)),
        "letter": compute_class_weights(letter_labels, len(dataset.schema.letter_to_idx)),
    }


def build_weighted_sampler(dataset: TileDataset) -> WeightedRandomSampler:
    tile_type_labels = [
        dataset.schema.tile_type_to_idx[folder_to_tile_type(sample.source_label)]
        for sample in dataset.samples
    ]
    counts = Counter(tile_type_labels)
    sample_weights = [1.0 / counts[label] for label in tile_type_labels]
    weights_tensor = torch.tensor(sample_weights, dtype=torch.double)
    return WeightedRandomSampler(weights_tensor, len(weights_tensor), replacement=True)


def create_dataloaders(
    dataset_dir: Path,
    image_size: int,
    batch_size: int,
    val_ratio: float,
    seed: int,
    num_workers: int,
) -> tuple[DataLoader, DataLoader, LabelSchema, dict[str, torch.Tensor], dict[str, int]]:
    all_samples = discover_samples(dataset_dir)
    schema = build_schema({sample.source_label for sample in all_samples})
    train_samples, val_samples = split_samples(all_samples, val_ratio=val_ratio, seed=seed)

    if not val_samples:
        raise ValueError(
            "Validation split is empty. Add more samples or increase --val-ratio."
        )

    train_dataset = TileDataset(
        samples=train_samples,
        schema=schema,
        image_size=image_size,
        train=True,
    )
    val_dataset = TileDataset(
        samples=val_samples,
        schema=schema,
        image_size=image_size,
        train=False,
    )

    sampler = build_weighted_sampler(train_dataset)
    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        sampler=sampler,
        num_workers=num_workers,
        pin_memory=True,
    )
    val_loader = DataLoader(
        val_dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=num_workers,
        pin_memory=True,
    )

    class_weights = compute_training_weights(train_dataset)
    stats = {
        "total_samples": len(all_samples),
        "train_samples": len(train_samples),
        "val_samples": len(val_samples),
    }
    return train_loader, val_loader, schema, class_weights, stats
