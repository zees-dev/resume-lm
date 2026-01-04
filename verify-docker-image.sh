#!/bin/bash
# Script to verify the Docker image contains the chatbot.tsx basePath fix

set -e

REGISTRY="ghcr.io"
IMAGE_NAME="zees-dev/resume-lm"  # Update if different
TAG="${1:-latest}"  # Default to 'latest', or pass tag as argument

echo "Verifying Docker image: $REGISTRY/$IMAGE_NAME:$TAG"
echo "=================================================="

# Pull the image
echo -e "\n1. Pulling image..."
docker pull "$REGISTRY/$IMAGE_NAME:$TAG"

# Create a temporary container
echo -e "\n2. Creating temporary container..."
CONTAINER_ID=$(docker create "$REGISTRY/$IMAGE_NAME:$TAG")

echo "Container ID: $CONTAINER_ID"

# Extract and check the chatbot.tsx file
echo -e "\n3. Checking chatbot.tsx for withBasePath usage..."
docker cp "$CONTAINER_ID:/app/.next" /tmp/next-verify 2>/dev/null || true

# Search for withBasePath in the built JavaScript
echo -e "\n4. Searching for 'withBasePath' in built files..."
if find /tmp/next-verify -name "*.js" -exec grep -l "withBasePath" {} \; 2>/dev/null | head -5; then
    echo "✅ Found withBasePath in built files"
else
    echo "❌ withBasePath NOT found in built files"
fi

# Search for the API endpoint usage
echo -e "\n5. Searching for API chat endpoint references..."
if find /tmp/next-verify -name "*.js" -exec grep -H "/api/chat" {} \; 2>/dev/null | head -5; then
    echo "Found /api/chat references (check if they use withBasePath)"
else
    echo "No /api/chat references found"
fi

# Check for basePath placeholder
echo -e "\n6. Checking for basePath placeholder (should be replaced at runtime)..."
if find /tmp/next-verify -name "*.js" -exec grep -l "__NEXT_BASEPATH_PLACEHOLDER__" {} \; 2>/dev/null | head -3; then
    echo "✅ Found basePath placeholder (will be replaced by entrypoint.sh)"
else
    echo "❌ No basePath placeholder found"
fi

# Cleanup
echo -e "\n7. Cleaning up..."
docker rm "$CONTAINER_ID" > /dev/null
rm -rf /tmp/next-verify

echo -e "\n=================================================="
echo "Verification complete!"
