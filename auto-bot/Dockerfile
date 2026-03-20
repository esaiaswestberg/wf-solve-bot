FROM python:3.12-slim

# git is required to install the wordfeud API from GitHub
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY auto-bot/requirements.txt auto-bot/requirements.txt
RUN pip install --no-cache-dir -r auto-bot/requirements.txt

COPY auto-bot/ auto-bot/
COPY py-solver/dictionaries/ py-solver/dictionaries/

WORKDIR /app/auto-bot

ENV WF_DB_PATH=/data/wf_bot.db

CMD ["python", "bot.py"]
