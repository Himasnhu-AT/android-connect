package com.himanshuat.androidconnect

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.himanshuat.androidconnect.service.ConnectionService
import com.himanshuat.androidconnect.ui.HomeScreen
import com.himanshuat.androidconnect.ui.theme.AndroidConnectTheme

class MainActivity : ComponentActivity() {
    private val requestNotifications =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        ContextCompat.startForegroundService(this, Intent(this, ConnectionService::class.java))

        val manager = (application as AndroidConnectApp).connection
        setContent {
            AndroidConnectTheme {
                HomeScreen(manager)
            }
        }
    }
}
