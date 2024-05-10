#!/bin/bash

pkill -f fastchat
# 默认参数
MODEL_PATH="/data/lama3/Meta-Llama-3-8B-Instruct"
GRADIO_PORT=7860
GPU="1"  # 默认使用第一个GPU
LOAD_8BIT=false  # 默认不加载8位模式
AUTH="./auth"

# 接受命令行参数
while getopts "m:p:g:a:l" opt; do
  case $opt in
    m) MODEL_PATH="$OPTARG"
    ;;
    p) GRADIO_PORT="$OPTARG"
    ;;
    g) GPU="$OPTARG"
    ;;
    a) AUTH="$OPTARG"
    ;;
    l) LOAD_8BIT=true
    ;;
    \?) echo "Usage: cmd [-m model_path] [-p gradio_port] [-g gpu_ids] [-l (load 8-bit)]"
            exit 1
    ;;
    :) echo "Option -$OPTARG requires an argument." >&2
            exit 1
    ;;
  esac
done
# 设置GPU环境变量
export CUDA_VISIBLE_DEVICES=$GPU

# 计算GPU数量
GPU_COUNT=$(echo $GPU | tr ',' '\n' | wc -l)

# API 服务器端口
API_PORT=$(($GRADIO_PORT + 10))

# server
nohup python3 -m fastchat.serve.controller > logs/server.log 2>&1 &
while [ `grep -c "Uvicorn running on" logs/server.log` -eq '0' ];do
    sleep 1s;
    echo "wait server running"
done
echo "server running"

# worker
WORKER_CMD="nohup python3 -m fastchat.serve.model_worker --model-name $MODEL_PATH --model-path $MODEL_PATH"
if [ $GPU_COUNT -gt 1 ]; then
    WORKER_CMD+=" --num-gpus $GPU_COUNT"
fi
if $LOAD_8BIT ; then
    WORKER_CMD+=" --load-8bit"
fi
WORKER_CMD+=" > logs/worker.log 2>&1 &"
echo $WORKER_CMD
eval $WORKER_CMD

while [ `grep -c "Uvicorn running on" logs/worker.log` -eq '0' ];do
    sleep 10s;
    echo "wait worker running"
done
echo "worker running"

# API 服务器
nohup python3 -m fastchat.serve.openai_api_server --host localhost --port $API_PORT > logs/api_server.log 2>&1 &
echo "API server running on port $API_PORT"

# webui
nohup python3 -m fastchat.serve.gradio_web_server --port $GRADIO_PORT --gradio-auth-path $AUTH > logs/web_server.log 2>&1 &
echo "Web server running on port $GRADIO_PORT, auth is $AUTH"


