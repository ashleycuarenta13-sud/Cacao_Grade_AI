
"""Model loading and inference for the CacaoGrade AI CNN service."""

from __future__ import annotations

import io
import math
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image


# Fermentation stages, in cut-test order.
CLASS_LABELS = [
    "unfermented",
    "partially_fermented",
    "well_fermented",
    "over_fermented",
]

MODEL_DIR = Path(__file__).resolve().parent / "model"

# Load the newly trained v3 model first.
MODEL_FILES = (
    "cacao_model_v3_candidate.onnx",
    "cacao_model_v2.onnx",
    "cacao_model.keras",
    "cacao_model.h5",
    "cacao_model.onnx",
)

IMAGE_SIZE = 224

# Used only if no trained model can be loaded.
_STAGE_CENTRES = {
    "unfermented": (0.85, 0.35),
    "partially_fermented": (0.60, 0.42),
    "well_fermented": (0.32, 0.50),
    "over_fermented": (0.14, 0.48),
}

_SIGMA = (0.13, 0.08)
NOT_CACAO_DISTANCE = 3.0

_model = None
_engine: Optional[str] = None
_load_error = ""
_model_path = ""


def _try_load() -> None:
    """Load the first available model in MODEL_FILES."""
    global _model, _engine, _load_error, _model_path

    if _engine is not None:
        return

    for name in MODEL_FILES:
        path = MODEL_DIR / name

        if not path.exists():
            continue

        try:
            if path.suffix == ".onnx":
                import onnxruntime as ort

                _model = ort.InferenceSession(
                    str(path),
                    providers=["CPUExecutionProvider"],
                )
            else:
                from tensorflow import keras

                _model = keras.models.load_model(path)

            _model_path = path.name
            _engine = "cnn"
            _load_error = ""
            return

        except Exception as exc:
            _load_error = f"{path.name} could not be loaded: {exc}"

    _model = None
    _model_path = ""
    _engine = "heuristic"


def status() -> dict:
    """Readiness probe used by GET /health."""
    _try_load()

    if _engine == "cnn":
        detail = f"Trained CNN model loaded: {_model_path}"
    else:
        detail = (
            _load_error
            or "No trained model could be loaded. "
            "Using the colour-statistics baseline."
        )

    return {
        "ready": _engine is not None,
        "engine": _engine,
        "model_file": _model_path or None,
        "classes": CLASS_LABELS,
        "detail": detail,
    }


def _softmax(values) -> np.ndarray:
    """Convert model scores into probabilities."""
    arr = np.asarray(values, dtype=np.float64)
    arr = arr - arr.max()
    exp = np.exp(arr)
    return exp / exp.sum()


def _preprocess(image_bytes: bytes) -> dict:
    """Resize an image and extract basic colour features."""
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    image = image.resize((IMAGE_SIZE, IMAGE_SIZE))

    pixels = np.asarray(image, dtype=np.float32) / 255.0

    red = pixels[..., 0]
    green = pixels[..., 1]
    blue = pixels[..., 2]

    total = (red + green + blue).clip(1e-6)
    redness = red / total

    return {
        "pixels": pixels,
        "lightness": float(pixels.mean()),
        "redness": float(redness.mean()),
    }


def _predict_cnn(pixels: np.ndarray) -> tuple[str, float]:
    """Run inference using the loaded CNN model."""
    batch = np.expand_dims(pixels, axis=0).astype(np.float32)

    if hasattr(_model, "predict"):
        # Keras model
        scores = _model.predict(batch, verbose=0)[0]
    else:
        # ONNX Runtime model
        input_name = _model.get_inputs()[0].name
        scores = _model.run(
            None,
            {input_name: batch},
        )[0][0]

    scores = np.asarray(scores, dtype=np.float32).reshape(-1)

    if scores.shape[0] != len(CLASS_LABELS):
        raise ValueError(
            f"Model returned {scores.shape[0]} scores, "
            f"expected {len(CLASS_LABELS)}."
        )

    probabilities = _softmax(scores)
    index = int(np.argmax(probabilities))

    return (
        CLASS_LABELS[index],
        float(probabilities[index]),
    )


def _predict_heuristic(features: dict) -> tuple[str, float]:
    """Fallback colour-based prediction when no CNN model loads."""
    values = (
        features["lightness"],
        features["redness"],
    )

    distances = [
        math.sqrt(
            sum(
                (
                    (values[i] - _STAGE_CENTRES[label][i])
                    / _SIGMA[i]
                ) ** 2
                for i in range(2)
            )
        )
        for label in CLASS_LABELS
    ]

    print(
        f"lightness={values[0]:.3f} "
        f"redness={values[1]:.3f} "
        f"min_dist={min(distances):.2f}"
    )

    if min(distances) > NOT_CACAO_DISTANCE:
        return "not_cacao", 0.0

    scores = np.array(
        [math.exp(-0.5 * distance * distance) for distance in distances],
        dtype=np.float64,
    )

    total = scores.sum()

    if total > 0:
        probabilities = scores / total
    else:
        probabilities = np.full(
            len(scores),
            1 / len(scores),
        )

    index = int(np.argmax(probabilities))

    return (
        CLASS_LABELS[index],
        float(probabilities[index]),
    )


def predict(image_bytes: bytes) -> dict:
    """Classify an image and return the prediction payload."""
    _try_load()
    features = _preprocess(image_bytes)

    if _engine == "cnn":
        label, confidence = _predict_cnn(features["pixels"])
    else:
        label, confidence = _predict_heuristic(features)

    return {
        "predicted_class": label,
        "confidence": round(confidence, 4),
        "engine": _engine,
        "model_file": _model_path or None,
    }