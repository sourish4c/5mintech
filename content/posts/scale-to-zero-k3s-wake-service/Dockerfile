# Multi-stage so the runtime image is just the app + a slim Python base.
FROM python:3.12-slim AS build
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=build /install /usr/local
COPY app.py .
EXPOSE 8080
# python:3.12-slim ships without a 'nobody' alt-uid, so create one before
# switching to it (otherwise the container fails to start with code 137).
RUN groupadd -g 65532 wake \
 && useradd  -u 65532 -g 65532 -M -s /usr/sbin/nologin wake
USER 65532:65532
CMD ["python", "app.py"]
