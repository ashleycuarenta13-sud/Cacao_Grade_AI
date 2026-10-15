# CacaoGrade AI - CNN inference service
#
# Activity 3 calls this component /ml-service. It is the independently
# scalable half of the stack: the API forwards each photo here, so it can be
# redeployed or scaled on its own during harvest season without touching the
# REST API.
#
# Part A's "Python 3.11" applies here too.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8001

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# classifier.py looks for a trained model in model/. The directory is shipped
# empty on purpose - the coursework machine has no training dataset yet, so the
# service falls back to its colour-statistics baseline and answers
# "waiting" until a .keras/.h5/.onnx file is dropped in.
RUN useradd --create-home --uid 10002 cacao \
    && mkdir -p /app/model \
    && chown -R cacao:cacao /app
USER cacao

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import os,urllib.request as u,sys; sys.exit(u.urlopen('http://127.0.0.1:'+os.getenv('PORT','8001')+'/health', timeout=4).status != 200)"

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
