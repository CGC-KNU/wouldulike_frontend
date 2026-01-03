package com.coggiri.new1

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import android.content.pm.Signature
import android.content.Intent
import java.security.MessageDigest

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logKakaoKeyHash()
        logIntent("onCreate", intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        logIntent("onNewIntent", intent)
    }

    private fun logKakaoKeyHash() {
        try {
            val signatures: Array<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val pkg = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                val info = pkg.signingInfo
                // Prefer current signers; fallback to history; else empty
                (info?.apkContentsSigners ?: info?.signingCertificateHistory) ?: emptyArray()
            } else {
                @Suppress("DEPRECATION")
                val pkg = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                @Suppress("DEPRECATION")
                pkg.signatures ?: emptyArray()
            }
            for (sig in signatures) {
                val md = MessageDigest.getInstance("SHA")
                md.update(sig.toByteArray())
                val keyHash = Base64.encodeToString(md.digest(), Base64.NO_WRAP)
                Log.i("KakaoKeyHash", keyHash)
            }
        } catch (e: Exception) {
            Log.w("KakaoKeyHash", "Failed to get key hash", e)
        }
    }

    private fun logIntent(phase: String, intent: Intent?) {
        val data = intent?.dataString
        val action = intent?.action
        Log.i("DeepLink", "$phase action=$action data=$data")
    }
}
