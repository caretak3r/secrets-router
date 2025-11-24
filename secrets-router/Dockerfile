# Multi-stage build for distroless Python image
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Copy application code
COPY main.py .

# Final stage: distroless Python image
FROM gcr.io/distroless/python3-debian12:latest

WORKDIR /app

# Copy Python dependencies from builder
COPY --from=builder /root/.local /root/.local

# Copy application code
COPY --from=builder /app/main.py .

# Set Python path to include user local packages
ENV PYTHONPATH=/root/.local/lib/python3.11/site-packages:$PYTHONPATH
ENV PATH=/root/.local/bin:$PATH

# Run as non-root user
USER 65532:65532

# Expose port
EXPOSE 8080

# Entry point
ENTRYPOINT ["python3", "main.py"]

