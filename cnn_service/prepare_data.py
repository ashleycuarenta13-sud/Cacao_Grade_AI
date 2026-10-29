from pathlib import Path
from collections import defaultdict
import hashlib
import random
from PIL import Image

BASE = Path(__file__).resolve().parent
SRC = BASE / "CacaoFermentations_dataset"
DST = BASE / "dataset_v2"
CLASSES = [
    "over_fermented",
    "partially_fermented",
    "unfermented",
    "well_fermented",
]
SEED = 42
IMAGE_SIZE = (224, 224)


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    if not SRC.is_dir():
        raise SystemExit(f"Source dataset not found: {SRC}")

    if DST.exists():
        raise SystemExit(
            f"{DST.name} already exists. Nothing was changed."
        )

    for class_name in CLASSES:
        if not (SRC / class_name).is_dir():
            raise SystemExit(f"Missing class folder: {class_name}")

    print("Checking exact duplicate images...")
    files_by_hash = defaultdict(list)

    for class_name in CLASSES:
        for path in sorted((SRC / class_name).iterdir()):
            if path.is_file() and path.suffix.lower() in {
                ".jpg", ".jpeg", ".png", ".bmp", ".webp"
            }:
                files_by_hash[sha256_file(path)].append(path)

    duplicate_groups = [
        paths for paths in files_by_hash.values() if len(paths) > 1
    ]
    excluded = {
        path for paths in duplicate_groups for path in paths
    }

    print(f"Duplicate groups found: {len(duplicate_groups)}")
    print(f"Files excluded as duplicates: {len(excluded)}")

    for number, paths in enumerate(duplicate_groups, start=1):
        print(f"\nDuplicate group {number}:")
        for path in paths:
            print(f"  {path.relative_to(SRC)}")

    clean_files = {}
    for class_name in CLASSES:
        clean_files[class_name] = [
            path
            for path in sorted((SRC / class_name).iterdir())
            if path.is_file()
            and path.suffix.lower() in {
                ".jpg", ".jpeg", ".png", ".bmp", ".webp"
            }
            and path not in excluded
        ]

        if len(clean_files[class_name]) < 3:
            raise SystemExit(
                f"Not enough clean images in {class_name}."
            )

    print("\nClean images per class:")
    for class_name, paths in clean_files.items():
        print(f"  {class_name}: {len(paths)}")

    random.seed(SEED)
    plan = {}

    for class_name, paths in clean_files.items():
        paths = paths.copy()
        random.shuffle(paths)

        total = len(paths)
        train_end = int(total * 0.70)
        valid_end = train_end + int(total * 0.15)

        plan[class_name] = {
            "train": paths[:train_end],
            "valid": paths[train_end:valid_end],
            "test": paths[valid_end:],
        }

    # Create the destination only after validation succeeds.
    for split in ("train", "valid", "test"):
        for class_name in CLASSES:
            (DST / split / class_name).mkdir(
                parents=True, exist_ok=True
            )

    try:
        for class_name in CLASSES:
            for split, paths in plan[class_name].items():
                target_dir = DST / split / class_name

                for index, source_path in enumerate(paths, start=1):
                    target_path = target_dir / f"{index:05d}.jpg"

                    with Image.open(source_path) as image:
                        image = image.convert("RGB")
                        image = image.resize(
                            IMAGE_SIZE, Image.Resampling.LANCZOS
                        )
                        image.save(
                            target_path, "JPEG", quality=90
                        )

        print("\nDataset created successfully:", DST)
        print("\nFinal image counts:")
        for split in ("train", "valid", "test"):
            print(f"\n{split}:")
            split_total = 0
            for class_name in CLASSES:
                count = len(list(
                    (DST / split / class_name).glob("*.jpg")
                ))
                split_total += count
                print(f"  {class_name}: {count}")
            print(f"  Total: {split_total}")

    except Exception:
        print(
            "\nERROR while creating dataset_v2. "
            "Some output files may have been created; "
            "do not rerun until the folder has been inspected."
        )
        raise


if __name__ == "__main__":
    main()
