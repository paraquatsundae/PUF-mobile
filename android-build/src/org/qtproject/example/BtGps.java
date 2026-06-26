package org.qtproject.example;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;

import java.io.InputStream;
import java.lang.reflect.Method;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.util.Set;
import java.util.UUID;

// Connects to a paired Bluetooth device exposing the Serial Port Profile (SPP /
// RFCOMM) -- e.g. the bt_gps_host.py running on a laptop or Pi, or any off-the-shelf
// Bluetooth GPS receiver -- and forwards every received byte to the native side over
// localhost UDP, exactly like JdUsbCan does for USB. Pure Android SDK, no deps.
// Called from C++ (BtGpsSource) via JNI.
public class BtGps {
    // Standard SPP service UUID.
    private static final UUID SPP =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");

    private static volatile boolean sRunning = false;
    private static Thread sThread;
    private static BluetoothSocket sSocket;
    private static String sReport = "";

    public static synchronized String report() { return sReport; }

    // Bonded devices as "name\tMAC" lines (\n separated) for the connection UI.
    public static String pairedDevices() {
        BluetoothAdapter ad = BluetoothAdapter.getDefaultAdapter();
        if (ad == null) return "";
        Set<BluetoothDevice> bonded;
        try {
            bonded = ad.getBondedDevices();
        } catch (SecurityException e) {
            return "";
        }
        if (bonded == null || bonded.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (BluetoothDevice d : bonded) {
            String name = d.getName();
            if (name == null) name = "(unknown)";
            sb.append(name).append('\t').append(d.getAddress()).append('\n');
        }
        return sb.toString();
    }

    public static synchronized String start(int udpPort, String mac, int channel) {
        stop();
        BluetoothAdapter ad = BluetoothAdapter.getDefaultAdapter();
        if (ad == null) { sReport = "no Bluetooth adapter"; return sReport; }
        if (!ad.isEnabled()) { sReport = "turn Bluetooth on first"; return sReport; }
        if (mac == null || mac.length() < 11) { sReport = "no device selected"; return sReport; }

        BluetoothDevice dev;
        try {
            dev = ad.getRemoteDevice(mac);
        } catch (IllegalArgumentException e) {
            sReport = "bad MAC " + mac; return sReport;
        }
        try { ad.cancelDiscovery(); } catch (Exception ignored) {}

        BluetoothSocket sock = null;
        String how = "uuid";
        try {
            // Preferred: SDP lookup of the SPP service (works against Windows + most
            // BT GPS pucks, which publish an SPP service record).
            sock = dev.createRfcommSocketToServiceRecord(SPP);
            sock.connect();
        } catch (Exception e1) {
            // Fallback: connect to a fixed RFCOMM channel (for servers without an SDP
            // record, e.g. a Pi using the built-in socket). Uses the hidden reflection
            // method that is widely relied upon for exactly this case.
            try { if (sock != null) sock.close(); } catch (Exception ignored) {}
            try {
                Method m = dev.getClass().getMethod("createRfcommSocket", int.class);
                sock = (BluetoothSocket) m.invoke(dev, channel);
                sock.connect();
                how = "ch" + channel;
            } catch (Exception e2) {
                sReport = "connect failed: " + e1.getMessage() + " / " + e2.getMessage();
                return sReport;
            }
        }

        sSocket = sock;
        sRunning = true;
        final BluetoothSocket fsock = sock;
        final int port = udpPort;
        sThread = new Thread(new Runnable() {
            public void run() {
                DatagramSocket out = null;
                try {
                    InputStream in = fsock.getInputStream();
                    out = new DatagramSocket();
                    InetAddress local = InetAddress.getByName("127.0.0.1");
                    byte[] buf = new byte[512];
                    while (sRunning) {
                        int n = in.read(buf);
                        if (n > 0)
                            out.send(new DatagramPacket(buf, n, local, port));
                        else if (n < 0)
                            break; // stream closed
                    }
                } catch (Exception ignored) {
                } finally {
                    if (out != null) out.close();
                }
            }
        });
        sThread.start();

        String name = dev.getName();
        sReport = "connected (" + how + ") to " + (name == null ? mac : name);
        return sReport;
    }

    public static synchronized void stop() {
        sRunning = false;
        if (sSocket != null) {
            try { sSocket.close(); } catch (Exception ignored) {}
            sSocket = null;
        }
        if (sThread != null) {
            try { sThread.join(600); } catch (InterruptedException ignored) {}
            sThread = null;
        }
    }
}
