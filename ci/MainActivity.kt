package com.midihl.myune_music_android

import android.app.Activity
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.view.InputDevice
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.LinkedList

class MainActivity : FlutterActivity() {
    private val safChannel = "myune_music_android/saf"
    private val deviceChannel = "myune_music_android/device"
    private val inputEventChannel = "myune_music_android/input_events"
    private val requestOpenTree = 4201
    private var pendingTreeResult: MethodChannel.Result? = null
    private var inputSink: EventChannel.EventSink? = null
    // All SAF queries use the serial background task queue below.
    private val documentParents = HashMap<Uri, String>()
    private val lyricExtensions = setOf("lrc", "krc", "qrc", "yrc")
    private val maxScanEntries = 20_000
    private val maxLyricBytes = 512 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, safChannel, io.flutter.plugin.common.StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectoryTree" -> runOnUiThread { pickDirectoryTree(result) }
                "listAudioFiles" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri == null) {
                        result.error("INVALID", "treeUri is null", null)
                    } else {
                        try {
                            result.success(listAudioFiles(Uri.parse(treeUri)))
                        } catch (e: Exception) {
                            result.error("LIST_FAILED", e.message, null)
                        }
                    }
                }
                "readBytes" -> {
                    val uri = call.argument<String>("uri")
                    val maxBytes = call.argument<Int>("maxBytes") ?: (24 * 1024 * 1024)
                    if (uri == null) {
                        result.error("INVALID", "uri is null", null)
                    } else {
                        try {
                            result.success(readBytes(Uri.parse(uri), maxBytes))
                        } catch (e: Exception) {
                            result.error("READ_FAILED", e.message, null)
                        }
                    }
                }
                "getDisplayName" -> handleSafRead(call.argument<String>("uri"), result) { uri ->
                    queryDisplayName(uri)
                }
                "readSidecarLyrics" -> {
                    val extension = call.argument<String>("extension")
                    if (extension == null || extension !in lyricExtensions) {
                        result.error("INVALID", "Unsupported lyric file type", null)
                    } else {
                        handleSafRead(call.argument<String>("uri"), result) { uri ->
                            readSidecarLyrics(uri, extension)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Android TV 判定与输入设备信息。桌面端不会加载这个 Activity。
        MethodChannel(messenger, deviceChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> result.success(deviceInfo())
                else -> result.notImplemented()
            }
        }

        // 按键事件只做「广播」，不吞事件：方向键 / DPAD_CENTER / 字符输入仍由
        // Flutter 的焦点系统与文本输入链路处理，避免 TV 上出现双跳或无法打字。
        EventChannel(messenger, inputEventChannel).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    inputSink = events
                }

                override fun onCancel(arguments: Any?) {
                    inputSink = null
                }
            },
        )
    }

    private fun handleSafRead(
        rawUri: String?,
        result: MethodChannel.Result,
        read: (Uri) -> Any?,
    ) {
        if (rawUri == null) {
            result.error("INVALID", "uri is null", null)
            return
        }
        try {
            result.success(read(Uri.parse(rawUri)))
        } catch (error: Exception) {
            result.error("READ_FAILED", error.message, null)
        }
    }

    private fun deviceInfo(): Map<String, Any> {
        val pm = packageManager
        val leanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val television = pm.hasSystemFeature("android.hardware.type.television")
        val touchscreen = pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val tvMode = uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        return mapOf(
            "isTv" to (leanback || television || tvMode),
            "hasLeanback" to leanback,
            "hasTelevisionFeature" to television,
            "hasTouchscreen" to touchscreen,
            "uiModeTypeTelevision" to tvMode,
            "sdkInt" to Build.VERSION.SDK_INT,
        )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            val sink = inputSink
            if (sink != null) {
                val device = event.device
                sink.success(
                    mapOf(
                        "keyCode" to event.keyCode,
                        "repeat" to event.repeatCount,
                        "metaState" to event.metaState,
                        "source" to event.source,
                        "deviceId" to event.deviceId,
                        "deviceName" to (device?.name ?: ""),
                        "deviceDescriptor" to (device?.descriptor ?: ""),
                        "isGamepad" to event.isFromSource(InputDevice.SOURCE_GAMEPAD),
                        "isKeyboard" to event.isFromSource(InputDevice.SOURCE_KEYBOARD),
                    ),
                )
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun pickDirectoryTree(result: MethodChannel.Result) {
        if (pendingTreeResult != null) {
            result.error("BUSY", "directory picker already active", null)
            return
        }
        pendingTreeResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, requestOpenTree)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestOpenTree) return
        val result = pendingTreeResult ?: return
        pendingTreeResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val takeFlags = (data.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        ))
        try {
            contentResolver.takePersistableUriPermission(uri, takeFlags)
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("PERMISSION_FAILED", e.message, null)
        }
    }

    private fun listAudioFiles(treeUri: Uri): List<Map<String, String>> {
        val out = ArrayList<Map<String, String>>()
        val queue = LinkedList<String>()
        queue.add(DocumentsContract.getTreeDocumentId(treeUri))
        val audioExtensions = setOf(
            "wav", "wady", "wavarc", "flac", "alac", "ape", "mp3", "aac",
            "m4a", "ogg", "opus", "wma", "aiff", "pcm",
        )
        val seen = HashSet<String>()
        var visited = 0
        while (queue.isNotEmpty()) {
            val parentId = queue.removeFirst()
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
            val cursor = contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                ),
                null,
                null,
                null,
            ) ?: throw IllegalStateException("Directory provider returned no cursor")
            cursor.use { c ->
                while (c.moveToNext()) {
                    visited++
                    if (visited > maxScanEntries) {
                        throw IllegalStateException("Directory scan exceeded 20000 entries; existing playlist was kept")
                    }
                    val docId = getString(c, DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                        ?: throw IllegalStateException("Directory provider omitted document ID")
                    val name = getString(c, DocumentsContract.Document.COLUMN_DISPLAY_NAME) ?: docId
                    val mime = getString(c, DocumentsContract.Document.COLUMN_MIME_TYPE) ?: ""
                    val modified = getLong(c, DocumentsContract.Document.COLUMN_LAST_MODIFIED) ?: 0L
                    val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    if (!seen.add(docUri.toString())) continue
                    val isDirectory = mime == DocumentsContract.Document.MIME_TYPE_DIR
                    if (isDirectory) {
                        queue.add(docId)
                    } else {
                        val ext = name.substringAfterLast('.', "").lowercase()
                        val isAudio = mime.startsWith("audio/") ||
                            audioExtensions.contains(ext)
                        if (isAudio) {
                            documentParents[docUri] = parentId
                            out.add(
                                mapOf(
                                    "uri" to docUri.toString(),
                                    "displayName" to name,
                                    "mimeType" to mime,
                                    "lastModified" to modified.toString(),
                                )
                            )
                        }
                    }
                }
            }
        }
        return out
    }

    private fun queryDisplayName(uri: Uri): String? {
        return contentResolver.query(
            uri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) getString(cursor, DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            else null
        }
    }

    private fun findParentDocumentId(uri: Uri): String? {
        documentParents[uri]?.let { return it }
        val wantedId = DocumentsContract.getDocumentId(uri)
        val queue = LinkedList<String>()
        queue.add(DocumentsContract.getTreeDocumentId(uri))
        val visitedDirectories = HashSet<String>()
        var visited = 0
        while (queue.isNotEmpty()) {
            val parentId = queue.removeFirst()
            if (!visitedDirectories.add(parentId)) continue
            val cursor = contentResolver.query(
                DocumentsContract.buildChildDocumentsUriUsingTree(uri, parentId),
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null, null, null,
            ) ?: continue
            cursor.use { children ->
                while (children.moveToNext()) {
                    if (++visited > maxScanEntries) return null
                    val childId = getString(children, DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                        ?: continue
                    if (childId == wantedId) {
                        documentParents[uri] = parentId
                        return parentId
                    }
                    if (getString(children, DocumentsContract.Document.COLUMN_MIME_TYPE) ==
                        DocumentsContract.Document.MIME_TYPE_DIR
                    ) {
                        queue.add(childId)
                    }
                }
            }
        }
        return null
    }

    private fun readSidecarLyrics(uri: Uri, extension: String): ByteArray? {
        if (!DocumentsContract.isTreeUri(uri) || !DocumentsContract.isDocumentUri(this, uri)) {
            return null
        }
        val name = queryDisplayName(uri) ?: return null
        val expectedName = "${name.substringBeforeLast('.')}.$extension"
        val parentId = findParentDocumentId(uri) ?: return null
        val lyricsUri = contentResolver.query(
            DocumentsContract.buildChildDocumentsUriUsingTree(uri, parentId),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            ),
            null, null, null,
        )?.use { cursor ->
            var matched: Uri? = null
            var visited = 0
            while (cursor.moveToNext() && ++visited <= maxScanEntries) {
                val childName = getString(cursor, DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mime = getString(cursor, DocumentsContract.Document.COLUMN_MIME_TYPE)
                if (childName.equals(expectedName, ignoreCase = true) &&
                    mime != DocumentsContract.Document.MIME_TYPE_DIR
                ) {
                    val id = getString(cursor, DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                        ?: continue
                    matched = DocumentsContract.buildDocumentUriUsingTree(uri, id)
                    break
                }
            }
            matched
        } ?: return null
        val bytes = readBytes(lyricsUri, maxLyricBytes + 1)
        return bytes.takeIf { it.isNotEmpty() && it.size <= maxLyricBytes }
    }

    private fun readBytes(uri: Uri, maxBytes: Int): ByteArray {
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("openInputStream returned null")
        val out = ByteArrayOutputStream()
        input.use { stream ->
            val buffer = ByteArray(64 * 1024)
            var total = 0
            while (total < maxBytes) {
                val count = stream.read(buffer, 0, minOf(buffer.size, maxBytes - total))
                if (count <= 0) break
                out.write(buffer, 0, count)
                total += count
            }
        }
        return out.toByteArray()
    }

    private fun getString(cursor: Cursor, name: String): String? {
        val index = cursor.getColumnIndex(name)
        if (index < 0 || cursor.isNull(index)) return null
        return cursor.getString(index)
    }

    private fun getLong(cursor: Cursor, name: String): Long? {
        val index = cursor.getColumnIndex(name)
        if (index < 0 || cursor.isNull(index)) return null
        return cursor.getLong(index)
    }
}
