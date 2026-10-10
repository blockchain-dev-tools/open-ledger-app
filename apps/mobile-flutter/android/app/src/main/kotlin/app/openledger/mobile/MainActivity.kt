package app.openledger.mobile

import android.content.ComponentName
import android.content.pm.PackageManager
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "LauncherDisguise"
        private const val SCREEN_SECURITY_CHANNEL = "app.openledger/screen_security"
        private const val LAUNCHER_DISGUISE_CHANNEL = "app.openledger/launcher_disguise"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ADR-011 §6: block screenshots / screen recording / the recents
        // thumbnail while a secret is on screen. Driven by the Dart-side
        // PrivacyShield, which only wraps the seed and private-key screens.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCREEN_SECURITY_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "disable" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ADR-012: launcher disguise — swap the desktop icon + label by
        // toggling which activity-alias owns the MAIN/LAUNCHER intent-filter.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LAUNCHER_DISGUISE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "apply" -> {
                    val disguise = call.argument<String>("disguise")
                    if (disguise != "standard" && disguise != "calculator") {
                        result.error("INVALID_ARGUMENT", "disguise must be standard|calculator", null)
                        return@setMethodCallHandler
                    }
                    applyLauncherAlias(disguise == "calculator")
                    result.success(null)
                }
                "current" -> result.success(currentLauncherAlias())
                else -> result.notImplemented()
            }
        }
    }

    /** Enable the target alias FIRST, then disable the other — enabling first
     *  avoids a window where no launcher entry exists at all. DONT_KILL_APP
     *  keeps this process alive; the launcher refreshes within seconds.
     *  Alias names are relative to the app package and must match
     *  AndroidManifest.xml (ADR-012). */
    private fun applyLauncherAlias(calculator: Boolean) {
        val pm = packageManager
        // ComponentName(Context, String) does NOT expand a leading '.' — the
        // alias class must be fully qualified or PMS rejects it with
        // "Component class ... does not exist".
        val standard = ComponentName(this, "$packageName.LauncherAliasStandard")
        val calculatorAlias = ComponentName(this, "$packageName.LauncherAliasCalculator")
        val enable = if (calculator) calculatorAlias else standard
        val disable = if (calculator) standard else calculatorAlias
        Log.i(TAG, "applyLauncherAlias calculator=$calculator")
        try {
            pm.setComponentEnabledSetting(
                enable,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            Log.i(TAG, "enable(${enable.shortClassName}) -> state=${pm.getComponentEnabledSetting(enable)}")
            pm.setComponentEnabledSetting(
                disable,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            Log.i(TAG, "disable(${disable.shortClassName}) -> state=${pm.getComponentEnabledSetting(disable)}")
        } catch (e: Exception) {
            Log.e(TAG, "applyLauncherAlias failed", e)
        }
    }

    /** The currently enabled alias. COMPONENT_ENABLED_STATE_DEFAULT resolves to
     *  the manifest defaults (standard enabled, calculator disabled), so any
     *  non-enabled calculator state means standard. */
    private fun currentLauncherAlias(): String {
        val state = packageManager.getComponentEnabledSetting(
            ComponentName(this, "$packageName.LauncherAliasCalculator")
        )
        return if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
            "calculator"
        } else {
            "standard"
        }
    }
}
