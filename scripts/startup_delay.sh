#!/bin/bash

# Define the delay in seconds (adjust this based on your ZK session timeout)
DELAY=30

echo "Waiting for $DELAY seconds to allow Zookeeper session timeout cleanup..."
sleep $DELAY
echo "Delay complete. Starting Kafka server."

# Execute the default Kafka startup command (often found in the original Dockerfile)
# Note: You may need to adjust this command based on your specific Kafka image/setup
exec /etc/confluent/docker/run