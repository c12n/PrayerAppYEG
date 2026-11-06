package com.c12n.alrashidwidget

import android.app.Activity
import android.content.Intent
import com.google.android.gms.auth.GoogleAuthUtil
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.Scope
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.concurrent.thread

/// Settings cloud backup (v2.0.0, workstream 9 amendment): the
/// settings-backup JSON stored as one file in the user's Google
/// Drive appDataFolder — private to this app, invisible in the
/// user's Drive UI, and reachable only after the standard Google
/// sign-in flow in the app. No server of ours is involved: the app
/// talks to drive.googleapis.com directly with the user's token.
///
/// ACTIVATION NOTE: Google sign-in needs an OAuth client for this
/// package + signing certificate registered in a Google Cloud
/// project (the standard one-time console step for any Android app
/// using Google sign-in). Until that exists, sign-in fails and the
/// Dart side reports the file route instead — nothing crashes.
object DriveBackup {
    private const val REQUEST_SIGN_IN = 0xDB01
    private const val FILE_NAME = "AlRashidSettingsBackup.json"
    private const val LAST_BACKUP_KEY = "backup.lastDriveAt"
    private const val SCOPE = "https://www.googleapis.com/auth/drive.appdata"

    private var pendingResult: MethodChannel.Result? = null
    private var pendingAction: String? = null
    private var pendingJson: String? = null

    private fun signInOptions() = GoogleSignInOptions.Builder(
        GoogleSignInOptions.DEFAULT_SIGN_IN
    ).requestEmail()
        .requestScopes(Scope(SCOPE))
        .build()

    /// Entry point for the 'alrashid/backup' channel methods that
    /// need Drive. Ensures sign-in (launching the system flow when
    /// needed), then runs the action on a worker thread.
    fun run(
        activity: Activity,
        action: String,
        json: String?,
        result: MethodChannel.Result
    ) {
        val account = GoogleSignIn.getLastSignedInAccount(activity)
        if (account != null) {
            execute(activity, action, json, result)
            return
        }
        pendingResult = result
        pendingAction = action
        pendingJson = json
        val client = GoogleSignIn.getClient(activity, signInOptions())
        activity.startActivityForResult(client.signInIntent, REQUEST_SIGN_IN)
    }

    fun onActivityResult(
        activity: Activity,
        requestCode: Int,
        data: Intent?
    ): Boolean {
        if (requestCode != REQUEST_SIGN_IN) return false
        val result = pendingResult ?: return true
        val action = pendingAction ?: return true
        val json = pendingJson
        pendingResult = null
        pendingAction = null
        pendingJson = null
        val task = GoogleSignIn.getSignedInAccountFromIntent(data)
        if (task.isSuccessful) {
            execute(activity, action, json, result)
        } else {
            result.success(if (action == "driveRestore") null else false)
        }
        return true
    }

    fun lastBackupMillis(activity: Activity): Long =
        activity.getSharedPreferences("alrashid_backup", Activity.MODE_PRIVATE)
            .getLong(LAST_BACKUP_KEY, 0L)

    private fun execute(
        activity: Activity,
        action: String,
        json: String?,
        result: MethodChannel.Result
    ) {
        thread {
            try {
                val account = GoogleSignIn.getLastSignedInAccount(activity)
                    ?: throw IllegalStateException("not signed in")
                val token = GoogleAuthUtil.getToken(
                    activity, account.account!!, "oauth2:$SCOPE")
                when (action) {
                    "driveBackup" -> {
                        upload(token, json ?: "")
                        activity.getSharedPreferences(
                            "alrashid_backup", Activity.MODE_PRIVATE)
                            .edit()
                            .putLong(LAST_BACKUP_KEY, System.currentTimeMillis())
                            .apply()
                        activity.runOnUiThread { result.success(true) }
                    }
                    "driveRestore" -> {
                        val text = download(token)
                        activity.runOnUiThread { result.success(text) }
                    }
                    else -> activity.runOnUiThread { result.notImplemented() }
                }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.success(if (action == "driveRestore") null else false)
                }
            }
        }
    }

    private fun request(
        token: String,
        method: String,
        url: String,
        body: String?,
        contentType: String
    ): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = method
        conn.setRequestProperty("Authorization", "Bearer $token")
        if (body != null) {
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", contentType)
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use {
                it.write(body)
            }
        }
        val code = conn.responseCode
        val stream = if (code in 200..299) conn.inputStream else conn.errorStream
        val text = stream?.let {
            BufferedReader(InputStreamReader(it, Charsets.UTF_8)).readText()
        } ?: ""
        if (code !in 200..299) throw IllegalStateException("Drive HTTP $code")
        return text
    }

    private fun findFileId(token: String): String? {
        val q = URLEncoder.encode("name='$FILE_NAME'", "UTF-8")
        val text = request(
            token, "GET",
            "https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&fields=files(id)&q=$q",
            null, "application/json")
        val files = JSONObject(text).optJSONArray("files")
        return if (files != null && files.length() > 0) {
            files.getJSONObject(0).getString("id")
        } else {
            null
        }
    }

    private fun upload(token: String, json: String) {
        val existing = findFileId(token)
        if (existing != null) {
            request(
                token, "PATCH",
                "https://www.googleapis.com/upload/drive/v3/files/$existing?uploadType=media",
                json, "application/json")
        } else {
            val boundary = "alrashid-backup-boundary"
            val metadata =
                JSONObject().put("name", FILE_NAME)
                    .put("parents", JSONArray().put("appDataFolder"))
                    .toString()
            val body = "--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n" +
                "$metadata\r\n--$boundary\r\nContent-Type: application/json\r\n\r\n" +
                "$json\r\n--$boundary--"
            request(
                token, "POST",
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart",
                body, "multipart/related; boundary=$boundary")
        }
    }

    private fun download(token: String): String? {
        val id = findFileId(token) ?: return null
        return request(
            token, "GET",
            "https://www.googleapis.com/drive/v3/files/$id?alt=media",
            null, "application/json")
    }
}
