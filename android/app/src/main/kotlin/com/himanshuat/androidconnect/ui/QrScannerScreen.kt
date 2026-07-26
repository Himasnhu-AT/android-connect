package com.himanshuat.androidconnect.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.google.zxing.BarcodeFormat
import com.journeyapps.barcodescanner.BarcodeCallback
import com.journeyapps.barcodescanner.BarcodeResult
import com.journeyapps.barcodescanner.DecoratedBarcodeView
import com.journeyapps.barcodescanner.DefaultDecoderFactory
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Full-screen camera preview that scans for an `ac://pair…` QR and reports it once. Uses the
 * lightweight ZXing embedded scanner (no CameraX / MLKit) to keep the app slim.
 */
@Composable
fun QrScannerScreen(onScanned: (String) -> Unit, onClose: () -> Unit) {
    val handled = remember { AtomicBoolean(false) }
    val scanner = remember { mutableStateOf<DecoratedBarcodeView?>(null) }

    // Drive the camera with the composable's lifecycle: pause when it leaves the tree.
    DisposableEffect(Unit) {
        onDispose { scanner.value?.pause() }
    }

    Box(Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                DecoratedBarcodeView(ctx).also { view ->
                    scanner.value = view
                    view.barcodeView.decoderFactory = DefaultDecoderFactory(listOf(BarcodeFormat.QR_CODE))
                    view.setStatusText("Point at the QR on your Mac")
                    view.decodeContinuous(object : BarcodeCallback {
                        override fun barcodeResult(result: BarcodeResult) {
                            val text = result.text ?: return
                            if (text.startsWith("ac://pair") && handled.compareAndSet(false, true)) {
                                onScanned(text)
                            }
                        }
                    })
                    view.resume()
                }
            },
        )
        FilledIconButton(
            onClick = onClose,
            modifier = Modifier.align(Alignment.TopEnd).padding(16.dp),
        ) {
            Icon(Icons.Rounded.Close, contentDescription = "Close")
        }
    }
}
