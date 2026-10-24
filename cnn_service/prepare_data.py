"""224x224 training copy -> cnn_service/dataset (needs_review excluded)."""
import argparse
from pathlib import Path
from PIL import Image

SRC = Path(r"C:\Users\Rico Respecia\Documents\Default Project\dataset")
DST = Path(__file__).resolve().parent / "dataset"
SPLITS = ("train", "valid", "test")
CLASSES = ("unfermented", "partially_fermented", "well_fermented", "over_fermented")
SIZE = 224

ap = argparse.ArgumentParser()
ap.add_argument("--src", default=str(SRC))
ap.add_argument("--cap", type=int, default=0, help="max train images per class (0 = all)")
a = ap.parse_args()

total = bytes_ = 0
for split in SPLITS:
    for cls in CLASSES:
        s, d = Path(a.src) / split / cls, DST / split / cls
        d.mkdir(parents=True, exist_ok=True)
        files = sorted(s.glob("*"))
        if split == "train" and a.cap:
            files = files[: a.cap]
        n = 0
        for f in files:
            if f.suffix.lower() not in (".jpg", ".jpeg", ".png"):
                continue
            out = d / f.name
            if not out.exists():
                with Image.open(f) as im:
                    im.convert("RGB").resize((SIZE, SIZE), Image.Resampling.BICUBIC) \
                      .save(out, "JPEG", quality=90)
                n += 1
            total += 1
            bytes_ += out.stat().st_size
        print(f"{split}/{cls:<20} {len(files)}")
print(f"TOTAL {total} files  ~{bytes_/1024/1024:.1f} MB  ->  {DST}")