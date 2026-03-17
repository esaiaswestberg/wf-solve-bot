from __future__ import annotations

import torch
from torch import nn


class TileClassifier(nn.Module):
    def __init__(
        self,
        num_tile_types: int,
        num_modifiers: int,
        num_letters: int,
    ) -> None:
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 32, kernel_size=3, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),
            nn.Conv2d(32, 64, kernel_size=3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),
            nn.Conv2d(64, 128, kernel_size=3, padding=1),
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),
            nn.AdaptiveAvgPool2d((1, 1)),
        )

        self.embedding = nn.Sequential(
            nn.Flatten(),
            nn.Linear(128, 128),
            nn.ReLU(inplace=True),
            nn.Dropout(p=0.2),
        )

        self.tile_type_head = nn.Linear(128, num_tile_types)
        self.modifier_head = nn.Linear(128, num_modifiers)
        self.letter_head = nn.Linear(128, num_letters)

    def forward(self, x: torch.Tensor) -> dict[str, torch.Tensor]:
        feats = self.features(x)
        emb = self.embedding(feats)
        return {
            "tile_type": self.tile_type_head(emb),
            "modifier": self.modifier_head(emb),
            "letter": self.letter_head(emb),
        }
