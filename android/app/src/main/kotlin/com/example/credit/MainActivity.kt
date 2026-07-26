package com.example.credit

import io.flutter.embedding.android.FlutterFragmentActivity

import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val channelName = "com.example.credit/backup_completion"

    override fun shouldDestroyEngineWithHost(): Boolean {
        return !BackupCompletionService.isServiceRunning
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
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
