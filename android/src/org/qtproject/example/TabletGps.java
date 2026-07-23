package org.qtproject.example;

import android.content.Context;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Bundle;
import android.os.HandlerThread;

import org.qtproject.qt5.android.QtNative;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;

// Streams the tablet's own GNSS fixes (Android LocationManager) to the native side
// over localhost UDP, mirroring the JdUsbCan / BtGps Java->UDP pattern. Each fix is
// sent as a compact "TGPS,lat,lon,alt,speedKmh,bearing,sats,hdop" line; the C++
// TabletGpsSource turns it into a $PANDA sentence for GpsModel. The location runtime
// permission is requested on the C++ side (QtAndroid) before start() is called, so a
// SecurityException here only means the grant was refused. Pure Android SDK, no deps.
public class TabletGps {
    private static volatile boolean sRunning = false;
    private static LocationManager sLm;
    private static LocationListener sListener;
    private static HandlerThread sThread;
    private static DatagramSocket sOut;
    private static InetAddress sLocal;
    private static int sPort;
    private static String sReport = "";
    private static volatile int sFixes = 0;

    public static synchronized String report() { return sReport; }

    public static synchronized String start(int udpPort) {
        stop();
        Context ctx = QtNative.activity();
        if (ctx == null) { sReport = "no activity context"; return sReport; }
        sLm = (LocationManager) ctx.getSystemService(Context.LOCATION_SERVICE);
        if (sLm == null) { sReport = "no LocationManager"; return sReport; }

        sPort = udpPort;
        sFixes = 0;
        try {
            sOut = new DatagramSocket();
            sLocal = InetAddress.getByName("127.0.0.1");
        } catch (Exception e) {
            sReport = "udp init failed: " + e.getMessage();
            return sReport;
        }

        sListener = new LocationListener() {
            public void onLocationChanged(Location loc) { send(loc); }
            public void onStatusChanged(String p, int s, Bundle b) {}
            public void onProviderEnabled(String p) {}
            public void onProviderDisabled(String p) {}
        };

        sThread = new HandlerThread("TabletGps");
        sThread.start();
        sRunning = true;
        try {
            boolean any = false;
            if (sLm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                sLm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 200, 0f,
                                           sListener, sThread.getLooper());
                any = true;
                // Seed immediately from the last known fix so the map can frame
                // before the first live update arrives.
                Location last = sLm.getLastKnownLocation(LocationManager.GPS_PROVIDER);
                if (last != null) send(last);
            }
            // Network provider as a coarse fallback (cold start / indoors on bench).
            if (sLm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                sLm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000, 0f,
                                           sListener, sThread.getLooper());
                any = true;
            }
            sReport = any ? "listening (GNSS)" : "no location provider enabled";
        } catch (SecurityException se) {
            sReport = "location permission denied";
        } catch (Exception e) {
            sReport = "start failed: " + e.getMessage();
        }
        return sReport;
    }

    private static void send(Location loc) {
        if (loc == null || !sRunning || sOut == null)
            return;
        double lat = loc.getLatitude();
        double lon = loc.getLongitude();
        String alt = loc.hasAltitude() ? String.valueOf(loc.getAltitude()) : "";
        double speedMs = loc.hasSpeed() ? loc.getSpeed() : 0.0;
        String spd = loc.hasSpeed() ? String.valueOf(speedMs * 3.6) : ""; // m/s -> km/h
        // Android bearing is often stale/wrong below ~2 m/s — omit it so the
        // native filter derives heading from the smoothed track instead.
        String brg = "";
        if (loc.hasBearing() && speedMs >= 2.0f)
            brg = String.valueOf(loc.getBearing());
        String sats = "";
        try {
            Bundle ex = loc.getExtras();
            if (ex != null && ex.containsKey("satellites"))
                sats = String.valueOf(ex.getInt("satellites"));
        } catch (Exception ignored) {}
        // HDOP is not exposed by android.location.Location; left blank (honest).
        String line = "TGPS," + lat + "," + lon + "," + alt + "," + spd + ","
                    + brg + "," + sats + "," + "" + "\n";
        try {
            byte[] b = line.getBytes("US-ASCII");
            sOut.send(new DatagramPacket(b, b.length, sLocal, sPort));
            sFixes++;
            sReport = "live (" + sFixes + " fixes)";
        } catch (Exception ignored) {}
    }

    public static synchronized void stop() {
        sRunning = false;
        if (sLm != null && sListener != null) {
            try { sLm.removeUpdates(sListener); } catch (Exception ignored) {}
        }
        sListener = null;
        if (sThread != null) {
            try { sThread.quitSafely(); } catch (Exception ignored) {}
            sThread = null;
        }
        if (sOut != null) {
            try { sOut.close(); } catch (Exception ignored) {}
            sOut = null;
        }
        sLm = null;
    }
}
