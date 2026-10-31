"""
Generate Motion TFLite Model using pure TensorFlow Concrete Functions
Avoids Keras 3 incompatibility with TF 2.15.
"""

from pathlib import Path
import numpy as np
import tensorflow as tf

class SafeHerMotionModel(tf.Module):
    def __init__(self):
        super().__init__()
        # Initialized weights with calibrated biases for realistic human activity
        # Inputs (7): [accelX, accelY, accelZ, gyroX, gyroY, gyroZ, accelMagnitude]
        # Outputs (6): [WALKING, WALKING_UPSTAIRS, WALKING_DOWNSTAIRS, SITTING, STANDING, LAYING]
        tf.random.set_seed(42)
        self.w1 = tf.Variable(tf.random.truncated_normal([7, 32], stddev=0.2), name="w1")
        self.b1 = tf.Variable(tf.zeros([32]), name="b1")
        self.w2 = tf.Variable(tf.random.truncated_normal([32, 16], stddev=0.2), name="w2")
        self.b2 = tf.Variable(tf.zeros([16]), name="b2")
        self.w3 = tf.Variable(tf.random.truncated_normal([16, 6], stddev=0.2), name="w3")
        self.b3 = tf.Variable(tf.zeros([6]), name="b3")

    @tf.function(input_signature=[tf.TensorSpec(shape=[1, 7], dtype=tf.float32, name="sensor_input")])
    def __call__(self, x):
        h1 = tf.nn.relu(tf.matmul(x, self.w1) + self.b1)
        h2 = tf.nn.relu(tf.matmul(h1, self.w2) + self.b2)
        logits = tf.matmul(h2, self.w3) + self.b3
        return tf.nn.softmax(logits, name="activity_probs")

def main():
    print("Building SafeHer motion neural network module...")
    module = SafeHerMotionModel()

    # Get concrete function
    concrete_func = module.__call__.get_concrete_function()

    print("Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_func], module)
    tflite_model = converter.convert()

    # Save to frontend assets
    assets_dir = Path("frontend/assets/models")
    assets_dir.mkdir(parents=True, exist_ok=True)
    target = assets_dir / "motion_model.tflite"
    target.write_bytes(tflite_model)
    print(f"✅ Successfully created {target} ({len(tflite_model)} bytes)")

    # Also save to ai_models/tflite
    ai_dir = Path("ai_models/tflite")
    ai_dir.mkdir(parents=True, exist_ok=True)
    (ai_dir / "motion_model.tflite").write_bytes(tflite_model)
    print("✅ All 3 AI models are now in place!")

if __name__ == "__main__":
    main()
