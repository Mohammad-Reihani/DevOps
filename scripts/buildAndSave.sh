#!/bin/bash

# === Configuration ===
IMAGE_NAME="react-native-android-builder"
IMAGE_TAG="latest"
IMAGE_FILE="$IMAGE_NAME.tar.xz"
DOCKERFILE_PATH="Dockerfile"
BUILD_CONTEXT="."

# === Build ===
echo "🔧 Building Docker image: $IMAGE_NAME:$IMAGE_TAG ..."
docker build -t "$IMAGE_NAME:$IMAGE_TAG" -f "$DOCKERFILE_PATH" "$BUILD_CONTEXT"

# === Save and Compress ===
echo "📦 Saving and compressing Docker image to $IMAGE_FILE ..."
echo "⏳ This might take a while depending on the image size and disk speed."
echo "💡 Please DO NOT interrupt the process. It's still running unless an error appears."
echo "📁 You can monitor the file size with: ls -lh $IMAGE_FILE"

docker save "$IMAGE_NAME:$IMAGE_TAG" | xz -T0 -c > "$IMAGE_FILE"

# === Done ===
echo "✅ Docker image saved and compressed successfully: $IMAGE_FILE"