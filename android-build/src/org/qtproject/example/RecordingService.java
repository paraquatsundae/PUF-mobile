package org.qtproject.example;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.telephony.TelephonyManager;

import org.qtproject.qt5.android.bindings.QtActivity;

// Foreground service + wake lock so coverage recording continues with the screen
// off. Keeps TabletGps location updates alive in the same process.
public class RecordingService extends Service {
    private static final int NOTIF_ID = 9001;
    private static final String CHANNEL = "puf_recording";
    private static PowerManager.WakeLock sWakeLock;

    public static synchronized void start(Context ctx) {
        if (ctx == null) return;
        Intent i = new Intent(ctx, RecordingService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            ctx.startForegroundService(i);
        else
            ctx.startService(i);
    }

    public static synchronized void stop(Context ctx) {
        if (ctx == null) return;
        ctx.stopService(new Intent(ctx, RecordingService.class));
    }

    public static String cellularGeneration() {
        Context ctx = org.qtproject.qt5.android.QtNative.activity();
        if (ctx == null) return "";
        try {
            TelephonyManager tm = (TelephonyManager) ctx.getSystemService(Context.TELEPHONY_SERVICE);
            if (tm == null) return "";
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                switch (tm.getDataNetworkType()) {
                case TelephonyManager.NETWORK_TYPE_NR:
                    return "5G";
                case TelephonyManager.NETWORK_TYPE_LTE:
                case TelephonyManager.NETWORK_TYPE_HSPAP:
                case TelephonyManager.NETWORK_TYPE_HSPA:
                case TelephonyManager.NETWORK_TYPE_UMTS:
                case TelephonyManager.NETWORK_TYPE_HSDPA:
                case TelephonyManager.NETWORK_TYPE_HSUPA:
                    return "4G";
                default:
                    break;
                }
            }
            return "4G";
        } catch (SecurityException ignored) {
            return "";
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        ensureChannel();
        startForeground(NOTIF_ID, buildNotification());
        acquireWakeLock();
        TabletGps.start(17628);
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        releaseWakeLock();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    private void ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (nm == null) return;
        NotificationChannel ch = new NotificationChannel(
            CHANNEL, "Coverage recording", NotificationManager.IMPORTANCE_LOW);
        ch.setDescription("Keeps GPS and coverage recording active in the background");
        nm.createNotificationChannel(ch);
    }

    private Notification buildNotification() {
        Intent launch = new Intent(this, QtActivity.class);
        launch.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi = PendingIntent.getActivity(
            this, 0, launch,
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                ? PendingIntent.FLAG_IMMUTABLE : 0);
        Notification.Builder b = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
            ? new Notification.Builder(this, CHANNEL)
            : new Notification.Builder(this);
        return b.setContentTitle("PUF-mobile")
                .setContentText("Recording coverage")
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentIntent(pi)
                .setOngoing(true)
                .build();
    }

    private static void acquireWakeLock() {
        Context ctx = org.qtproject.qt5.android.QtNative.activity();
        if (ctx == null) return;
        if (sWakeLock != null && sWakeLock.isHeld()) return;
        PowerManager pm = (PowerManager) ctx.getSystemService(Context.POWER_SERVICE);
        if (pm == null) return;
        sWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "pufmobile:record");
        sWakeLock.acquire();
    }

    private static void releaseWakeLock() {
        if (sWakeLock != null && sWakeLock.isHeld())
            sWakeLock.release();
        sWakeLock = null;
    }
}
