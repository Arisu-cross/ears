FROM python:3.11-slim

# ffmpeg: 音频转码(TG 的 ogg/opus → wav);libsndfile1: librosa 读 wav 靠它
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . ./

# 基线与记录写在这里,部署时挂持久卷到 /app/data —— 换容器不丢
# (server.py 的 DATA 与 earsplus 的 voiceprint.json 都落在这个目录)
ENV DATA=/app/data
RUN mkdir -p /app/data

EXPOSE 8020
CMD ["sh", "-c", "uvicorn server:app --host 0.0.0.0 --port ${PORT:-8020}"]
