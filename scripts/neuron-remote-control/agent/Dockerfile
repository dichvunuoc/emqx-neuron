FROM python:3.11-slim

WORKDIR /app

COPY scripts/neuron-remote-control/agent/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY scripts/neuron-remote-control/contracts /app/contracts
COPY scripts/neuron-remote-control/agent /app/agent

ENTRYPOINT ["python", "/app/agent/gateway_agent.py"]
