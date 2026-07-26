package com.himanshuat.androidconnect.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Laptop
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.LinkOff
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Phone
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.Send
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.himanshuat.androidconnect.connectivity.ConnectionManager
import com.himanshuat.androidconnect.connectivity.DiscoveredPeer
import com.himanshuat.androidconnect.features.FileTransferHandler
import com.himanshuat.androidconnect.pairing.PairedPeer
import com.himanshuat.androidconnect.ui.theme.Positive

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(manager: ConnectionManager) {
    var showScanner by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val cameraLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) showScanner = true
    }
    val requestScan = {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) showScanner = true else cameraLauncher.launch(Manifest.permission.CAMERA)
    }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { manager.sendFile(it) }
    }
    val callPermissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}
    val requestCallPerms = {
        callPermissions.launch(
            arrayOf(
                Manifest.permission.READ_PHONE_STATE,
                Manifest.permission.ANSWER_PHONE_CALLS,
                Manifest.permission.READ_CALL_LOG,
                Manifest.permission.READ_CONTACTS,
            ),
        )
    }

    if (showScanner) {
        QrScannerScreen(
            onScanned = { url -> manager.pairViaQr(url); showScanner = false },
            onClose = { showScanner = false },
        )
        return
    }

    val status by manager.status.collectAsState()
    val paired by manager.paired.collectAsState()
    val discovered by manager.discovered.collectAsState()
    val pairingMode by manager.pairingMode.collectAsState()
    val transfers by manager.fileTransfer.transfers.collectAsState()

    val connected = status.startsWith("Connected")
    val pairedIds = paired.map { it.id }.toSet()
    val nearby = discovered.filter { it.id !in pairedIds }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Link, null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(8.dp))
                        Text("AndroidConnect")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { inner ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(inner),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item { HeroCard(connected, status, pairingMode, manager::setPairing) }

            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                    QuickAction(Icons.Rounded.QrCodeScanner, "Scan QR", requestScan, Modifier.weight(1f))
                    QuickAction(Icons.Rounded.Send, "Send file", { filePicker.launch("*/*") }, Modifier.weight(1f))
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                    QuickAction(
                        Icons.Rounded.Notifications, "Notifications",
                        { context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) },
                        Modifier.weight(1f),
                    )
                    QuickAction(Icons.Rounded.Phone, "Call control", requestCallPerms, Modifier.weight(1f))
                }
            }

            if (transfers.isNotEmpty()) {
                item { SectionLabel("Transfers") }
                items(transfers.takeLast(6).reversed(), key = { it.id }) { TransferRow(it) }
            }

            if (paired.isNotEmpty()) {
                item { SectionLabel("Paired") }
                items(paired, key = { it.id }) { peer ->
                    DeviceRow(peer.name, if (connected) "Connected" else "Paired", connected) {
                        IconButton(onClick = { manager.unpair(peer) }) {
                            Icon(Icons.Rounded.Close, "Unpair", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            item { SectionLabel(if (nearby.isEmpty()) "Searching for your Mac…" else "Nearby") }
            items(nearby, key = { it.id }) { peer ->
                DeviceRow(peer.name, "Nearby", false) {
                    Button(onClick = { manager.pair(peer) }) { Text("Pair") }
                }
            }
        }
    }
}

@Composable
private fun HeroCard(
    connected: Boolean,
    status: String,
    pairingMode: Boolean,
    onPairingChange: (Boolean) -> Unit,
) {
    val accent = MaterialTheme.colorScheme.primary
    val ring by animateColorAsState(if (connected) Positive else accent, label = "ring")
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(52.dp).background(ring.copy(alpha = 0.16f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (connected) Icons.Rounded.Laptop else Icons.Rounded.LinkOff,
                        null, tint = ring, modifier = Modifier.size(26.dp),
                    )
                }
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        if (connected) status.removePrefix("Connected to ").ifEmpty { "Connected" }
                        else "Not connected",
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(7.dp).background(ring, CircleShape))
                        Spacer(Modifier.width(6.dp))
                        Text(
                            status, style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Ready to pair", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "Turn on, then scan the QR or tap this phone on your Mac",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = pairingMode, onCheckedChange = onPairingChange)
            }
        }
    }
}

@Composable
private fun QuickAction(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    FilledTonalButton(onClick = onClick, modifier = modifier.height(72.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icon, null)
            Text(label, style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun DeviceRow(name: String, detail: String, connected: Boolean, trailing: @Composable () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Rounded.Laptop, null,
                tint = if (connected) Positive else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    detail, style = MaterialTheme.typography.labelSmall,
                    color = if (connected) Positive else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            trailing()
        }
    }
}

@Composable
private fun TransferRow(transfer: FileTransferHandler.Transfer) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (transfer.incoming) Icons.Rounded.Download else Icons.Rounded.Upload,
                    null,
                    tint = when {
                        transfer.failed -> MaterialTheme.colorScheme.error
                        transfer.done -> Positive
                        else -> MaterialTheme.colorScheme.primary
                    },
                )
                Spacer(Modifier.width(10.dp))
                Text(transfer.name, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    when {
                        transfer.failed -> "Failed"
                        transfer.done -> "Done"
                        else -> "${(transfer.progress * 100).toInt()}%"
                    },
                    style = MaterialTheme.typography.labelMedium,
                    color = if (transfer.failed) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!transfer.done && !transfer.failed) {
                LinearProgressIndicator(progress = { transfer.progress }, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 8.dp, start = 4.dp),
    )
}
