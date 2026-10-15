# Trained model goes here

The inference service picks up a trained model from this folder automatically:

| File | Runtime |
|---|---|
| `cacao_model.keras` | TensorFlow / Keras |
| `cacao_model.h5` | TensorFlow / Keras (legacy format) |
| `cacao_model.onnx` | ONNX Runtime |

The model must take an RGB image resized to **224 x 224**, normalised to `0..1`,
and return **4 scores** in this order:

1. `unfermented`
2. `partially_fermented`
3. `well_fermented`
4. `over_fermented`

Drop the file here and restart the service — `GET /health` will report
`"engine": "cnn"` instead of `"heuristic"`.

Until a trained model exists, the service runs a deterministic colour-statistics
baseline (`classifier.py`) so the upload pipeline, the API, and the Flutter
client can be exercised end to end. **The baseline is not a CNN** — replace it
before relying on the classifications.
