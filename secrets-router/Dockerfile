# Multi-stage build for distroless Python image
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies to system location
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Final stage: use regular Python image instead of distroless for easier debugging
FROM python:3.11-slim

WORKDIR /app

# Copy Python dependencies from builder to system location
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code
COPY --from=builder /app/main.py .

# Set PYTHONPATH to include system packages
ENV PYTHONPATH=/usr/local/lib/python3.11/site-packages:$PYTHONPATH

# Run as non-root user
RUN useradd -m -u 65532 -s /bin/bash runner
USER runner

# Expose port
EXPOSE 8080

# Entry point
ENTRYPOINT ["python3", "main.py"]

