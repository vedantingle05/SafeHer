"""
SafeHer AI - Master Training Script
=====================================
Runs the complete AI training pipeline:
  1. Prepare / download datasets
  2. Train facial emotion detection model
  3. Train audio distress detection model
  4. Train motion/fall detection model
  5. Convert all models to TFLite

Usage:
  python scripts/train_all.py
  python scripts/train_all.py --skip-download   # Skip dataset prep
"""

import sys
import time
from pathlib import Path

def run_script(name, path):
    """Run a training script and measure time."""
    print(f"\n{'='*60}")
    print(f"  Running: {name}")
    print(f"{'='*60}\n")

    start = time.time()
    try:
        # Use exec to run in same process for shared imports
        exec(open(str(path)).read(), {'__name__': '__main__', '__file__': str(path)})
        elapsed = time.time() - start
        print(f"\n⏱️  {name} completed in {elapsed:.1f}s")
        return True
    except Exception as e:
        print(f"\n❌ {name} failed: {e}")
        return False

def main():
    base = Path(__file__).resolve().parent
    skip_download = '--skip-download' in sys.argv

    print("🛡️  SafeHer AI - Complete Training Pipeline")
    print("=" * 60)

    results = {}

    # Step 1: Prepare data
    if not skip_download:
        results['Data Preparation'] = run_script(
            'Data Preparation', base / 'prepare_data.py')
    else:
        print("\n⏭️  Skipping dataset download (--skip-download)")

    # Step 2: Train emotion model
    results['Emotion Model'] = run_script(
        'Facial Emotion Detection', base / 'train_emotion_model.py')

    # Step 3: Train audio model
    results['Audio Model'] = run_script(
        'Audio Distress Detection', base / 'train_audio_model.py')

    # Step 4: Train motion model
    results['Motion Model'] = run_script(
        'Motion/Fall Detection', base / 'train_motion_model.py')

    # Summary
    print("\n" + "=" * 60)
    print("  TRAINING SUMMARY")
    print("=" * 60)
    for name, success in results.items():
        status = "✅ Success" if success else "❌ Failed"
        print(f"  {status}  {name}")

    # Check TFLite outputs
    tflite_dir = base.parent / "tflite"
    if tflite_dir.exists():
        tflite_files = list(tflite_dir.glob("*.tflite"))
        print(f"\n📱 TFLite models ready ({len(tflite_files)}):")
        for f in tflite_files:
            size_mb = f.stat().st_size / (1024 * 1024)
            print(f"   {f.name} ({size_mb:.2f} MB)")

    print("\n🎉 Pipeline complete!")
    print("   Copy .tflite files to: frontend/assets/models/")

if __name__ == "__main__":
    main()
