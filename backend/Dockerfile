# CacaoGrade AI - REST API
#
# Activity 3, Part A: "Backend language: Python 3.11" and "Backend runtime:
# Uvicorn (ASGI) inside a Docker container on Google Cloud Run".
#
# The image deliberately uses 3.11 even though a local dev venv may be a
# different patch level - the container is the artefact that gets deployed, so
# it is the one that has to match the document.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8000

WORKDIR /app

# Dependencies first so a source-only change does not invalidate this layer.
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# Cloud Run assigns $PORT at start-up; 8000 is the local `docker run` default.
EXPOSE 8000

# The API writes each cut-test photo into uploads/, so the process needs a
# directory it owns. Running non-root keeps a compromised request handler from
# being able to rewrite the image itself.
RUN useradd --create-home --uid 10001 cacao \
    && mkdir -p /app/uploads \
    && chown -R cacao:cacao /app
USER cacao

# /health answers 200 only once the database connection works, so this also
# proves the container reached PostgreSQL rather than merely booting.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import os,urllib.request as u,sys; sys.exit(u.urlopen('http://127.0.0.1:'+os.getenv('PORT','8000')+'/health', timeout=4).status != 200)"

# Database credentials, JWT_SECRET and CNN_SERVICE_URL arrive as environment
# configuration, never baked into the image - see .env.example and .dockerignore.
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
