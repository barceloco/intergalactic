FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client git sshpass \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir ansible==10.5.0 PyYAML==6.0.2

WORKDIR /repo
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
