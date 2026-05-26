FROM python:3.12-alpine

RUN apk add --no-cache gcc musl-dev libffi-dev openssl-dev

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY server.py .

RUN mkdir -p /app/keys

EXPOSE 8080

CMD ["python", "-u", "server.py"]
