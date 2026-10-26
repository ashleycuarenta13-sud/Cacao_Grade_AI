"""Model loading and inference for the CacaoGrade AI CNN service.

Two engines are supported and both return the same payload, so neither the API
nor the Flutter client has to know which one is active:

1. ``cnn``        - a trained Keras/ONNX model dropped into ``model/``.
2. ``heuristic``  - a deterministic colour-statistics baseline used only while
                    the model is still being trained, so the Activity 2
                    Part D request-to-response trace stays runnable instead of
                    failing with 503.
"""
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
MODEL_FILES = ("cacao_model_v2.onnx", "cacao_model.keras", "cacao_model.h5", "cacao_model.onnx")
IMAGE_SIZE = 224  # cut-test photos are downscaled before inference

# (mean lightness, mean redness) expected per stage, following the cut-test
# colour scale: pale -> tan -> rich brown -> dark / cracked. Lightness carries
# most of the signal; the red/brown ratio separates the pale end.
_STAGE_CENTRES = {
    "unfermented": (0.85, 0.35),
    "partially_fermented": (0.60, 0.42),
    "well_fermented": (0.32, 0.50),
    "over_fermented": (0.14, 0.48),
}
_SIGMA = (0.13, 0.08)

# Distance (in sigma units) beyond which the photo matches no fermentation
# stage and is treated as "not a cacao bean". Tune with real photos.
NOT_CACAO_DISTANCE = 3.0

_model = None
_engine: Optional[str] = None
_load_error = ""


def _try_load() -> None:
    """Loads the trained model once, if one exists in ``model/``."""
    global _model, _engine, _load_error
    if _engine is not None:
        return

    for name in MODEL_FILES:
        path = MODEL_DIR / name
        if not path.exists():
            continue
        try:
            if path.suffix == ".onnx":
                import onnxruntime as ort  # type: ignore

                _model = ort.InferenceSession(
                    str(path), providers=["CPUExecutionProvider"]
                )
            else:
                from tensorflow import keras  # type: ignore

                _model = keras.models.load_model(str(path))
            _engine = "cnn"
            _load_error = ""
            return
        except Exception as exc:  # pragma: no cover - depends on local install
            _load_error = f"{path.name} could not be loaded: {exc}"

    _engine = "heuristic"


def status() -> dict:
    """Readiness probe used by ``GET /health``."""
    _try_load()
    return {
        "ready": _engine is not None,
        "engine": _engine,
        "classes": CLASS_LABELS,
        "detail": (
            "Trained CNN model loaded."
            if _engine == "cnn"
            else _load_error
            or (
                "No trained model found in model/. Using the built-in "
                "colour-statistics baseline so the pipeline stays runnable."
            )
        ),
    }


def _softmax(values) -> np.ndarray:
    arr = np.asarray(values, dtype=np.float64)
    arr = arr - arr.max()
    exp = np.exp(arr)
    return exp / exp.sum()


def _preprocess(image_bytes: bytes) -> dict:
    """Resize the photo and extract the colour features the scorer uses."""
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    image = image.resize((IMAGE_SIZE, IMAGE_SIZE))

    pixels = np.asarray(image, dtype=np.float32) / 255.0
    red, green, blue = pixels[..., 0], pixels[..., 1], pixels[..., 2]

    # Scale-invariant red/brown share, so dark beans still count as brown
    # instead of collapsing to a near-zero R-B difference.
    total = (red + green + blue).clip(1e-6)
    redness = red / total

    return {
        "pixels": pixels,
        "lightness": float(pixels.mean()),
        "redness": float(redness.mean()),
    }


def _predict_cnn(pixels: np.ndarray) -> tuple[str, float]:
    batch = np.expand_dims(pixels, axis=0)

    if hasattr(_model, "predict"):  # Keras model
        scores = _model.predict(batch, verbose=0)[0]
    else:  # onnxruntime session
        name = _model.get_inputs()[0].name
        scores = _model.run(None, {name: batch.astype(np.float32)})[0][0]

    scores = np.asarray(scores, dtype=np.float32).reshape(-1)
    if scores.shape[0] != len(CLASS_LABELS):
        raise ValueError(
            f"Model returned {scores.shape[0]} scores, expected {len(CLASS_LABELS)}."
        )

    probs = _softmax(scores)
    idx = int(np.argmax(probs))
    return CLASS_LABELS[idx], float(probs[idx])


def _predict_heuristic(features: dict) -> tuple[str, float]:
    """Gaussian score over (lightness, redness); rejects photos that match no stage."""
    x = (features["lightness"], features["redness"])

    dists = [
        math.sqrt(
            sum(
                ((x[i] - _STAGE_CENTRES[label][i]) / _SIGMA[i]) ** 2
                for i in range(2)
            )
        )
        for label in CLASS_LABELS
    ]

    print(f"lightness={x[0]:.3f} redness={x[1]:.3f} min_dist={min(dists):.2f}")
        
    if min(dists) > NOT_CACAO_DISTANCE:
        return "not_cacao", 0.0

    scores = np.array([math.exp(-0.5 * d * d) for d in dists], dtype=np.float64)
    probs = scores / scores.sum() if scores.sum() > 0 else np.full(len(scores), 1 / len(scores))
    idx = int(np.argmax(probs))
    return CLASS_LABELS[idx], float(probs[idx])

def predict(image_bytes: bytes) -> dict:
    """Runs the selected engine and returns the classification payload."""
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
    }
