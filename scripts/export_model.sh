#!/bin/bash
# Export a YOLO model to Core ML (.mlpackage) with embedded NMS so Vision
# returns VNRecognizedObjectObservation directly.
#
# Fallback chain: yolo26n -> yolo11n -> Apple YOLOv3-Tiny (.mlmodel download).
# Output lands in eye-assist/Models/.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_DIR="$ROOT/eye-assist/Models"
VENV_DIR="${TMPDIR:-/tmp}/audiovision-export-venv"
mkdir -p "$MODELS_DIR"

echo "== Creating Python 3.12 venv with uv =="
uv venv --python 3.12 "$VENV_DIR" || exit 1
source "$VENV_DIR/bin/activate"

echo "== Installing ultralytics + coremltools =="
uv pip install --python "$VENV_DIR/bin/python" ultralytics coremltools || exit 1

export_yolo() {
  local model="$1"
  echo "== Exporting $model to Core ML =="
  (cd "${TMPDIR:-/tmp}" && yolo export model="${model}.pt" format=coreml nms=True imgsz=640 half=True) || return 1
  local pkg="${TMPDIR:-/tmp}/${model}.mlpackage"
  if [ -d "$pkg" ]; then
    rm -rf "$MODELS_DIR/YOLODetector.mlpackage"
    cp -R "$pkg" "$MODELS_DIR/YOLODetector.mlpackage"
    echo "$model" > "$MODELS_DIR/model_name.txt"
    echo "== SUCCESS: $model -> $MODELS_DIR/YOLODetector.mlpackage =="
    return 0
  fi
  return 1
}

if export_yolo "yolo26n"; then exit 0; fi
echo "yolo26n export failed, trying yolo11n"
if export_yolo "yolo11n"; then exit 0; fi

echo "== Falling back to Apple YOLOv3-Tiny download =="
curl -fL -o "${TMPDIR:-/tmp}/YOLOv3Tiny.mlmodel" \
  "https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3Tiny/YOLOv3TinyFP16.mlmodel" || exit 1
rm -rf "$MODELS_DIR/YOLODetector.mlpackage" "$MODELS_DIR/YOLODetector.mlmodel"
mv "${TMPDIR:-/tmp}/YOLOv3Tiny.mlmodel" "$MODELS_DIR/YOLODetector.mlmodel"
echo "yolov3-tiny" > "$MODELS_DIR/model_name.txt"
echo "== SUCCESS: YOLOv3-Tiny fallback =="
