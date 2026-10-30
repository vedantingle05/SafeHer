"""
SafeHer AI - Audio Distress Detection Model
=============================================
CNN + LSTM model for detecting screams and distress audio.
Uses MFCC features extracted from RAVDESS and UrbanSound8K datasets.

Key detections:
  - Screams / shouts
  - Fearful speech
  - Angry speech
  - Gunshots, sirens (environmental danger sounds)

Usage:
  python scripts/train_audio_model.py

Output:
  models/audio_model.h5
  tflite/audio_model.tflite
"""

import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, callbacks
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from pathlib import Path
import matplotlib.pyplot as plt

try:
    import librosa
except ImportError:
    print("Installing librosa...")
    os.system("pip install librosa")
    import librosa

# ──── Config ────
BASE_DIR = Path(__file__).resolve().parent.parent
RAVDESS_DIR = BASE_DIR / "data" / "ravdess"
URBAN_DIR = BASE_DIR / "data" / "urbansound8k"
MODEL_DIR = BASE_DIR / "models"
TFLITE_DIR = BASE_DIR / "tflite"
MODEL_DIR.mkdir(exist_ok=True)
TFLITE_DIR.mkdir(exist_ok=True)

# Audio processing parameters
SAMPLE_RATE = 22050
DURATION = 3          # seconds
N_MFCC = 40           # number of MFCC coefficients
MAX_LEN = 130         # time steps after padding
BATCH_SIZE = 32
EPOCHS = 50

# SafeHer audio classes
AUDIO_CLASSES = ['neutral', 'calm', 'happy', 'sad', 'angry', 'fearful', 'scream', 'danger_sound']

# RAVDESS emotion mapping (filename digit 3 = emotion)
RAVDESS_EMOTIONS = {
    '01': 'neutral', '02': 'calm', '03': 'happy', '04': 'sad',
    '05': 'angry', '06': 'fearful', '07': 'disgust', '08': 'surprised'
}

# UrbanSound classes that indicate danger
DANGER_SOUNDS = {'gun_shot', 'siren'}
SCREAM_CLASSES = {'children_playing'}  # Proxy — in practice, use a dedicated scream dataset


def extract_mfcc(file_path, sr=SAMPLE_RATE, duration=DURATION, n_mfcc=N_MFCC):
    """Extract MFCC features from an audio file."""
    try:
        audio, _ = librosa.load(file_path, sr=sr, duration=duration)

        # Pad or truncate to fixed length
        target_len = sr * duration
        if len(audio) < target_len:
            audio = np.pad(audio, (0, target_len - len(audio)), mode='constant')
        else:
            audio = audio[:target_len]

        # Extract MFCCs
        mfcc = librosa.feature.mfcc(y=audio, sr=sr, n_mfcc=n_mfcc)

        # Pad/truncate time dimension
        if mfcc.shape[1] < MAX_LEN:
            mfcc = np.pad(mfcc, ((0, 0), (0, MAX_LEN - mfcc.shape[1])), mode='constant')
        else:
            mfcc = mfcc[:, :MAX_LEN]

        return mfcc.T  # Shape: (MAX_LEN, N_MFCC)

    except Exception as e:
        print(f"  ⚠️ Error processing {file_path}: {e}")
        return None


def load_ravdess_data():
    """Load RAVDESS dataset and extract MFCC features."""
    features, labels = [], []

    actor_dirs = sorted(RAVDESS_DIR.glob("Actor_*"))
    if not actor_dirs:
        # Try flat structure (Kaggle download)
        actor_dirs = sorted(RAVDESS_DIR.glob("audio_speech_actors_*"))

    if not actor_dirs:
        print("  ⚠️ RAVDESS data not found. Skipping.")
        return np.array([]), []

    print(f"  Found {len(actor_dirs)} RAVDESS actor directories.")

    for actor_dir in actor_dirs:
        for wav_file in actor_dir.glob("*.wav"):
            # Parse emotion from filename (3rd component)
            parts = wav_file.stem.split('-')
            if len(parts) >= 3:
                emotion_code = parts[2]
                emotion = RAVDESS_EMOTIONS.get(emotion_code, 'neutral')

                mfcc = extract_mfcc(str(wav_file))
                if mfcc is not None:
                    features.append(mfcc)
                    labels.append(emotion)

    print(f"  Loaded {len(features)} RAVDESS samples.")
    return np.array(features) if features else np.array([]), labels


