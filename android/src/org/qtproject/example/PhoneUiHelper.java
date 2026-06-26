package org.qtproject.example;

import android.app.Activity;
import android.graphics.Color;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowManager;

/** Themed status/navigation bars + inset query for phone shell safe-area fill. */
public final class PhoneUiHelper {
    // Bar colours must track Theme.banner (dark) / Theme.banner (light).
    private static final int DARK_BAR_COLOR = Color.parseColor("#0b1310");
    private static final int LIGHT_BAR_COLOR = Color.parseColor("#dfe8e2");

    private PhoneUiHelper() {}

    /** @param dark true = dark bars + light icons; false = light bars + dark icons. */
    public static void applySystemUi(Activity activity, boolean dark) {
        if (activity == null)
            return;
        Window window = activity.getWindow();
        if (window == null)
            return;
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
        int bar = dark ? DARK_BAR_COLOR : LIGHT_BAR_COLOR;
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(bar);
        View decor = window.getDecorView();
        int vis = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN;
        if (!dark) {
            // Dark icons/text on the light bars (API 23+ status, API 26+ nav).
            vis |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                 | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
        }
        decor.setSystemUiVisibility(vis);
        // Match Theme.banner so LAYOUT_FULLSCREEN never shows a black void above QML.
        decor.setBackgroundColor(bar);
        decor.requestApplyInsets();
    }

    /** @return {statusBarInsetPx, navigationBarInsetPx} in physical pixels. */
    public static int[] systemBarInsets(Activity activity) {
        int top = 0;
        int bottom = 0;
        if (activity == null)
            return new int[] { top, bottom };
        Window window = activity.getWindow();
        if (window == null)
            return new int[] { top, bottom };
        View decor = window.getDecorView();
        if (decor == null)
            return new int[] { top, bottom };
        int navDimen = dimenFallback(activity, "navigation_bar_height");
        WindowInsets wi = decor.getRootWindowInsets();
        if (wi != null) {
            top = wi.getStableInsetTop();
            bottom = wi.getStableInsetBottom();
            // LAYOUT_HIDE_NAVIGATION: stable bottom is often 0 while the system
            // window inset still reports the on-screen nav bar (Android 6 tablets).
            int sysBottom = wi.getSystemWindowInsetBottom();
            if (sysBottom > bottom)
                bottom = sysBottom;
            // Gesture insets are non-zero on hardware-key devices too; only apply
            // when the system already reports nav-bar overlap (software/gesture nav).
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                android.graphics.Insets gesture = wi.getSystemGestureInsets();
                if (gesture != null && gesture.bottom > 0 && sysBottom > 0 && bottom <= gesture.bottom)
                    bottom = gesture.bottom;
            }
            // Insets ready and zero => physical buttons / no soft-key band (Samsung).
            // Never substitute navigation_bar_height here — that dimen is non-zero even
            // when no on-screen nav bar consumes layout space.
        } else {
            top = dimenFallback(activity, "status_bar_height");
            // Insets not laid out yet; poll via refreshSystemInsets() until sysBottom appears.
            bottom = 0;
        }
        if (navDimen > 0 && bottom > navDimen)
            bottom = navDimen;
        if (bottom > 96)
            bottom = 96;
        return new int[] { top, bottom };
    }

    public static int statusBarInset(Activity activity) {
        return systemBarInsets(activity)[0];
    }

    public static int navigationBarInset(Activity activity) {
        return systemBarInsets(activity)[1];
    }

    private static int dimenFallback(Activity activity, String name) {
        if (activity == null)
            return 0;
        int resId = activity.getResources().getIdentifier(name, "dimen", "android");
        if (resId > 0)
            return activity.getResources().getDimensionPixelSize(resId);
        return 0;
    }
}
