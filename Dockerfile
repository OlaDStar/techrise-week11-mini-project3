FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install -r requirements.txt

COPY . .

USER root

ENV SECRET_KEY=SuperSecretPassword123

EXPOSE 5000

CMD ["python", "app/app.py"]
