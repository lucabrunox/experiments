FROM alpine:latest

WORKDIR /app

RUN set -xe && \
  apk add python3 py3-pip tini

COPY requirements.txt .
RUN set -xe && \
  python3 -m venv venv && \
  source venv/bin/activate && \
  pip install -r requirements.txt

COPY . .

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/venv/bin/python", "/app/manage.py", "runserver", "0.0.0.0:8000"]