"""Smoke test for the CNN inference service (no server required)."""
from pathlib import Path

from classifier import predict, status

IMAGES = Path(__file__).resolve().parent.parent / "frontend" / "assets" / "images"

CASES = [
    ("unfermented-cacao.png", "unfermented"),
    ("partially-fermented.png", "partially_fermented"),
    ("well-fermented.png", "well_fermented"),
    ("over-fermented.png", "over_fermented"),
]


def main() -> None:
    info = status()
    print(f"STATUS: ready={info['ready']} engine={info['engine']}")
    print(f"        {info['detail']}\n")

    hits = 0
    for name, expected in CASES:
        path = IMAGES / name
        if not path.exists():
            print(f"{name:28s} -> MISSING FILE")
            continue

        result = predict(path.read_bytes())
        label = result["predicted_class"]
        hits += label == expected
        print(
            f"{name:28s} -> {label:20s} "
            f"{result['confidence']:.4f}  expected={expected}"
        )

    print(f"\n{hits}/{len(CASES)} fixture images matched their label.")


if __name__ == "__main__":
    main()
