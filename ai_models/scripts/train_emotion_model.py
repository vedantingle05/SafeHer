"""
SafeHer AI - Facial Emotion Detection Model
=============================================
CNN model trained on FER2013 dataset to detect distress emotions.
Detects: angry, disgust, fear, happy, neutral, sad, surprise
Key for SafeHer: fear, angry, sad → potential distress signals.

Usage:
  python scripts/train_emotion_model.py

Output:
  models/emotion_model.h5
  tflite/emotion_model.tflite
"""

import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, callbacks
from tensorflow.keras.preprocessing.image import ImageDataGenerator
from pathlib import Path
import matplotlib.pyplot as plt

# ──── Config ────
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data" / "fer2013"
MODEL_DIR = BASE_DIR / "models"
TFLITE_DIR = BASE_DIR / "tflite"
MODEL_DIR.mkdir(exist_ok=True)
TFLITE_DIR.mkdir(exist_ok=True)

IMG_SIZE = 48
BATCH_SIZE = 64
EPOCHS = 50
NUM_CLASSES = 7

EMOTION_LABELS = ['angry', 'disgust', 'fear', 'happy', 'neutral', 'sad', 'surprise']
# Distress emotions (used for SafeHer alerting)
DISTRESS_EMOTIONS = {'fear', 'angry', 'sad', 'disgust'}


def build_model():
    """Build a CNN for facial emotion recognition."""
    model = models.Sequential([
        # Block 1
        layers.Conv2D(64, (3, 3), padding='same', input_shape=(IMG_SIZE, IMG_SIZE, 1)),
        layers.BatchNormalization(),
        layers.Activation('relu'),
        layers.Conv2D(64, (3, 3), padding='same'),
        layers.BatchNormalization(),
        layers.Activation('relu'),
        layers.MaxPooling2D((2, 2)),
        layers.Dropout(0.25),

        # Block 2
        layers.Conv2D(128, (3, 3), padding='same'),
        layers.BatchNormalization(),
        layers.Activation('relu'),
        layers.Conv2D(128, (3, 3), padding='same'),
        layers.BatchNormalization(),
        layers.Activation('relu'),
        layers.MaxPooling2D((2, 2)),
        layers.Dropout(0.25),

        # Block 3
        layers.Conv2D(256, (3, 3), padding='same'),
        layers.BatchNormalization(),
        layers.Activation('relu'),
        layers.Conv2D(256, (3, 3), padding='same'),
        layers.BatchNormalization(),
        layers.Activation('relu'),
        layers.MaxPooling2D((2, 2)),
        layers.Dropout(0.25),

        # Dense layers
        layers.Flatten(),
        layers.Dense(512),
        layers.BatchNormalization(),
        layers.Activation('relu'),
        layers.Dropout(0.5),
        layers.Dense(256),
        layers.BatchNormalization(),
        layers.Activation('relu'),
        layers.Dropout(0.5),
        layers.Dense(NUM_CLASSES, activation='softmax'),
    ])

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.0001),
        loss='categorical_crossentropy',
        metrics=['accuracy'],
    )

    return model


def load_data():
    """Load FER2013 data using ImageDataGenerator."""
    train_datagen = ImageDataGenerator(
        rescale=1.0 / 255,
        rotation_range=15,
        width_shift_range=0.15,
        height_shift_range=0.15,
        horizontal_flip=True,
        zoom_range=0.1,
    )
    test_datagen = ImageDataGenerator(rescale=1.0 / 255)

    train_generator = train_datagen.flow_from_directory(
        DATA_DIR / "train",
        target_size=(IMG_SIZE, IMG_SIZE),
        color_mode='grayscale',
        batch_size=BATCH_SIZE,
        class_mode='categorical',
    )

    test_generator = test_datagen.flow_from_directory(
        DATA_DIR / "test",
        target_size=(IMG_SIZE, IMG_SIZE),
        color_mode='grayscale',
        batch_size=BATCH_SIZE,
        class_mode='categorical',
    )

    return train_generator, test_generator


def convert_to_tflite(model):
    """Convert Keras model to TensorFlow Lite for mobile deployment."""
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]  # Float16 quantization
    tflite_model = converter.convert()

    output_path = TFLITE_DIR / "emotion_model.tflite"
    with open(output_path, 'wb') as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"✅ TFLite model saved: {output_path} ({size_mb:.2f} MB)")


def train():
    """Main training pipeline."""
    print("=" * 60)
    print("  SafeHer - Facial Emotion Detection Training")
    print("=" * 60)

    # Load data
    print("\n📂 Loading FER2013 dataset...")
    train_gen, test_gen = load_data()
    print(f"   Training samples: {train_gen.samples}")
    print(f"   Test samples: {test_gen.samples}")
    print(f"   Classes: {list(train_gen.class_indices.keys())}")

    # Build model
    print("\n🏗️  Building CNN model...")
    model = build_model()
    model.summary()

    # Callbacks
    cb = [
        callbacks.EarlyStopping(patience=10, restore_best_weights=True),
        callbacks.ReduceLROnPlateau(factor=0.5, patience=5, min_lr=1e-7),
        callbacks.ModelCheckpoint(
            str(MODEL_DIR / "emotion_model_best.h5"),
            save_best_only=True, monitor='val_accuracy',
        ),
    ]

    # Train
    print("\n🚀 Training...")
    history = model.fit(
        train_gen,
        epochs=EPOCHS,
        validation_data=test_gen,
        callbacks=cb,
    )

    # Evaluate
    print("\n📊 Evaluating...")
    loss, accuracy = model.evaluate(test_gen)
    print(f"   Test Loss: {loss:.4f}")
    print(f"   Test Accuracy: {accuracy:.4f} ({accuracy * 100:.1f}%)")

    # Save full model
    model.save(str(MODEL_DIR / "emotion_model.h5"))
    print(f"\n💾 Model saved: {MODEL_DIR / 'emotion_model.h5'}")

    # Convert to TFLite
    print("\n📱 Converting to TFLite...")
    convert_to_tflite(model)

    # Plot training history
    _plot_history(history)

    print("\n✅ Emotion detection model training complete!")


def _plot_history(history):
    """Save training history plots."""
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

    ax1.plot(history.history['accuracy'], label='Train')
    ax1.plot(history.history['val_accuracy'], label='Validation')
    ax1.set_title('Model Accuracy')
    ax1.set_xlabel('Epoch')
    ax1.set_ylabel('Accuracy')
    ax1.legend()

    ax2.plot(history.history['loss'], label='Train')
    ax2.plot(history.history['val_loss'], label='Validation')
    ax2.set_title('Model Loss')
    ax2.set_xlabel('Epoch')
    ax2.set_ylabel('Loss')
    ax2.legend()

    plt.tight_layout()
    plt.savefig(str(MODEL_DIR / 'emotion_training_history.png'), dpi=150)
    print(f"📈 Training plot saved: {MODEL_DIR / 'emotion_training_history.png'}")


if __name__ == "__main__":
    train()
