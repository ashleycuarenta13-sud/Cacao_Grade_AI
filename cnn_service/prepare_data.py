
"""Prepare a reproducible train/valid/test dataset from class folders."""

import random
import shutil
from pathlib import Path
from PIL import Image

BASE = Path(__file__).resolve().parent
SRC = BASE / "CacaoFermentations_dataset"
DST = BASE / "dataset_v2"

CLASSES = (
    "unfermented",
    "partially_fermented",
    "well_fermented",
    "over_fermented",
)

SPLITS = ("train", "valid", "test")
SIZE = 224
SEED = 42
EXTENSIONS = {".jpg", ".jpeg", ".png"}

def main():
    if not SRC.is_dir():
        raise SystemExit(f"Source folder not found: {SRC}")

    # Do not overwrite an existing prepared dataset.
    if DST.exists():
        raise SystemExit(
            f"{DST} already exists. Rename or back it up first."
        )

    random.seed(SEED)
    counts = {split: {} for split in SPLITS}

    for cls in CLASSES:
        source_dir = SRC / cls

        if not source_dir.is_dir():
            raise SystemExit(f"Missing class folder: {source_dir}")

        files = sorted(
            f for f in source_dir.iterdir()
            if f.is_file() and f.suffix.lower() in EXTENSIONS
        )

        if len(files) < 3:
            raise SystemExit(f"Not enough images in class: {cls}")

        random.shuffle(files)

        total = len(files)
        train_end = int(total * 0.70)
        valid_end = int(total * 0.85)

        split_files = {
            "train": files[:train_end],
            "valid": files[train_end:valid_end],
            "test": files[valid_end:],
        }

        for split, selected_files in split_files.items():
            dest_dir = DST / split / cls
            dest_dir.mkdir(parents=True, exist_ok=True)

            for index, file in enumerate(selected_files):
                output_file = dest_dir / f"{index:05d}.jpg"

                with Image.open(file) as image:
                    image.convert("RGB").resize(
                        (SIZE, SIZE),
                        Image.Resampling.BICUBIC,
                    ).save(output_file, "JPEG", quality=90)

            counts[split][cls] = len(selected_files)

    print("\nDataset preparation complete.")
    print(f"Source: {SRC}")
    print(f"Destination: {DST}")
    print(f"Random seed: {SEED}")
    print("\nImage counts:")

    for split in SPLITS:
        print(f"\n{split}:")
        for cls in CLASSES:
            print(f"  {cls}: {counts[split][cls]}")
        print(f"  Total: {sum(counts[split].values())}")

    print(
        "\nNote: images are split randomly within each class. "
        "If multiple images come from the same original sample, "
        "a sample-level split may be needed to avoid data leakage."
    )

if __name__ == "__main__":
    main()
