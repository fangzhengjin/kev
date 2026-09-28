# Kev 推理服务镜像（CPU 版，amd64）
# 基础镜像自带 uv 与 Python 3.13，与仓库 .python-version 一致
# 注意：不用 uv sync —— uv.lock 在 Linux 平台锁的是 CUDA 版 torch，
# CPU 镜像改用 uv pip --torch-backend=cpu 从 download.pytorch.org/whl/cpu 解析
FROM ghcr.io/astral-sh/uv:python3.13-bookworm

WORKDIR /app

# torch CPU 版独立成层（版本范围与 pyproject 保持一致），改代码时无需重新下载
RUN uv pip install --system --torch-backend=cpu "torch>=2.6,<2.9"

# 项目代码与依赖
COPY . .
RUN uv pip install --system ".[serve]"

# 模型权重烘入镜像：Kev-0.8B adapter + Qwen3.5-0.8B-Base
# CI 在境外直连 huggingface.co；境内本地构建时传：
#   --build-arg HF_ENDPOINT=https://hf-mirror.com --build-arg HF_HUB_DISABLE_XET=1
# （hf-mirror 不代理 Xet 存储，境内构建必须禁用，否则 401）
ARG HF_ENDPOINT=https://huggingface.co
ARG HF_HUB_DISABLE_XET=0
RUN HF_ENDPOINT=$HF_ENDPOINT HF_HUB_DISABLE_XET=$HF_HUB_DISABLE_XET \
    python -c "from huggingface_hub import snapshot_download; snapshot_download('jaredpalmer/kev-0.8b', allow_patterns=['*.json', '*.safetensors', '*.pt', '*.txt', '*.jinja']); snapshot_download('Qwen/Qwen3.5-0.8B-Base')"

# 权重已内置，运行期离线读缓存；改 KEV_RUN 可换模型（新模型需运行期访问 HF）
ENV HF_HUB_OFFLINE=1 \
    KEV_RUN=jaredpalmer/kev-0.8b

EXPOSE 8009
# 必须绑 0.0.0.0：serve 默认 127.0.0.1，容器外无法访问
CMD ["sh", "-c", "python -m kev.serve --host 0.0.0.0 --port 8009 --run \"$KEV_RUN\""]