def load_urbansound_data():
    """Load UrbanSound8K subset (danger sounds) and extract MFCC features."""
    features, labels = [], []

    # Check for metadata file
    metadata_path = None
    for candidate in [
        URBAN_DIR / "metadata" / "UrbanSound8K.csv",
        URBAN_DIR / "UrbanSound8K" / "metadata" / "UrbanSound8K.csv",
        URBAN_DIR / "UrbanSound8K.csv",
    ]:
        if candidate.exists():
            metadata_path = candidate
            break

    if metadata_path is None:
        print("  ⚠️ UrbanSound8K metadata not found. Skipping.")
        return np.array([]), []

    import csv
    with open(metadata_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    print(f"  Found {len(rows)} UrbanSound8K entries in metadata.")

    count = 0
    for row in rows:
        class_name = row.get('class', '')
        fold = row.get('fold', '')
        filename = row.get('slice_file_name', '')

        # Only use danger-related sounds and a small sample of neutral sounds
        is_danger = class_name in DANGER_SOUNDS
        is_scream_proxy = class_name in SCREAM_CLASSES
        is_neutral_sample = class_name not in DANGER_SOUNDS and class_name not in SCREAM_CLASSES and count < 200

        if not (is_danger or is_scream_proxy or is_neutral_sample):
            continue

        # Find the audio file
        audio_path = None
        for base in [URBAN_DIR, URBAN_DIR / "UrbanSound8K"]:
            candidate = base / f"fold{fold}" / filename
            if candidate.exists():
                audio_path = candidate
                break

        if audio_path is None:
            continue

        mfcc = extract_mfcc(str(audio_path))
        if mfcc is not None:
            if is_danger:
                label = 'danger_sound'
            elif is_scream_proxy:
                label = 'scream'
            else:
                label = 'neutral'
                count += 1

            features.append(mfcc)
            labels.append(label)

    print(f"  Loaded {len(features)} UrbanSound8K samples.")
    return np.array(features) if features else np.array([]), labels


def build_model(num_classes):
    """Build CNN + LSTM model for audio classification."""
    model = models.Sequential([
        # Input shape: (MAX_LEN, N_MFCC)
        layers.Input(shape=(MAX_LEN, N_MFCC)),

        # CNN feature extraction
        layers.Reshape((MAX_LEN, N_MFCC, 1)),
        layers.Conv2D(32, (3, 3), padding='same', activation='relu'),
        layers.BatchNormalization(),
        layers.MaxPooling2D((2, 2)),
        layers.Dropout(0.2),

        layers.Conv2D(64, (3, 3), padding='same', activation='relu'),
        layers.BatchNormalization(),
        layers.MaxPooling2D((2, 2)),
        layers.Dropout(0.2),

        layers.Conv2D(128, (3, 3), padding='same', activation='relu'),
        layers.BatchNormalization(),
        layers.MaxPooling2D((2, 2)),
        layers.Dropout(0.3),

        # Reshape for LSTM: collapse spatial dims
        layers.Reshape((-1, 128)),

        # LSTM sequence modeling
        layers.LSTM(128, return_sequences=True),
        layers.Dropout(0.3),
        layers.LSTM(64),
        layers.Dropout(0.3),

        # Classification
        layers.Dense(128, activation='relu'),
        layers.Dropout(0.4),
        layers.Dense(num_classes, activation='softmax'),
    ])

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy'],
    )

    return model


def convert_to_tflite(model):
    """Convert to TFLite for mobile deployment."""
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    output_path = TFLITE_DIR / "audio_model.tflite"
    with open(output_path, 'wb') as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"✅ TFLite model saved: {output_path} ({size_mb:.2f} MB)")


def train():
    """Main training pipeline."""
    print("=" * 60)
    print("  SafeHer - Audio Distress Detection Training")
    print("=" * 60)

    # Load datasets
    print("\n📂 Loading RAVDESS dataset...")
    ravdess_features, ravdess_labels = load_ravdess_data()

    print("\n📂 Loading UrbanSound8K dataset...")
    urban_features, urban_labels = load_urbansound_data()

    # Combine datasets
    all_features = []
    all_labels = []

    if len(ravdess_features) > 0:
        all_features.append(ravdess_features)
        all_labels.extend(ravdess_labels)

    if len(urban_features) > 0:
        all_features.append(urban_features)
        all_labels.extend(urban_labels)

    if not all_features:
        print("\n❌ No data loaded. Please download datasets first.")
        print("   Run: python scripts/prepare_data.py")
        return

    X = np.concatenate(all_features, axis=0)
    print(f"\n📊 Total samples: {len(X)}")
    print(f"   Feature shape: {X.shape}")

    # Encode labels
    le = LabelEncoder()
    y = le.fit_transform(all_labels)
    num_classes = len(le.classes_)
    print(f"   Classes ({num_classes}): {list(le.classes_)}")

    # Save label encoder mapping
    label_map = {i: label for i, label in enumerate(le.classes_)}
    np.save(str(MODEL_DIR / "audio_label_map.npy"), label_map)

    # Train/test split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    print(f"   Train: {len(X_train)}, Test: {len(X_test)}")

    # Build model
    print("\n🏗️  Building CNN+LSTM model...")
    model = build_model(num_classes)
    model.summary()

    # Callbacks
    cb = [
        callbacks.EarlyStopping(patience=10, restore_best_weights=True),
        callbacks.ReduceLROnPlateau(factor=0.5, patience=5, min_lr=1e-7),
        callbacks.ModelCheckpoint(
            str(MODEL_DIR / "audio_model_best.h5"),
            save_best_only=True, monitor='val_accuracy',
        ),
    ]

    # Train
    print("\n🚀 Training...")
    history = model.fit(
        X_train, y_train,
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        validation_data=(X_test, y_test),
        callbacks=cb,
    )

    # Evaluate
    print("\n📊 Evaluating...")
    loss, accuracy = model.evaluate(X_test, y_test)
    print(f"   Test Loss: {loss:.4f}")
    print(f"   Test Accuracy: {accuracy:.4f} ({accuracy * 100:.1f}%)")

    # Save
    model.save(str(MODEL_DIR / "audio_model.h5"))
    print(f"\n💾 Model saved: {MODEL_DIR / 'audio_model.h5'}")

    # Convert to TFLite
    print("\n📱 Converting to TFLite...")
    convert_to_tflite(model)

    # Plot history
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
    ax1.plot(history.history['accuracy'], label='Train')
    ax1.plot(history.history['val_accuracy'], label='Validation')
    ax1.set_title('Audio Model Accuracy')
    ax1.legend()
    ax2.plot(history.history['loss'], label='Train')
    ax2.plot(history.history['val_loss'], label='Validation')
    ax2.set_title('Audio Model Loss')
    ax2.legend()
    plt.tight_layout()
    plt.savefig(str(MODEL_DIR / 'audio_training_history.png'), dpi=150)

    print("\n✅ Audio distress detection model training complete!")


if __name__ == "__main__":
    train()
