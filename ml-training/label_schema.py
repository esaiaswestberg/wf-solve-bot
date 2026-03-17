from __future__ import annotations

from dataclasses import dataclass


MODIFIER_LABELS = ("DL", "TL", "DW", "TW")
EMPTY_LABELS = ("EMPTY",)
WILDCARD_ALIASES = ("WILDCARD", "WILD", "BLANK", "?")


@dataclass(frozen=True)
class LabelSchema:
    tile_type_to_idx: dict[str, int]
    modifier_to_idx: dict[str, int]
    letter_to_idx: dict[str, int]

    @property
    def idx_to_tile_type(self) -> dict[int, str]:
        return {v: k for k, v in self.tile_type_to_idx.items()}

    @property
    def idx_to_modifier(self) -> dict[int, str]:
        return {v: k for k, v in self.modifier_to_idx.items()}

    @property
    def idx_to_letter(self) -> dict[int, str]:
        return {v: k for k, v in self.letter_to_idx.items()}


def normalize_letter_label(folder_name: str) -> str:
    upper = folder_name.upper()
    if upper in WILDCARD_ALIASES:
        return "WILDCARD"
    return upper


def build_schema(available_labels: set[str]) -> LabelSchema:
    tile_types = {"EMPTY": 0, "MODIFIER": 1, "LETTER": 2}

    modifier_to_idx = {label: i for i, label in enumerate(MODIFIER_LABELS)}

    letter_labels = {
        normalize_letter_label(label)
        for label in available_labels
        if label not in MODIFIER_LABELS and label not in EMPTY_LABELS
    }
    letter_labels.add("WILDCARD")

    letter_to_idx = {label: i for i, label in enumerate(sorted(letter_labels))}

    return LabelSchema(
        tile_type_to_idx=tile_types,
        modifier_to_idx=modifier_to_idx,
        letter_to_idx=letter_to_idx,
    )


def folder_to_tile_type(folder_name: str) -> str:
    if folder_name in EMPTY_LABELS:
        return "EMPTY"
    if folder_name in MODIFIER_LABELS:
        return "MODIFIER"
    return "LETTER"
