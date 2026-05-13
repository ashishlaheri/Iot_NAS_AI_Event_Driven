FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl libgl1 libglib2.0-0t64 libsm6 libxext6 libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Install CPU-only PyTorch FIRST (saves ~3GB vs CUDA version)
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Then install ultralytics (will use the already-installed CPU torch)
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download YOLOv8-Nano model at build time
RUN python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')" \
    && mkdir -p /app/models && mv yolov8n.pt /app/models/ 2>/dev/null || true

COPY main.py .
RUN mkdir -p /app/uploads /app/models

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
