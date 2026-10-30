"""
SafeHer AI - Dataset Download & Preparation
=============================================
Downloads and prepares the datasets needed for training:
  1. FER2013     → Facial Emotion Recognition
  2. RAVDESS     → Speech Emotion Recognition
  3. UrbanSound8K → Sound Classification (scream detection)
  4. UCI HAR     → Human Activity Recognition (fall detection)

Usage:
  python scripts/prepare_data.py

Note: Some datasets require Kaggle API credentials.
  - Place kaggle.json in ~/.kaggle/
  - Get it from: https://www.kaggle.com/settings → API → Create New Token
"""

import os
import sys
import zipfile
import urllib.request
from pathlib import Path

# ──── Paths ────
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"

def create_dirs():
    """Create data directories."""
    dirs = [
        DATA_DIR / "fer2013",
        DATA_DIR / "ravdess",
        DATA_DIR / "urbansound8k",
        DATA_DIR / "uci_har",
    ]
    for d in dirs:
        d.mkdir(parents=True, exist_ok=True)
    print("✅ Data directories created.")

def download_fer2013():
    """
    FER2013 - Facial Emotion Recognition dataset.
    Download from Kaggle: kaggle datasets download -d msambare/fer2013
    """
    dest = DATA_DIR / "fer2013"
    if (dest / "train").exists():
        print("✅ FER2013 already present.")
        return

    print("\n📦 FER2013 Dataset")
    print("   This dataset must be downloaded from Kaggle.")
    print("   Run: kaggle datasets download -d msambare/fer2013")
    print(f"   Extract to: {dest}")
    print("   Expected structure:")
    print("     data/fer2013/train/<emotion_folder>/images...")
    print("     data/fer2013/test/<emotion_folder>/images...")
    print("   Emotion folders: angry, disgust, fear, happy, neutral, sad, surprise")

    try:
        os.system(f"kaggle datasets download -d msambare/fer2013 -p {dest} --unzip")
        print("✅ FER2013 downloaded.")
    except Exception as e:
        print(f"⚠️  Auto-download failed ({e}). Please download manually.")

def download_ravdess():
    """
    RAVDESS - Ryerson Audio-Visual Database of Emotional Speech and Song.
    Available at: https://zenodo.org/record/1188976
    """
    dest = DATA_DIR / "ravdess"
    if any(dest.glob("Actor_*")):
        print("✅ RAVDESS already present.")
        return

    print("\n📦 RAVDESS Dataset")
    print("   Download from: https://zenodo.org/record/1188976")
    print(f"   Extract all Actor_XX folders to: {dest}")
    print("   File naming convention: modality-vocal-emotion-intensity-statement-repetition-actor.wav")
    print("   Emotions: 01=neutral, 02=calm, 03=happy, 04=sad, 05=angry, 06=fearful, 07=disgust, 08=surprised")

    try:
        os.system(f"kaggle datasets download -d uwrfkaggler/ravdess-emotional-speech-audio -p {dest} --unzip")
        print("✅ RAVDESS downloaded.")
    except Exception as e:
        print(f"⚠️  Auto-download failed ({e}). Please download manually.")

def download_urbansound8k():
    """
    UrbanSound8K - Urban sound classification dataset.
    Available at: https://urbansounddataset.weebly.com/
    """
    dest = DATA_DIR / "urbansound8k"
    if (dest / "UrbanSound8K").exists() or any(dest.glob("fold*")):
        print("✅ UrbanSound8K already present.")
        return

    print("\n📦 UrbanSound8K Dataset")
    print("   Download from: https://urbansounddataset.weebly.com/urbansound8k.html")
    print(f"   Extract to: {dest}")
    print("   Expected: fold1/ through fold10/ directories + metadata/UrbanSound8K.csv")
    print("   Classes: air_conditioner, car_horn, children_playing, dog_bark,")
    print("            drilling, engine_idling, gun_shot, jackhammer, siren, street_music")

    try:
        os.system(f"kaggle datasets download -d chrisfilo/urbansound8k -p {dest} --unzip")
        print("✅ UrbanSound8K downloaded.")
    except Exception as e:
        print(f"⚠️  Auto-download failed ({e}). Please download manually.")

def download_uci_har():
    """
    UCI HAR - Human Activity Recognition Using Smartphones.
    Direct download available from UCI ML Repository.
    """
    dest = DATA_DIR / "uci_har"
    if (dest / "UCI HAR Dataset").exists() or (dest / "train").exists():
        print("✅ UCI HAR already present.")
        return

    print("\n📦 UCI HAR Dataset")
    url = "https://archive.ics.uci.edu/ml/machine-learning-databases/00240/UCI%20HAR%20Dataset.zip"
    zip_path = dest / "uci_har.zip"

    try:
        print(f"   Downloading from UCI repository...")
        urllib.request.urlretrieve(url, zip_path)
        with zipfile.ZipFile(zip_path, 'r') as zf:
            zf.extractall(dest)
        zip_path.unlink()
        print("✅ UCI HAR downloaded and extracted.")
    except Exception as e:
        print(f"⚠️  Download failed ({e}).")
        print(f"   Manual download: {url}")
        print(f"   Extract to: {dest}")

def main():
    print("=" * 60)
    print("  SafeHer AI - Dataset Preparation")
    print("=" * 60)

    create_dirs()
    download_fer2013()
    download_ravdess()
    download_urbansound8k()
    download_uci_har()

    print("\n" + "=" * 60)
    print("  Dataset preparation complete!")
    print("  Check the data/ directory for downloaded files.")
    print("  If any downloads failed, follow the manual instructions above.")
    print("=" * 60)

if __name__ == "__main__":
    main()
