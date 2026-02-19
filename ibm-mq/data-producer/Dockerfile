FROM python:3.11-slim

WORKDIR /app

# Install MQ client libraries
RUN apt-get update && \
    apt-get install -y wget && \
    mkdir -p /opt/mqm && \
    cd /tmp && \
    wget https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist/9.3.0.0-IBM-MQC-Redist-LinuxX64.tar.gz && \
    tar -xzf 9.3.0.0-IBM-MQC-Redist-LinuxX64.tar.gz -C /opt/mqm && \
    rm 9.3.0.0-IBM-MQC-Redist-LinuxX64.tar.gz && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set MQ environment variables
ENV LD_LIBRARY_PATH=/opt/mqm/lib64:/opt/mqm/lib
ENV MQ_INSTALLATION_PATH=/opt/mqm

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy producer script
COPY producer.py .

# Run the producer
CMD ["python", "-u", "producer.py"]
