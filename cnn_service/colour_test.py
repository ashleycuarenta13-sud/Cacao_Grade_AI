"""Checks the colour scorer against synthetic cut-test colour patches."""
import io

import numpy as np
from PIL import Image

from classifier import predict

# Roughly the cut-test colour scale, from pale bean to over-fermented black.
PATCHES = [
    ("unfermented", (228, 216, 208)),
    ("partially_fermented", (196, 154, 112)),
    ("well_fermented", (122, 76, 44)),
    ("over_fermented", (52, 33, 24)),
]


def patch_jpeg(rgb: tuple[int, int, int]) -> bytes:
    image = Image.new("RGB", (256, 256), rgb)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


def main() -> None:
    hits = 0
    for expected, rgb in PATCHES:
        result = predict(patch_jpeg(rgb))
        label = result["predicted_class"]
        hits += label == expected
        print(
            f"RGB{str(rgb):16s} -> {label:20s} {result['confidence']:.4f} "
            f"expected={expected}"
        )

    print(f"\n{hits}/{len(PATCHES)} colour patches matched their stage.")


if __name__ == "__main__":
    main()
