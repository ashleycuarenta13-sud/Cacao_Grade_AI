"""CacaoGrade AI - CNN Inference Service.

Independent microservice (Activity 2, Part A - "External services"). It owns the
trained fermentation classifier so the model can be scaled, retrained, and
redeployed on its own schedule without touching the main API.

    POST /predict   multipart image -> {predicted_class, confidence, engine}
    GET  /health    readiness + which engine is active

Run:
    .venv\\Scripts\\python.exe -m uvicorn main:app --port 8001
"""
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from classifier import CLASS_LABELS, predict, status

app = FastAPI(title="CacaoGrade AI - CNN Inference Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ALLOWED_TYPES = {"image/jpeg", "image/jpg", "image/png"}
MAX_BYTES = 10 * 1024 * 1024


@app.get("/health")
def health():
    """Readiness probe - reports which engine answered the last load attempt."""
    info = status()
    return {
        "status": "success" if info["ready"] else "error",
        "service": "cnn-inference",
        **info,
    }


@app.post("/predict")
async def predict_image(file: UploadFile = File(...)):
    """Runs the fermentation-stage classifier on an uploaded cut-test photo."""
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=400, detail="Only JPG and PNG images are allowed."
        )

    image_bytes = await file.read()

    if not image_bytes:
        raise HTTPException(status_code=400, detail="The uploaded image is empty.")

    if len(image_bytes) > MAX_BYTES:
        raise HTTPException(status_code=400, detail="Image size must not exceed 10MB.")

    try:
        result = predict(image_bytes)
    except Exception as exc:
        raise HTTPException(
            status_code=422, detail=f"Could not read the image: {exc}"
        ) from exc

    return {
        "status": "success",
        "filename": file.filename,
        "classes": CLASS_LABELS,
        **result,
    }
