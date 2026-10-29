
from pathlib import Path
import numpy as np
import onnxruntime as ort
from PIL import Image

ROOT = Path(__file__).resolve().parent
TEST_DIR = ROOT / "dataset" / "test"
MODEL = ROOT / "model" / "cacao_model_v3_candidate.onnx"

CLASSES = [
    "unfermented",
    "partially_fermented",
    "well_fermented",
    "over_fermented",
]

if not MODEL.exists():
    raise SystemExit(f"Model not found: {MODEL}")

if not TEST_DIR.exists():
    raise SystemExit(f"Test folder not found: {TEST_DIR}")

session = ort.InferenceSession(
    str(MODEL),
    providers=["CPUExecutionProvider"]
)

input_name = session.get_inputs()[0].name
matrix = np.zeros((len(CLASSES), len(CLASSES)), dtype=int)
correct = 0
total = 0
misclassified = []
errors = []

for true_idx, label in enumerate(CLASSES):
    folder = TEST_DIR / label

    if not folder.is_dir():
        errors.append(f"Missing test folder: {folder}")
        continue

    for path in sorted(folder.iterdir()):
        if path.suffix.lower() not in (".jpg", ".jpeg", ".png"):
            continue

        try:
            with Image.open(path) as source:
                image = source.convert("RGB").resize((224, 224))

            pixels = np.asarray(image, dtype=np.float32) / 255.0
            tensor = pixels[None, ...]

            scores = session.run(
                None,
                {input_name: tensor.astype(np.float32)}
            )[0].reshape(-1)

            pred_idx = int(np.argmax(scores))
            matrix[true_idx, pred_idx] += 1
            total += 1

            if pred_idx == true_idx:
                correct += 1
            else:
                misclassified.append({
                    "file": str(path.relative_to(ROOT)),
                    "actual": label,
                    "predicted": CLASSES[pred_idx],
                    "confidence": float(scores[pred_idx]),
                })

        except Exception as exc:
            errors.append(f"{path}: {exc}")

print(f"Model: {MODEL.name}")
print(f"Images evaluated: {total}")

if total:
    print(f"Accuracy: {correct}/{total} = {correct / total:.2%}")

print("\nConfusion matrix (rows=actual, columns=predicted):")
print("Actual \\ Predicted | " + " | ".join(CLASSES))

for i, label in enumerate(CLASSES):
    print(f"{label:20} | " + " | ".join(str(v) for v in matrix[i]))

print("\nPer-class results:")

for i, label in enumerate(CLASSES):
    support = int(matrix[i].sum())
    class_correct = int(matrix[i, i])
    precision_den = int(matrix[:, i].sum())

    precision = class_correct / precision_den if precision_den else 0.0
    recall = class_correct / support if support else 0.0

    print(
        f"{label}: correct={class_correct}/{support}, "
        f"precision={precision:.2%}, recall={recall:.2%}"
    )

print(f"\nIncorrect predictions: {len(misclassified)}")

for item in misclassified:
    print(
        f"Actual: {item['actual']} | "
        f"Predicted: {item['predicted']} | "
        f"Score: {item['confidence']:.4f} | "
        f"File: {item['file']}"
    )

if errors:
    print(f"\nSkipped/errors: {len(errors)}")

    for error in errors[:10]:
        print("-", error)

# Save incorrect predictions for easier review.
report_path = ROOT / "misclassified_images.txt"

with report_path.open("w", encoding="utf-8") as report:
    for item in misclassified:
        report.write(
            f"Actual: {item['actual']} | "
            f"Predicted: {item['predicted']} | "
            f"Score: {item['confidence']:.4f} | "
            f"File: {item['file']}\n"
        )

print(f"\nError report saved to: {report_path}")
