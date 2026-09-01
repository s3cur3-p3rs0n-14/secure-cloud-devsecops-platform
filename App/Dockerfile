FROM python:3.11-alpine

RUN apk update && apk upgrade --no-cache

WORKDIR /app

COPY requirements.txt .
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir --upgrade -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]



