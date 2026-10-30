"""
SafeHer AI - Fall & Motion Detection Model
============================================
LSTM model trained on UCI HAR dataset for detecting falls and abnormal motion.
Also trains a Random Forest as a lightweight alternative.

Activities detected:
  WALKING, WALKING_UPSTAIRS, WALKING_DOWNSTAIRS,
  SITTING, STANDING, LAYING
  → SafeHer maps sudden transitions to LAYING as potential falls.

Usage:
  python scripts/train_motion_model.py

Output:
  models/motion_lstm_model.h5
  models/motion_rf_model.pkl
  tflite/motion_model.tflite
"""

import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, callbacks
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, accuracy_score
from pathlib import Path
import matplotlib.pyplot as plt
import pickle

# ──── Config ────
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data" / "uci_har"
MODEL_DIR = BASE_DIR / "models"
TFLITE_DIR = BASE_DIR / "tflite"
MODEL_DIR.mkdir(exist_ok=True)
TFLITE_DIR.mkdir(exist_ok=True)

BATCH_SIZE = 64
EPOCHS = 50
NUM_CLASSES = 6

ACTIVITY_LABELS = {
    1: 'WALKING',
    2: 'WALKING_UPSTAIRS',
    3: 'WALKING_DOWNSTAIRS',
    4: 'SITTING',
    5: 'STANDING',
    6: 'LAYING',
}

# For SafeHer: LAYING after motion = possible fall
FALL_RISK_TRANSITIONS = {
    (1, 6), (2, 6), (3, 6),  # Walking → Laying
    (5, 6),                    # Standing → Laying
}


def find_data_root():
    """Locate the UCI HAR Dataset directory."""
    candidates = [
        DATA_DIR / "UCI HAR Dataset",
        DATA_DIR / "UCI_HAR_Dataset",
        DATA_DIR,
    ]
    for c in candidates:
        if (c / "train" / "X_train.txt").exists():
            return c
    return None


def load_uci_har():
    """Load UCI HAR dataset from text files."""
    root = find_data_root()
    if root is None:
        print("❌ UCI HAR data not found!")
        print("   Run: python scripts/prepare_data.py")
        return None

    print(f"  Data root: {root}")

    def load_file(path):
        return np.loadtxt(str(path))

    def load_labels(path):
        return np.loadtxt(str(path), dtype=int)

    # Load pre-computed features (561 features)
    X_train = load_file(root / "train" / "X_train.txt")
    X_test = load_file(root / "test" / "X_test.txt")
    y_train = load_labels(root / "train" / "y_train.txt")
    y_test = load_labels(root / "test" / "y_test.txt")

    # Load raw inertial signals for LSTM (if available)
    raw_train, raw_test = None, None
    inertial_train = root / "train" / "Inertial Signals"
    inertial_test = root / "test" / "Inertial Signals"

    if inertial_train.exists():
        signal_files = [
            'body_acc_x_train.txt', 'body_acc_y_train.txt', 'body_acc_z_train.txt',
            'body_gyro_x_train.txt', 'body_gyro_y_train.txt', 'body_gyro_z_train.txt',
            'total_acc_x_train.txt', 'total_acc_y_train.txt', 'total_acc_z_train.txt',
        ]
        signals_train = []
        signals_test = []

        for sf in signal_files:
            train_path = inertial_train / sf
            test_path = inertial_test / sf.replace('train', 'test')

            if train_path.exists() and test_path.exists():
                signals_train.append(load_file(train_path))
                signals_test.append(load_file(test_path))

        if signals_train:
            raw_train = np.stack(signals_train, axis=-1)  # (samples, 128, 9)
            raw_test = np.stack(signals_test, axis=-1)
            print(f"  Raw signals shape: {raw_train.shape}")

    print(f"  Feature matrix: {X_train.shape}")
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")
    print(f"  Classes: {np.unique(y_train)}")

    return {
        'X_train': X_train, 'X_test': X_test,
        'y_train': y_train, 'y_test': y_test,
        'raw_train': raw_train, 'raw_test': raw_test,
    }


def build_lstm_model(input_shape, num_classes):
    """Build LSTM model for sequence-based motion detection."""
    model = models.Sequential([
        layers.Input(shape=input_shape),

        layers.LSTM(128, return_sequences=True),
        layers.Dropout(0.3),
        layers.LSTM(64),
        layers.Dropout(0.3),

        layers.Dense(128, activation='relu'),
        layers.BatchNormalization(),
        layers.Dropout(0.4),
        layers.Dense(64, activation='relu'),
        layers.Dropout(0.3),
        layers.Dense(num_classes, activation='softmax'),
    ])

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy'],
    )
    return model


def build_dense_model(input_dim, num_classes):
    """Build a simple Dense model for pre-computed features (fallback)."""
    model = models.Sequential([
        layers.Input(shape=(input_dim,)),
        layers.Dense(256, activation='relu'),
        layers.BatchNormalization(),
        layers.Dropout(0.3),
        layers.Dense(128, activation='relu'),
        layers.BatchNormalization(),
        layers.Dropout(0.3),
        layers.Dense(64, activation='relu'),
        layers.Dropout(0.2),
        layers.Dense(num_classes, activation='softmax'),
    ])

    model.compile(
        optimizer='adam',
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy'],
    )
    return model


