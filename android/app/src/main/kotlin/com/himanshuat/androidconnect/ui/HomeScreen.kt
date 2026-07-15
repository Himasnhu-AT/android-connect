package com.himanshuat.androidconnect.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Laptop
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.himanshuat.androidconnect.connectivity.ConnectionManager
import com.himanshuat.androidconnect.connectivity.DiscoveredPeer
import com.himanshuat.androidconnect.features.FileTransferHandler
import com.himanshuat.androidconnect.pairing.PairedPeer

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

    val pairedIds = paired.map { it.id }.toSet()
    val nearby = discovered.filter { it.id !in pairedIds }

    Scaffold(topBar = { TopAppBar(title = { Text("AndroidConnect") }) }) { inner ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(inner),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item { StatusCard(status, pairingMode, manager::setPairing) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = requestScan, modifier = Modifier.weight(1f)) {
                        Text("Scan QR")
                    }
                    OutlinedButton(onClick = { filePicker.launch("*/*") }, modifier = Modifier.weight(1f)) {
                        Text("Send a file")
                    }
                }
            }

            item {
                OutlinedButton(
                    onClick = { context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Enable notification mirroring")
                }
            }
            item {
                OutlinedButton(onClick = requestCallPerms, modifier = Modifier.fillMaxWidth()) {
                    Text("Enable call control")
                }
            }

            if (transfers.isNotEmpty()) {
                item { SectionLabel("Transfers") }
                items(transfers.takeLast(5), key = { it.id }) { transfer ->
                    TransferRow(transfer)
                }
            }

            if (paired.isNotEmpty()) {
                item { SectionLabel("Paired") }
                items(paired, key = { it.id }) { peer ->
                    PairedRow(peer) { manager.unpair(peer) }
                }
            }

            item { SectionLabel(if (nearby.isEmpty()) "Searching for your Mac…" else "Nearby") }
            items(nearby, key = { it.id }) { peer ->
                NearbyRow(peer) { manager.pair(peer) }
            }
        }
    }
}

@Composable
private fun StatusCard(status: String, pairingMode: Boolean, onPairingChange: (Boolean) -> Unit) {
    Card {
        Column(
            Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Link, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text(status, style = MaterialTheme.typography.titleMedium)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Ready to pair", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "Turn on, then tap Pair on your Mac",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = pairingMode, onCheckedChange = onPairingChange)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PairedRow(peer: PairedPeer, onUnpair: () -> Unit) {
    ElevatedCard {
        ListItem(
            headlineContent = { Text(peer.name) },
            supportingContent = { Text("Paired", style = MaterialTheme.typography.labelSmall) },
            leadingContent = { Icon(Icons.Rounded.Laptop, contentDescription = null) },
            trailingContent = {
                IconButton(onClick = onUnpair) { Icon(Icons.Rounded.Close, contentDescription = "Unpair") }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NearbyRow(peer: DiscoveredPeer, onPair: () -> Unit) {
    ElevatedCard {
        ListItem(
            headlineContent = { Text(peer.name) },
            leadingContent = { Icon(Icons.Rounded.Laptop, contentDescription = null) },
            trailingContent = { Button(onClick = onPair) { Text("Pair") } },
        )
    }
}

@Composable
private fun TransferRow(transfer: FileTransferHandler.Transfer) {
    ElevatedCard {
        Column(
            Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (transfer.incoming) Icons.Rounded.Download else Icons.Rounded.Upload,
                    contentDescription = null,
                )
                Spacer(Modifier.width(8.dp))
                Text(transfer.name, maxLines = 1, modifier = Modifier.weight(1f))
                Text(
                    when {
                        transfer.failed -> "Failed"
                        transfer.done -> "Done"
                        else -> "${(transfer.progress * 100).toInt()}%"
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = if (transfer.failed) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!transfer.done && !transfer.failed) {
                LinearProgressIndicator(
                    progress = { transfer.progress },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = 8.dp, start = 4.dp),
    )
}
