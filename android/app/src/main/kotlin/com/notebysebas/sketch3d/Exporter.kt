package com.notebysebas.sketch3d

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.annotation.RequiresApi
import java.io.File

/**
 * Native bridge used by the web app to persist exported files.
 *
 * In a WebView `<a download>` is a no-op, so index.html encodes the blob as
 * base64 and calls `window.AndroidBridge.saveToDownloads(name, mime, base64)`.
 * Files land in the device Downloads folder (MediaStore on Android 10+,
 * the public Downloads directory on Android 9 and older).
 */
class Exporter(private val activity: WryActivity) {

    private val context: Context
        get() = activity.applicationContext

    @JavascriptInterface
    fun isAvailable(): Boolean = true

    @JavascriptInterface
    fun saveToDownloads(name: String, mime: String, base64: String): Boolean {
        val safeName = sanitize(name)
        val mimeType = if (mime.isNullOrBlank()) "application/octet-stream" else mime
        return try {
            val bytes = Base64.decode(base64, Base64.DEFAULT)
            val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveWithMediaStore(safeName, effectiveMime(safeName, mimeType), bytes) != null
            } else {
                saveLegacy(safeName, bytes) != null
            }
            toast(if (ok) "Saved: $safeName" else "Save failed: $safeName")
            ok
        } catch (e: Throwable) {
            toast("Save failed: $safeName")
            false
        }
    }

    private fun sanitize(name: String): String {
        val clean = name.replace(Regex("[^A-Za-z0-9._-]"), "_").trim('_', '.')
        return if (clean.isEmpty()) "sketch3d" else clean
    }

    /**
     * MediaStore derives the extension from the MIME type and appends it when
     * it disagrees with the requested name — an OBJ exported as `text/plain`
     * would land as `name.obj.txt`. Keep the extension we asked for.
     */
    private fun effectiveMime(name: String, mime: String): String {
        val mapped = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: return mime
        val extension = name.substringAfterLast('.', "")
        return if (extension.equals(mapped, ignoreCase = true)) {
            mime
        } else {
            "application/octet-stream"
        }
    }

    /** Android 10+ — MediaStore is the only way to write to public Downloads. */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveWithMediaStore(name: String, mime: String, bytes: ByteArray): Uri? {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return null
        val written = try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) } != null
        } catch (e: Throwable) {
            false
        }

        if (!written) {
            resolver.delete(uri, null, null)
            return null
        }

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri
    }

    /** Android 9 and older — direct write to the public Downloads directory. */
    private fun saveLegacy(name: String, bytes: ByteArray): Uri? {
        return try {
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, name)
            file.writeBytes(bytes)
            Uri.fromFile(file)
        } catch (e: Throwable) {
            // Permission denied: fall back to the app-private external dir.
            try {
                val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                    ?: return null
                val file = File(dir, name)
                file.writeBytes(bytes)
                Uri.fromFile(file)
            } catch (e2: Throwable) {
                null
            }
        }
    }

    private fun toast(message: String) {
        activity.runOnUiThread {
            Toast.makeText(activity, message, Toast.LENGTH_SHORT).show()
        }
    }
}
