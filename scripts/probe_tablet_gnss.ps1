# Read-only probe to discover how the Allwinner T3 tablet exposes its internal
# GNSS receiver (fed by the BT-770 antenna over coax). Run with USB debugging
# enabled and the device authorized. Nothing here writes to the device.

$adb = 'C:\Android\Sdk\platform-tools\adb.exe'

function Section($t) { Write-Host ''; Write-Host "==== $t ====" -ForegroundColor Cyan }

Section 'Devices'
& $adb devices -l

Section 'Identity'
& $adb shell getprop ro.product.model
& $adb shell getprop ro.product.manufacturer
& $adb shell getprop ro.build.version.release
& $adb shell getprop ro.build.version.sdk

Section 'GNSS-related system properties'
& $adb shell "getprop | grep -iE 'gps|gnss|location|serial|tty|baud'"

Section 'Serial device nodes (internal UARTs)'
& $adb shell "ls -l /dev/ttyS* /dev/ttyHS* /dev/ttyMT* /dev/s3c* 2>/dev/null"

Section 'USB serial nodes (if a USB receiver is attached)'
& $adb shell "ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null"

Section 'Kernel log GNSS/GPS hits (dmesg may need root)'
& $adb shell "dmesg 2>/dev/null | grep -iE 'gps|gnss|ttyS|uart' | tail -n 40"

Section 'Location providers'
& $adb shell "dumpsys location | grep -iE 'provider|gps|nmea|last location' | head -n 40"

Section 'gps.conf / vendor GNSS config'
& $adb shell "cat /system/etc/gps.conf 2>/dev/null; cat /vendor/etc/gps.conf 2>/dev/null"

Section 'Try reading candidate UARTs (1s each, common bauds)'
foreach ($node in @('/dev/ttyS0','/dev/ttyS1','/dev/ttyS2','/dev/ttyS3','/dev/ttyS4')) {
    foreach ($baud in @(9600, 38400, 115200)) {
        Write-Host "-- $node @ $baud --"
        & $adb shell "if [ -r $node ]; then (stty -F $node $baud 2>/dev/null; timeout 1 cat $node 2>/dev/null | head -c 200); else echo 'not readable'; fi"
        Write-Host ''
    }
}

Section 'Done'
Write-Host 'Look for lines starting with $GxGGA / $GxRMC = raw NMEA on an internal UART.'
