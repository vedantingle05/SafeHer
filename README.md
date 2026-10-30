# 🛡️ SafeHer — AI-Based Personal Safety Monitoring System

## ⚡ Quick Start (One Command)

**Prerequisites:** Flutter SDK, Node.js, Python 3.9+

```bash
# Unzip, then:
cd safeher
chmod +x setup.sh
./setup.sh
```

That's it. The script:
- Runs `flutter create` to generate all native build files
- Installs all Flutter, npm, and Python dependencies
- Creates the Python virtual environment
- Verifies everything works

Then:
```bash
# Terminal 1: Start backend
cd backend && npm run dev

# Terminal 2: Run app
cd frontend && flutter run
```

---

## 📁 What's Inside (62 files, 7,600+ lines)

```
safeher/
├── setup.sh                    ← RUN THIS FIRST
├── frontend/                   ← Flutter App (10 screens, 9 services)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/            (splash, onboarding, login, signup,
│   │   │                        home, dashboard, alerts, sensors,
│   │   │                        profile, settings)
│   │   ├── services/           (api, auth, sensors, alerts, AI inference,
│   │   │                        evidence capture, audio recording,
│   │   │                        safety monitoring, background)
│   │   ├── models/data_models.dart
│   │   └── themes/app_theme.dart
│   ├── android/                (manifest, build.gradle, permissions)
│   ├── ios/                    (Info.plist, Podfile, AppDelegate)
│   └── test/widget_test.dart
├── backend/                    ← Node.js API (JWT, MongoDB, SMS, Push)
│   ├── server.js
│   ├── routes/                 (auth, user, alert, emergency)
│   ├── controllers/            (auth, user, alert, emergency)
│   ├── models/                 (User, Alert, Contact)
│   ├── middleware/auth.middleware.js
│   └── utils/                  (sms via Twilio, push via Firebase)
├── ai_models/                  ← Python AI (4 datasets, 3 models)
│   ├── scripts/
│   │   ├── prepare_data.py     (downloads FER2013, RAVDESS, UrbanSound8K, UCI HAR)
│   │   ├── train_emotion_model.py   (CNN → facial emotion)
│   │   ├── train_audio_model.py     (CNN+LSTM → scream detection)
│   │   ├── train_motion_model.py    (LSTM+RF → fall detection)
│   │   └── train_all.py             (runs everything)
│   └── requirements.txt
└── docs/
```

## 🔧 Configuration (After Setup)

### Required: MongoDB Atlas (free)
1. Go to https://cloud.mongodb.com → Create free M0 cluster
2. Get connection string
3. Edit `backend/.env`:
   ```
   MONGODB_URI=mongodb+srv://user:pass@cluster0.xxx.mongodb.net/safeher
   JWT_SECRET=any_random_long_string_here
   ```

### Optional: Firebase (for push notifications + storage)
1. Create project at https://console.firebase.google.com
2. Add Android app → download `google-services.json` → `frontend/android/app/`
3. Add iOS app → download `GoogleService-Info.plist` → `frontend/ios/Runner/`
4. Without Firebase: app works fully, just no push notifications or cloud evidence storage

### Optional: Twilio (for SMS alerts)
1. Sign up at https://twilio.com
2. Add to `backend/.env`:
   ```
   TWILIO_ACCOUNT_SID=xxx
   TWILIO_AUTH_TOKEN=xxx
   TWILIO_PHONE_NUMBER=+1234567890
   ```
3. Without Twilio: SMS alerts log to console instead

### Optional: Train AI Models
```bash
cd ai_models
source venv/bin/activate
python scripts/prepare_data.py      # Download datasets
python scripts/train_all.py          # Train all 3 models (1-4 hours)
cp tflite/*.tflite ../frontend/assets/models/
```
Without models: fall detection still works via accelerometer thresholds

## 📡 API Documentation

Base URL: `http://localhost:5000/api`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | /auth/register | No | Create account |
| POST | /auth/login | No | Email/password login |
| POST | /auth/google | No | Google Sign-In |
| GET | /user/profile | JWT | Get profile |
| PUT | /user/profile | JWT | Update profile |
| POST | /user/contacts | JWT | Add emergency contact |
| DELETE | /user/contacts/:id | JWT | Remove contact |
| POST | /alert | JWT | Create alert |
| GET | /alert | JWT | List alerts (paginated) |
| PATCH | /alert/:id/status | JWT | Update alert status |
| POST | /emergency | JWT | Full SOS (alert + SMS + push) |

## 🤖 AI Detection Flow

```
Phone Sensors → Safety Monitoring Service → AI Models → Alert Decision
    │                                            │
    ├─ Accelerometer ──→ Fall threshold check ──→ fall detected? → ALERT
    ├─ Microphone ─────→ MFCC extraction ──────→ scream model  → ALERT
    ├─ Camera ─────────→ Grayscale 48×48 ─────→ emotion model → ALERT
    └─ Panic Button ───→ Direct trigger ───────────────────────→ ALERT
                                                                   │
                                                    ┌──────────────┘
                                                    ▼
                                    Capture Evidence (photo + audio)
                                    Send SMS to emergency contacts
                                    Push notification
                                    Store in MongoDB
```
