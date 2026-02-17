package com.example.rgss.nativeactivity

import android.content.Intent
import android.os.Bundle
import android.system.Os
import android.util.Log
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.scorbutics.rubyvm.LibraryConfig
import com.scorbutics.rubyvm.RubyVMPaths
import java.io.File

/**
 * Launcher Activity for the NativeActivity rendering example.
 *
 * This activity handles the KMP-based initialization:
 * 1. Extracts the Ruby runtime assets (stdlib, native extensions)
 * 2. Copies the Ruby rendering script from APK assets to internal storage
 * 3. Sets environment variables with paths for the native main() function
 * 4. Launches the NativeActivity which starts SFML rendering
 *
 * The NativeActivity loads librgss_runtime.so, which contains:
 * - SFML's ANativeActivity_onCreate: sets up EGL/OpenGL ES2 context
 * - A generic main() function that reads env vars and runs the Ruby script
 * - The full LiteRGSS/LiteCGSS/SFML rendering pipeline
 */
class LauncherActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "RGSSLauncher"

        init {
            // Configure library name BEFORE any library loading
            // Must match the name used when publishing the KMP module
            LibraryConfig.libraryName = "rgss_runtime"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val textView = TextView(this).apply {
            text = getString(R.string.initializing)
            textSize = 18f
            setPadding(32, 32, 32, 32)
        }
        setContentView(textView)

        Thread {
            try {
                Log.i(TAG, "Starting KMP asset extraction...")

                // Phase 1: Use KMP module to extract Ruby runtime assets
                // This handles the two-phase library loading:
                //   - Loads libassets.so to extract embedded Ruby runtime
                //   - Extracts Ruby stdlib, native libs to app's filesDir
                //   - Loads librgss_runtime.so with all symbols
                val paths = RubyVMPaths.getDefaultPaths(this)

                Log.i(TAG, "Install dir: ${paths.installDir}")
                Log.i(TAG, "Ruby base dir: ${paths.rubyBaseDir}")
                Log.i(TAG, "Native libs dir: ${paths.nativeLibsDir}")

                // Phase 2: Copy the Ruby rendering script from APK assets to internal storage
                val scriptFile = File(filesDir, "render_demo.rb")
                assets.open("render_demo.rb").use { input ->
                    scriptFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                Log.i(TAG, "Script copied to: ${scriptFile.absolutePath}")

                // Phase 3: Set environment variables for the native main() function
                // These are process-wide and will be visible to the SFML thread
                // that calls main() in the NativeActivity
                Os.setenv("RGSS_RUBY_BASE_DIR", paths.rubyBaseDir, true)
                Os.setenv("RGSS_NATIVE_LIBS_DIR", paths.nativeLibsDir, true)
                Os.setenv("RGSS_SCRIPT_PATH", scriptFile.absolutePath, true)

                Log.i(TAG, "Environment variables set, launching NativeActivity...")

                // Phase 4: Launch the NativeActivity
                // Since librgss_runtime.so is already loaded (by KMP in Phase 1),
                // Android will reuse it when the NativeActivity starts.
                // SFML's ANativeActivity_onCreate will set up the rendering context
                // and spawn a thread calling main(), which reads our env vars.
                runOnUiThread {
                    val intent = Intent(
                        this@LauncherActivity,
                        android.app.NativeActivity::class.java
                    )
                    startActivity(intent)
                    finish()
                }

            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize", e)
                runOnUiThread {
                    textView.text = "ERROR: ${e.message}\n\n${e.stackTraceToString()}"
                }
            }
        }.start()
    }
}
