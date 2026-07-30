FROM python:3.11-slim

# ffmpeg: 音频转码(TG 的 ogg/opus → wav);libsndfile1: librosa 读 wav 靠它;
# curl: 第二阶段下载 onnx 模型用(WITH_ONNX=1 时)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg libsndfile1 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# ── 第二阶段:声纹锁 + 环境音识别(默认关闭)────────────────────────────────
# 构建时加 --build-arg WITH_ONNX=1 才启用:装 onnxruntime 并下载两个 onnx 模型。
# 不加则镜像保持轻量(约省 95MB + 构建时间),earsplus 会因模型缺失而优雅关闭,
# 只跑转写 + 语气分析。这样第一阶段和第二阶段镜像可以从同一个 Dockerfile 出。
ARG WITH_ONNX=0
RUN if [ "$WITH_ONNX" = "1" ]; then \
        set -eux; \
        pip install --no-cache-dir onnxruntime; \
        mkdir -p models; \
        curl -fSL -o models/yamnet.onnx \
            https://huggingface.co/zeropointnine/yamnet-onnx/resolve/main/yamnet.onnx; \
        curl -fSL -o models/yamnet_class_map.csv \
            https://huggingface.co/zeropointnine/yamnet-onnx/resolve/main/yamnet_class_map.csv; \
        curl -fSL -o models/ecapa.onnx \
            https://huggingface.co/losfen/spkrec-ecapa-voxceleb-onnx/resolve/main/embedding_model.onnx; \
        python -c "import onnxruntime as ort; \
            ort.InferenceSession('models/yamnet.onnx', providers=['CPUExecutionProvider']); \
            ort.InferenceSession('models/ecapa.onnx', providers=['CPUExecutionProvider']); \
            print('[build] onnx models load OK')"; \
    else \
        echo "[build] WITH_ONNX=0 — 声纹/环境音关闭,只跑转写+语气"; \
    fi

COPY . ./

# 基线与记录写在这里,部署时挂持久卷到 /app/data —— 换容器不丢
# (server.py 的 DATA 与 earsplus 的 voiceprint.json 都落在这个目录)
ENV DATA=/app/data
RUN mkdir -p /app/data

EXPOSE 8020
CMD ["sh", "-c", "uvicorn server:app --host 0.0.0.0 --port ${PORT:-8020}"]
