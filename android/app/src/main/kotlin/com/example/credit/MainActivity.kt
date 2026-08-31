package com.example.credit

import io.flutter.embedding.android.FlutterFragmentActivity

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private val channelName = "com.example.credit/backup_completion"
    private val whatsappChannelName = "com.example.credit/whatsapp_share"

    override fun shouldDestroyEngineWithHost(): Boolean {
        return !BackupCompletionService.isServiceRunning
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Existing backup completion channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCompletionService" -> {
                        val status = call.argument<String>("status") ?: "Credits Backup Running..."
                        startBackupService(status)
                        result.success(null)
                    }
                    "updateNotification" -> {
                        val status = call.argument<String>("status") ?: "Credits Backup Running..."
                        updateBackupServiceNotification(status)
                        result.success(null)
                    }
                    "stopCompletionService" -> {
                        stopBackupService()
                        result.success(null)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }

        // WhatsApp direct share channel
        // Sends a PDF file directly to a specific WhatsApp contact using the jid extra.
        // This bypasses the share sheet and opens WhatsApp straight to the borrower's chat.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, whatsappChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareToWhatsApp" -> {
                        val filePath = call.argument<String>("filePath")
                        val phone   = call.argument<String>("phone")   // e.g. "919876543210"
                        val text    = call.argument<String>("text") ?: ""

                        if (filePath == null || phone == null) {
                            result.error("INVALID_ARGS", "filePath and phone are required", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val file = File(filePath)
                            val authority = "com.example.credit.whatsapp_provider"
                            val contentUri: Uri = FileProvider.getUriForFile(
                                this, authority, file
                            )

                            // WhatsApp jid format for individual chats: phone@s.whatsapp.net
                            val jid = "$phone@s.whatsapp.net"

                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "application/pdf"
                                setPackage("com.whatsapp")
                                putExtra(Intent.EXTRA_STREAM, contentUri)
                                putExtra("jid", jid)
                                if (text.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, text)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }

                            // Try WhatsApp Business too if regular WhatsApp isn't available
                            val pm = packageManager
                            val canWhatsApp = pm.getLaunchIntentForPackage("com.whatsapp") != null
                            val canWhatsAppBusiness = pm.getLaunchIntentForPackage("com.whatsapp.w4b") != null

                            if (!canWhatsApp && canWhatsAppBusiness) {
                                intent.setPackage("com.whatsapp.w4b")
                            } else if (!canWhatsApp && !canWhatsAppBusiness) {
                                result.error("WHATSAPP_NOT_FOUND", "WhatsApp is not installed", null)
                                return@setMethodCallHandler
                            }

                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startBackupService(status: String) {
        val intent = Intent(this, BackupCompletionService::class.java).apply {
            putExtra("status", status)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun updateBackupServiceNotification(status: String) {
        startBackupService(status)
    }

    private fun stopBackupService() {
        val intent = Intent(this, BackupCompletionService::class.java)
        stopService(intent)
    }
}
