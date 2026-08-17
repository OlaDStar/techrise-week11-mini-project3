FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install -r requirements.txt

COPY . .

ENV HOST=0.0.0.0

EXPOSE 5000

CMD ["python", "app/app.py"]
