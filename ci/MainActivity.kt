package com.midihl.myune_music_android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.LinkedList

class MainActivity : FlutterActivity() {
    private val channel = "myune_music_android/saf"
    private val requestOpenTree = 4201
    private var pendingTreeResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectoryTree" -> pickDirectoryTree(result)
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
                "exists" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("INVALID", "uri is null", null)
                    } else {
                        result.success(documentExists(Uri.parse(uri)))
                    }
                }
                "viewDocument" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("INVALID", "uri is null", null)
                    } else {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.parse(uri), "audio/*")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("VIEW_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
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
            // ACTION_OPEN_DOCUMENT_TREE 返回的是读授权；只请求实际持有的 flags，
            // 避免某些 DocumentsProvider 因 WRITE 未授予而拒绝持久化。
            val persistFlags = takeFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            contentResolver.takePersistableUriPermission(uri, persistFlags)
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("PERMISSION_FAILED", e.message, null)
        }
    }

    private fun listAudioFiles(treeUri: Uri): List<Map<String, String>> {
        val out = ArrayList<Map<String, String>>()
        val queue = LinkedList<Uri>()
        queue.add(
            DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
            )
        )
        val audioExtensions = setOf(
            "mp3", "flac", "wav", "aac", "m4a", "ogg", "wma", "ape",
            "alac", "opus", "aiff", "aif", "wady", "wavarc", "pcm",
        )
        val seen = HashSet<String>()
        var visited = 0
        while (queue.isNotEmpty() && visited < 20000) {
            val childrenUri = queue.removeFirst()
            val cursor = try {
                contentResolver.query(
                    childrenUri,
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                        DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                        DocumentsContract.Document.COLUMN_SIZE,
                    ),
                    null,
                    null,
                    null,
                ) ?: throw IllegalStateException("无法枚举目录：$childrenUri")
            } catch (e: Exception) {
                throw IllegalStateException("SAF 目录读取失败：$childrenUri (${e.message})", e)
            }
            cursor.use { c ->
                while (c.moveToNext() && visited < 20000) {
                    visited++
                    val docId = getString(c, DocumentsContract.Document.COLUMN_DOCUMENT_ID) ?: continue
                    val name = getString(c, DocumentsContract.Document.COLUMN_DISPLAY_NAME) ?: docId
                    val mime = getString(c, DocumentsContract.Document.COLUMN_MIME_TYPE) ?: ""
                    val modified = getLong(c, DocumentsContract.Document.COLUMN_LAST_MODIFIED) ?: 0L
                    val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    if (!seen.add(docUri.toString())) continue
                    val isDirectory = mime == DocumentsContract.Document.MIME_TYPE_DIR
                    if (isDirectory) {
                        queue.add(
                            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
                        )
                    } else {
                        val ext = name.substringAfterLast('.', "").lowercase()
                        val isAudio = mime.startsWith("audio/") ||
                            audioExtensions.contains(ext)
                        if (isAudio) {
                            out.add(
                                mapOf(
                                    "uri" to docUri.toString(),
                                    "displayName" to name,
                                    "mimeType" to mime,
                                    "lastModified" to modified.toString(),
                                    "size" to (getLong(c, DocumentsContract.Document.COLUMN_SIZE) ?: 0L).toString(),
                                )
                            )
                        }
                    }
                }
            }
        }
        return out
    }

    private fun documentExists(uri: Uri): Boolean {
        return try {
            contentResolver.openInputStream(uri)?.use { true } ?: false
        } catch (_: Exception) {
            false
        }
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