def train_random_forest(X_train, X_test, y_train, y_test):
    """Train a Random Forest classifier as a lightweight alternative."""
    print("\n🌲 Training Random Forest...")
    rf = RandomForestClassifier(
        n_estimators=200,
        max_depth=20,
        random_state=42,
        n_jobs=-1,
    )
    rf.fit(X_train, y_train)

    y_pred = rf.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    print(f"   Random Forest Accuracy: {acc:.4f} ({acc * 100:.1f}%)")
    print("\n   Classification Report:")
    print(classification_report(
        y_test, y_pred,
        target_names=[ACTIVITY_LABELS[i] for i in sorted(ACTIVITY_LABELS.keys())],
    ))

    # Save model
    rf_path = MODEL_DIR / "motion_rf_model.pkl"
    with open(rf_path, 'wb') as f:
        pickle.dump(rf, f)
    print(f"💾 Random Forest saved: {rf_path}")

    return rf


def convert_to_tflite(model, name="motion_model"):
    """Convert Keras model to TFLite."""
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    output_path = TFLITE_DIR / f"{name}.tflite"
    with open(output_path, 'wb') as f:
        f.write(tflite_model)

    size_mb = len(tflite_model) / (1024 * 1024)
    print(f"✅ TFLite model saved: {output_path} ({size_mb:.2f} MB)")


def train():
    """Main training pipeline."""
    print("=" * 60)
    print("  SafeHer - Fall & Motion Detection Training")
    print("=" * 60)

    # Load data
    print("\n📂 Loading UCI HAR dataset...")
    data = load_uci_har()
    if data is None:
        return

    # Labels are 1-indexed, convert to 0-indexed
    y_train = data['y_train'] - 1
    y_test = data['y_test'] - 1

    # ── Method 1: LSTM on raw signals (preferred) ──
    if data['raw_train'] is not None:
        print("\n🏗️  Building LSTM model (raw inertial signals)...")
        lstm_model = build_lstm_model(
            input_shape=data['raw_train'].shape[1:],
            num_classes=NUM_CLASSES,
        )
        lstm_model.summary()

        cb = [
            callbacks.EarlyStopping(patience=10, restore_best_weights=True),
            callbacks.ReduceLROnPlateau(factor=0.5, patience=5),
        ]

        print("\n🚀 Training LSTM...")
        history = lstm_model.fit(
            data['raw_train'], y_train,
            epochs=EPOCHS,
            batch_size=BATCH_SIZE,
            validation_data=(data['raw_test'], y_test),
            callbacks=cb,
        )

        loss, acc = lstm_model.evaluate(data['raw_test'], y_test)
        print(f"\n   LSTM Test Accuracy: {acc:.4f} ({acc * 100:.1f}%)")

        lstm_model.save(str(MODEL_DIR / "motion_lstm_model.h5"))
        convert_to_tflite(lstm_model, "motion_model")

    else:
        # ── Method 2: Dense model on pre-computed features ──
        print("\n🏗️  Building Dense model (pre-computed features)...")
        dense_model = build_dense_model(
            input_dim=data['X_train'].shape[1],
            num_classes=NUM_CLASSES,
        )

        cb = [
            callbacks.EarlyStopping(patience=10, restore_best_weights=True),
            callbacks.ReduceLROnPlateau(factor=0.5, patience=5),
        ]

        print("\n🚀 Training Dense model...")
        history = dense_model.fit(
            data['X_train'], y_train,
            epochs=EPOCHS,
            batch_size=BATCH_SIZE,
            validation_data=(data['X_test'], y_test),
            callbacks=cb,
        )

        loss, acc = dense_model.evaluate(data['X_test'], y_test)
        print(f"\n   Dense Model Test Accuracy: {acc:.4f} ({acc * 100:.1f}%)")

        dense_model.save(str(MODEL_DIR / "motion_dense_model.h5"))
        convert_to_tflite(dense_model, "motion_model")

    # ── Method 3: Random Forest (lightweight fallback) ──
    train_random_forest(data['X_train'], data['X_test'], y_train, y_test)

    # Save label mapping
    label_map = {i: ACTIVITY_LABELS[i + 1] for i in range(NUM_CLASSES)}
    np.save(str(MODEL_DIR / "motion_label_map.npy"), label_map)

    # Plot
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))
    ax1.plot(history.history['accuracy'], label='Train')
    ax1.plot(history.history['val_accuracy'], label='Validation')
    ax1.set_title('Motion Model Accuracy')
    ax1.legend()
    ax2.plot(history.history['loss'], label='Train')
    ax2.plot(history.history['val_loss'], label='Validation')
    ax2.set_title('Motion Model Loss')
    ax2.legend()
    plt.tight_layout()
    plt.savefig(str(MODEL_DIR / 'motion_training_history.png'), dpi=150)

    print("\n✅ Motion detection model training complete!")


if __name__ == "__main__":
    train()
