FROM python:3.11-alpine

RUN apk update && apk upgrade --no-cache

WORKDIR /app

COPY requirements.txt .
RUN addgroup -S appgroup && adduser -S -u 1001 appuser -G appgroup


RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir --upgrade -r requirements.txt

COPY app.py .
RUN chown -R appuser:appgroup /app 

USER 1001

EXPOSE 5000

CMD ["python", "app.py"]



