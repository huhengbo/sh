#!/bin/bash

# Update package index
sudo apt-get update

# Install necessary packages
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -

# Add Docker's official APT repository
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable"

# Update package index again
sudo apt-get update

# Install Docker CE
sudo apt-get install -y docker-ce

# Enable Docker service
sudo systemctl enable docker

# Start Docker service
sudo systemctl start docker

# Configure Docker to listen on TCP port 2375 without TLS
sudo mkdir -p /etc/systemd/system/docker.service.d
echo "[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375" | sudo tee /etc/systemd/system/docker.service.d/override.conf

# Reload systemd and restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "Docker has been installed and configured to listen on port 2375 without TLS."