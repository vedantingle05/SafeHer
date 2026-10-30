#!/bin/bash
# ============================================================
#  SafeHer — One-Command Setup Script
#  Run this ONCE after unzipping. Everything will be ready.
# ============================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "🛡️  SafeHer — Automated Setup"
echo "============================================================"

# ──── Check prerequisites ────
echo ""
echo "Checking prerequisites..."

check_cmd() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ $1 is not installed. Please install it first.${NC}"
        echo "   $2"
        exit 1
    else
        echo -e "${GREEN}✅ $1 found${NC}"
    fi
}

check_cmd "flutter" "Install from: https://flutter.dev/docs/get-started/install"
check_cmd "node" "Install from: https://nodejs.org"
check_cmd "npm" "Comes with Node.js"
check_cmd "python3" "Install from: https://python.org"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ============================================================
#  STEP 1: Setup Flutter App
# ============================================================
echo ""
echo -e "${YELLOW}━━━ Step 1/4: Setting up Flutter app ━━━${NC}"

cd frontend

# Save our custom code
echo "Backing up custom code..."
cp -r lib lib_backup
cp pubspec.yaml pubspec_backup.yaml
cp -r assets assets_backup 2>/dev/null || true
cp -r android/app/src/main/AndroidManifest.xml manifest_backup.xml 2>/dev/null || true
cp -r android/app/build.gradle buildgradle_backup 2>/dev/null || true
cp -r android/app/src/main/res res_backup 2>/dev/null || true
cp -r android/app/proguard-rules.pro proguard_backup 2>/dev/null || true
cp -r android/app/src/main/kotlin kotlin_backup 2>/dev/null || true
cp -r ios/Runner/Info.plist plist_backup 2>/dev/null || true
cp -r ios/Runner/AppDelegate.swift appdelegate_backup 2>/dev/null || true
cp -r ios/Podfile podfile_backup 2>/dev/null || true
cp analysis_options.yaml analysis_backup.yaml 2>/dev/null || true
cp -r test test_backup 2>/dev/null || true

# Run flutter create to generate ALL native scaffold files
echo "Running flutter create (generates ~200 native files)..."
flutter create --org com.safeher --project-name safeher --platforms android,ios .

# Restore our custom code OVER the scaffold
echo "Restoring SafeHer custom code..."
rm -rf lib && mv lib_backup lib
cp pubspec_backup.yaml pubspec.yaml && rm pubspec_backup.yaml
rm -rf assets && mv assets_backup assets 2>/dev/null || mkdir -p assets/models assets/images assets/sounds
cp manifest_backup.xml android/app/src/main/AndroidManifest.xml 2>/dev/null || true
cp buildgradle_backup android/app/build.gradle 2>/dev/null || true
cp -r res_backup/* android/app/src/main/res/ 2>/dev/null || true
cp proguard_backup android/app/proguard-rules.pro 2>/dev/null || true
cp -r kotlin_backup/* android/app/src/main/kotlin/ 2>/dev/null || true
cp plist_backup ios/Runner/Info.plist 2>/dev/null || true
cp appdelegate_backup ios/Runner/AppDelegate.swift 2>/dev/null || true
cp podfile_backup ios/Podfile 2>/dev/null || true
cp analysis_backup.yaml analysis_options.yaml 2>/dev/null || true
rm -rf test && mv test_backup test 2>/dev/null || true

# Clean up backups
rm -f manifest_backup.xml buildgradle_backup proguard_backup plist_backup appdelegate_backup podfile_backup analysis_backup.yaml
rm -rf res_backup kotlin_backup

# Ensure asset dirs exist with placeholders
mkdir -p assets/models assets/images assets/sounds
touch assets/models/.gitkeep assets/images/.gitkeep assets/sounds/.gitkeep

# Install Flutter dependencies
echo "Installing Flutter packages..."
flutter pub get

echo -e "${GREEN}✅ Flutter app ready${NC}"
cd "$SCRIPT_DIR"

# ============================================================
#  STEP 2: Setup Backend
# ============================================================
echo ""
echo -e "${YELLOW}━━━ Step 2/4: Setting up Node.js backend ━━━${NC}"

cd backend

# Install npm packages
echo "Installing npm packages..."
npm install

# Create .env if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Created .env from template — edit it with your MongoDB URI${NC}"
fi

echo -e "${GREEN}✅ Backend ready${NC}"
cd "$SCRIPT_DIR"

# ============================================================
#  STEP 3: Setup AI/ML
# ============================================================
echo ""
echo -e "${YELLOW}━━━ Step 3/4: Setting up Python AI environment ━━━${NC}"

cd ai_models

# Create virtual environment
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

echo "Installing Python packages..."
source venv/bin/activate 2>/dev/null || . venv/bin/activate
pip install -r requirements.txt --quiet

# Create output directories
mkdir -p data models tflite

echo -e "${GREEN}✅ AI environment ready${NC}"
echo "   To train models: source venv/bin/activate && python scripts/train_all.py"
cd "$SCRIPT_DIR"

# ============================================================
#  STEP 4: Final verification
# ============================================================
echo ""
echo -e "${YELLOW}━━━ Step 4/4: Verifying setup ━━━${NC}"

errors=0

# Check Flutter
cd frontend
if flutter pub get --dry-run &>/dev/null; then
    echo -e "${GREEN}✅ Flutter dependencies OK${NC}"
else
    echo -e "${RED}❌ Flutter dependency issues — run: cd frontend && flutter pub get${NC}"
    errors=$((errors+1))
fi
cd "$SCRIPT_DIR"

# Check backend
if [ -d "backend/node_modules" ]; then
    echo -e "${GREEN}✅ Backend dependencies OK${NC}"
else
    echo -e "${RED}❌ Backend dependencies missing — run: cd backend && npm install${NC}"
    errors=$((errors+1))
fi

# Check Python
if [ -d "ai_models/venv" ]; then
    echo -e "${GREEN}✅ Python environment OK${NC}"
else
    echo -e "${RED}❌ Python venv missing${NC}"
    errors=$((errors+1))
fi

# ============================================================
#  Done!
# ============================================================
echo ""
echo "============================================================"
if [ $errors -eq 0 ]; then
    echo -e "${GREEN}🎉 SafeHer setup complete! All systems ready.${NC}"
else
    echo -e "${YELLOW}⚠️  Setup completed with $errors warnings.${NC}"
fi
echo "============================================================"
echo ""
echo "HOW TO RUN:"
echo ""
echo "  1. Start backend:"
echo "     cd backend && npm run dev"
echo ""
echo "  2. Run Flutter app (in another terminal):"
echo "     cd frontend && flutter run"
echo ""
echo "  3. Train AI models (optional — takes 1-4 hours):"
echo "     cd ai_models && source venv/bin/activate"
echo "     python scripts/prepare_data.py"
echo "     python scripts/train_all.py"
echo "     cp tflite/*.tflite ../frontend/assets/models/"
echo ""
echo "  IMPORTANT: Edit backend/.env with your MongoDB Atlas URI"
echo "  (Get free cluster: https://cloud.mongodb.com)"
echo ""
