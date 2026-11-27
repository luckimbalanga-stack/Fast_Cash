package cd.fastcash.fast_cash

import android.app.ActivityOptions
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat

/**
 * Notification système type appel entrant (CallStyle + fullScreenIntent)
 * pour faire remonter l'écran Fast-Cash au-dessus des autres apps / verrouillage.
 */
object IncomingCallNotifier {
    // v4 : sonnerie propriétaire Fast-Cash (res/raw/fastcash_ring) — le son du canal est immuable.
    const val CHANNEL_ID = "pdr_incoming_call_v4"
    const val NOTIF_ID = 71001
    const val ACTION_INCOMING = "cd.fastcash.fast_cash.INCOMING_CALL"
    const val EXTRA_CALL = "pdr_incoming_call"
    const val EXTRA_OPERATION_ID = "operation_id"
    const val EXTRA_PAYLOAD = "call_payload"
    const val EXTRA_WAIT = "wait_seconds"

    @Volatile
    private var lastRingedId: Int = -1

    @Volatile
    private var ringtonePlayer: MediaPlayer? = null

    /** Sonnerie intégrée (assets/fastCash.mp3 → res/raw/fastcash_ring). */
    private fun ringtoneUri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/${R.raw.fastcash_ring}")

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Anciens canaux (sonnerie téléphone) → suppression pour forcer la sonnerie app.
        manager.deleteNotificationChannel("pdr_incoming_call_v2")
        manager.deleteNotificationChannel("pdr_incoming_call_v3")
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Appels demandes Fast-Cash",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Affiche les demandes retrait/dépôt comme un appel entrant."
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(ringtoneUri(context), attrs)
        }
        manager.createNotificationChannel(channel)
    }

    /** Affiche la notif FSI + réveille l’écran + tente de ramener l’app immédiatement. */
    fun ring(
        context: Context,
        operationId: Int,
        title: String,
        body: String,
        callerName: String,
        waitSeconds: Int,
        payloadJson: String,
        force: Boolean = false,
    ) {
        if (!force && lastRingedId == operationId) {
            // Re-tente juste le bring-to-front si déjà sonné.
            bringAppToFront(context, operationId, waitSeconds, payloadJson)
            return
        }
        lastRingedId = operationId
        wakeScreen(context)
        show(context, operationId, title, body, callerName, waitSeconds, payloadJson)
        try {
            bringAppToFront(context, operationId, waitSeconds, payloadJson)
        } catch (_: Exception) {
            // BAL : la fullScreenIntent reste le filet de sécurité.
        }
    }

    fun show(
        context: Context,
        operationId: Int,
        title: String,
        body: String,
        callerName: String,
        waitSeconds: Int,
        payloadJson: String,
    ) {
        ensureChannel(context)
        val appContext = context.applicationContext
        val contentIntent = activityPendingIntent(appContext, operationId, waitSeconds, payloadJson, 1001)
        val acceptIntent = activityPendingIntent(appContext, operationId, waitSeconds, payloadJson, 1002)
        val refuseIntent = activityPendingIntent(appContext, operationId, waitSeconds, payloadJson, 1003)

        val caller = Person.Builder()
            .setName(callerName.ifBlank { "Client Fast-Cash" })
            .setImportant(true)
            .build()

        // Boucle la sonnerie Fast-Cash jusqu’à acceptation / refus / expiration.
        val looping = startRingtone(appContext)

        val builder = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(false)
            .setContentIntent(contentIntent)
            .setFullScreenIntent(contentIntent, true)
            .setTimeoutAfter((waitSeconds.coerceIn(5, 120) * 1000L))
            .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
            .addAction(0, "Refuser", refuseIntent)
            .addAction(0, "Accepter", acceptIntent)

        if (looping) {
            // Évite le double son (canal + MediaPlayer) : le MediaPlayer gère la sonnerie.
            builder.setSilent(true)
        } else {
            builder.setSound(ringtoneUri(appContext))
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setStyle(
                NotificationCompat.CallStyle.forIncomingCall(caller, refuseIntent, acceptIntent),
            )
        }

        val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIF_ID, builder.build())
    }

    fun dismiss(context: Context) {
        lastRingedId = -1
        stopRingtone()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIF_ID)
    }

    fun bringAppToFront(
        context: Context,
        operationId: Int,
        waitSeconds: Int,
        payloadJson: String,
    ) {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_INCOMING
            putExtra(EXTRA_CALL, true)
            putExtra(EXTRA_OPERATION_ID, operationId)
            putExtra(EXTRA_WAIT, waitSeconds)
            putExtra(EXTRA_PAYLOAD, payloadJson)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_USER_ACTION,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val options = ActivityOptions.makeBasic().apply {
                pendingIntentBackgroundActivityStartMode =
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            }
            context.startActivity(intent, options.toBundle())
        } else {
            ContextCompat.startActivity(context, intent, null)
        }
    }

    private fun startRingtone(context: Context): Boolean {
        stopRingtone()
        return try {
            val player = MediaPlayer().apply {
                setDataSource(context, ringtoneUri(context))
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                isLooping = true
                prepare()
                start()
            }
            ringtonePlayer = player
            true
        } catch (_: Exception) {
            ringtonePlayer = null
            false
        }
    }

    private fun stopRingtone() {
        try {
            ringtonePlayer?.run {
                if (isPlaying) stop()
                release()
            }
        } catch (_: Exception) {
        }
        ringtonePlayer = null
    }

    private fun wakeScreen(context: Context) {
        // Réveil bref uniquement pour l’appel — ne bloque pas la veille ensuite.
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wl = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "fastcash:incoming_call",
            )
            wl.acquire(2500L)
        } catch (_: Exception) {
        }
    }

    private fun activityPendingIntent(
        context: Context,
        operationId: Int,
        waitSeconds: Int,
        payloadJson: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_INCOMING
            putExtra(EXTRA_CALL, true)
            putExtra(EXTRA_OPERATION_ID, operationId)
            putExtra(EXTRA_WAIT, waitSeconds)
            putExtra(EXTRA_PAYLOAD, payloadJson)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }
}
