package org.qtproject.example;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;

import org.qtproject.qt5.android.QtNative;

// Opens an slcan/LAWICEL USB-CAN adapter (CDC-ACM) via the Android USB-host API,
// sends the slcan bring-up (close, 250 kbps, open) and forwards every received
// byte to the native side over localhost UDP. Pure Android SDK -- no external
// dependency. Called from C++ (CanGpsSource) via JNI.
public class JdUsbCan {
    private static final String ACTION_PERM = "org.qtproject.example.USB_PERMISSION";

    // Implemented in the native lib (cangpssource.cpp). Evicts the in-kernel cdc_acm
    // driver via USBDEVFS_DISCONNECT + CLAIMINTERFACE on the raw fd, for kernels where
    // claimInterface(force=true) returns true but does not actually detach.
    private static native int nativeDetach(int fd, int ifno);
    private static native int nativeReset(int fd);
    // Raw usbfs control/bulk transfers (Android's UsbDeviceConnection transfer
    // methods return -1 on this device even though the raw fd works).
    private static native int nativeControl(int fd, int reqType, int req, int val,
                                            int idx, byte[] data, int len, int timeout);
    private static native int nativeBulk(int fd, int ep, byte[] data, int len, int timeout);

    private static volatile boolean sRunning = false;
    private static Thread sThread;
    private static UsbDeviceConnection sConn;
    private static UsbInterface sIface;
    private static UsbDevice sDev;
    private static BroadcastReceiver sReceiver;
    private static int sUdpPort = 17626;
    private static int sBaud = 115200;
    private static int sCanBitrate = 250000;

    private static char slcanCode(int bitrate) {
        switch (bitrate) {
            case 10000:   return '0';
            case 20000:   return '1';
            case 50000:   return '2';
            case 100000:  return '3';
            case 125000:  return '4';
            case 250000:  return '5';
            case 500000:  return '6';
            case 800000:  return '7';
            case 1000000: return '8';
            default:      return '5';
        }
    }

