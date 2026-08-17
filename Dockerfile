FROM python:3.11-slim

WORKDIR /app

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir --upgrade setuptools wheel

COPY . .

ENV HOST=0.0.0.0

EXPOSE 5000

CMD ["python", "app/app.py"]
