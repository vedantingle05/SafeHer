package com.safeher.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val SMS_CHANNEL = "com.safeher.app/sms"
    private val TAG = "SafeHerSms"

    override fun getRenderMode(): RenderMode {
        return RenderMode.texture
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendDirectSms" -> {
                    val phone = call.argument<String>("phone")
                    val message = call.argument<String>("message")

                    if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "Phone and message cannot be empty", null)
                        return@setMethodCallHandler
                    }

                    // Check SEND_SMS permission at runtime
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                        Log.w(TAG, "SEND_SMS permission not granted. Requesting...")
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.SEND_SMS), 101)
                        result.error("PERMISSION_DENIED", "SEND_SMS permission not granted", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val smsManager = getBestSmsManager()
                        val parts = smsManager.divideMessage(message)
                        Log.d(TAG, "Dispatching SMS to $phone in ${parts.size} part(s)")

                        // Try sending directly
                        if (parts.size > 1) {
                            smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                        } else {
                            smsManager.sendTextMessage(phone, null, message, null, null)
                        }

                        // Also attempt 10-digit national format if phone was formatted with +91
                        val clean10 = phone.replace("+91", "").trim()
                        if (clean10.length == 10 && clean10 != phone) {
                            try {
                                if (parts.size > 1) {
                                    smsManager.sendMultipartTextMessage(clean10, null, parts, null, null)
                                } else {
                                    smsManager.sendTextMessage(clean10, null, message, null, null)
                                }
                            } catch (e2: Exception) {
                                Log.w(TAG, "10-digit retry notice: ${e2.message}")
                            }
                        }

                        Log.d(TAG, "✅ SMS successfully handed to cellular baseband for $phone")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Failed to send SMS via SmsManager: ${e.message}", e)
                        result.error("SMS_FAILED", e.localizedMessage, null)
                    }
                }
                "openSmsApp" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    try {
                        val uri = Uri.parse("smsto:${Uri.encode(phone)}")
                        val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                            putExtra("sms_body", message)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        Log.d(TAG, "📱 Opened native SMS composer for $phone")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to launch SMS composer: ${e.message}")
                        result.error("INTENT_FAILED", e.localizedMessage, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getBestSmsManager(): SmsManager {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val defaultSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
                if (defaultSubId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                    applicationContext.getSystemService(SmsManager::class.java).createForSubscriptionId(defaultSubId)
                } else {
                    applicationContext.getSystemService(SmsManager::class.java)
                }
            } catch (e: Exception) {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        } else {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }
    }
}