    public static synchronized String start(int udpPort, int baud, int canBitrate) {
        stop();
        sUdpPort = udpPort;
        sBaud = baud;
        sCanBitrate = canBitrate;
        Context ctx = QtNative.activity();
        if (ctx == null) return "no activity";
        UsbManager mgr = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);
        if (mgr == null) return "no USB service";
        UsbDevice dev = findDevice(mgr);
        if (dev == null) return "no USB-CAN device plugged in";
        if (!mgr.hasPermission(dev)) {
            requestPermission(ctx, mgr, dev);
            return "asking USB permission (tap OK)";
        }
        return open(mgr, dev);
    }

    // Last bring-up report, surfaced to the status line for blind debugging.
    private static String sReport = "";

    public static synchronized String report() { return sReport; }

    private static boolean knownCanVid(int vid) {
        // CANable slcan (OpenMoko 16D0:117E), candleLight 1D50, ST 0483, FTDI 0403,
        // Silabs CP210x 10C4, WCH CH340 1A86 (common on cheap slcan clones).
        return vid == 0x16D0 || vid == 0x1D50 || vid == 0x0483 ||
               vid == 0x0403 || vid == 0x10C4 || vid == 0x1A86;
    }

    private static UsbDevice findDevice(UsbManager mgr) {
        UsbDevice fallback = null;
        for (UsbDevice d : mgr.getDeviceList().values()) {
            if (pickInterface(d) == null) continue;
            if (knownCanVid(d.getVendorId())) return d; // prefer a known CAN adapter
            if (fallback == null) fallback = d;
        }
        return fallback;
    }

    // First interface that exposes both a bulk IN and bulk OUT endpoint
    // (the CDC-ACM data interface on an slcan adapter).
    private static UsbInterface pickInterface(UsbDevice d) {
        for (int i = 0; i < d.getInterfaceCount(); ++i) {
            UsbInterface intf = d.getInterface(i);
            boolean in = false, out = false;
            for (int e = 0; e < intf.getEndpointCount(); ++e) {
                UsbEndpoint ep = intf.getEndpoint(e);
                if (ep.getType() != UsbConstants.USB_ENDPOINT_XFER_BULK) continue;
                if (ep.getDirection() == UsbConstants.USB_DIR_IN) in = true; else out = true;
            }
            if (in && out) return intf;
        }
        return null;
    }

    // CDC Communications interface (class 0x02) -> target for class control
    // requests (SET_LINE_CODING / SET_CONTROL_LINE_STATE). Falls back to 0.
    private static int commInterfaceIndex(UsbDevice d) {
        for (int i = 0; i < d.getInterfaceCount(); ++i) {
            if (d.getInterface(i).getInterfaceClass() == 2) // CDC Communications
                return d.getInterface(i).getId();
        }
        return 0;
    }

    private static void requestPermission(Context ctx, final UsbManager mgr, final UsbDevice dev) {
        if (sReceiver != null) {
            try { ctx.unregisterReceiver(sReceiver); } catch (Exception ignored) {}
        }
        sReceiver = new BroadcastReceiver() {
            public void onReceive(Context c, Intent intent) {
                if (!ACTION_PERM.equals(intent.getAction())) return;
                if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
                    open(mgr, dev);
            }
        };
        ctx.registerReceiver(sReceiver, new IntentFilter(ACTION_PERM));
        PendingIntent pi = PendingIntent.getBroadcast(
                ctx, 0, new Intent(ACTION_PERM), PendingIntent.FLAG_UPDATE_CURRENT);
        mgr.requestPermission(dev, pi);
    }

    private static synchronized String open(UsbManager mgr, UsbDevice dev) {
        UsbInterface intf = pickInterface(dev);
        if (intf == null) return "no bulk interface";
        UsbEndpoint epIn = null, epOut = null;
        for (int e = 0; e < intf.getEndpointCount(); ++e) {
            UsbEndpoint ep = intf.getEndpoint(e);
            if (ep.getType() != UsbConstants.USB_ENDPOINT_XFER_BULK) continue;
            if (ep.getDirection() == UsbConstants.USB_DIR_IN) epIn = ep; else epOut = ep;
        }
        if (epIn == null || epOut == null) return "no bulk endpoints";

        final UsbDeviceConnection conn = mgr.openDevice(dev);
        if (conn == null) return "openDevice failed";
        int fd = conn.getFileDescriptor();

        // Evict the in-kernel cdc_acm driver for real (claimInterface(force) is a
        // no-op on this kernel). Native USBDEVFS_DISCONNECT + CLAIMINTERFACE on fd.
        StringBuilder det = new StringBuilder("det=");
        for (int i = 0; i < dev.getInterfaceCount(); ++i) {
            int d;
            try { d = nativeDetach(fd, i); }
            catch (Throwable t) { d = -1000; } // native symbol missing
            det.append(i == 0 ? "" : ",").append(d);
        }

        // Also take the Java-side claim so UsbDeviceConnection tracks ownership.
        int claimedN = 0;
        for (int i = 0; i < dev.getInterfaceCount(); ++i) {
            if (conn.claimInterface(dev.getInterface(i), true)) ++claimedN;
        }
        boolean claimed = claimedN > 0;
        sConn = conn;
        sIface = intf;
        sDev = dev;

        sleep(120); // let the detach settle before any I/O

        final int outAddr = epOut.getAddress() & 0xff;
        final int inAddr = epIn.getAddress() & 0xff;
        final int commIdx = commInterfaceIndex(dev);

        // CDC-ACM line coding (baud 8N1) + DTR|RTS, via raw usbfs (Android's wrappers
        // fail on this device).
        int lc = nativeControl(fd, 0x21, 0x20, 0, commIdx, lineCoding(sBaud), 7, 2000);
        int dtr = nativeControl(fd, 0x21, 0x22, 0x03, commIdx, null, 0, 2000);

        // slcan bring-up sent as discrete, settled commands (mirrors python-can):
        //   C  close channel | S<n>  set CAN bitrate | O  open channel
        int wClose = writeCmd(fd, outAddr, "C");
        sleep(40);
        int wRate  = writeCmd(fd, outAddr, "S" + slcanCode(sCanBitrate));
        sleep(40);
        int wOpen  = writeCmd(fd, outAddr, "O");
        sleep(40);

        // Test read: distinguishes a dead OUT pipe from a dead device. >=0 means the
        // IN pipe is alive (0 = no bytes yet), -1 means read itself failed.
        int rd = nativeBulk(fd, inAddr, new byte[64], 64, 400);

        // Topology: device class + each interface id:class, to confirm the layout.
        StringBuilder topo = new StringBuilder();
        topo.append("dc").append(dev.getDeviceClass());
        for (int i = 0; i < dev.getInterfaceCount(); ++i)
            topo.append(" i").append(dev.getInterface(i).getId())
                .append("c").append(dev.getInterface(i).getInterfaceClass());

        sReport = String.format(
            "%04X:%04X %s data%d in%02X out%02X fd=%d %s claim=%d/%d lc=%d dtr=%d C=%d S%c=%d O=%d rd=%d",
            dev.getVendorId(), dev.getProductId(), topo.toString(),
            intf.getId(), epIn.getAddress() & 0xff, epOut.getAddress() & 0xff,
            fd, det.toString(), claimedN, dev.getInterfaceCount(),
            lc, dtr, wClose, slcanCode(sCanBitrate), wRate, wOpen, rd);

        final int readFd = fd;
        final int readAddr = inAddr;
        final int port = sUdpPort;
        sRunning = true;
        sThread = new Thread(new Runnable() {
            public void run() {
                DatagramSocket sock = null;
                try {
                    sock = new DatagramSocket();
                    InetAddress local = InetAddress.getByName("127.0.0.1");
                    byte[] buf = new byte[256];
                    while (sRunning) {
                        int n = nativeBulk(readFd, readAddr, buf, buf.length, 250);
                        if (n > 0)
                            sock.send(new DatagramPacket(buf, n, local, port));
                        else if (n < 0)
                            sleep(5); // timeout/err: avoid a hot spin
                    }
                } catch (Exception ignored) {
                } finally {
                    if (sock != null) sock.close();
                }
            }
        });
        sThread.start();
        return "opened " + (sCanBitrate / 1000) + "k  " + sReport;
    }

    private static int writeCmd(int fd, int outAddr, String cmd) {
        byte[] b = (cmd + "\r").getBytes();
        return nativeBulk(fd, outAddr, b, b.length, 2000);
    }

    private static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException ignored) {}
    }

    private static byte[] lineCoding(int baud) {
        byte[] lc = new byte[7];
        lc[0] = (byte) (baud & 0xff);
        lc[1] = (byte) ((baud >> 8) & 0xff);
        lc[2] = (byte) ((baud >> 16) & 0xff);
        lc[3] = (byte) ((baud >> 24) & 0xff);
        lc[4] = 0; // 1 stop bit
        lc[5] = 0; // no parity
        lc[6] = 8; // 8 data bits
        return lc;
    }

    public static synchronized void stop() {
        sRunning = false;
        if (sThread != null) {
            try { sThread.join(600); } catch (InterruptedException ignored) {}
            sThread = null;
        }
        if (sConn != null) {
            try {
                if (sDev != null)
                    for (int i = 0; i < sDev.getInterfaceCount(); ++i)
                        sConn.releaseInterface(sDev.getInterface(i));
                else if (sIface != null)
                    sConn.releaseInterface(sIface);
            } catch (Exception ignored) {}
            sConn.close();
            sConn = null;
        }
        sIface = null;
        sDev = null;
        Context ctx = QtNative.activity();
        if (ctx != null && sReceiver != null) {
            try { ctx.unregisterReceiver(sReceiver); } catch (Exception ignored) {}
        }
        sReceiver = null;
    }
}
