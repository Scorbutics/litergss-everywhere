package com.example.rgss

import android.os.Bundle
import android.util.Log
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.scorbutics.rubyvm.ExecutionResult
import com.scorbutics.rubyvm.LibraryConfig
import com.scorbutics.rubyvm.LogListener
import com.scorbutics.rubyvm.LogMessage
import com.scorbutics.rubyvm.LogSource
import com.scorbutics.rubyvm.RubyInterpreter
import com.scorbutics.rubyvm.RubyVMPaths
import com.scorbutics.rubyvm.ScriptResult
import com.scorbutics.rubyvm.batch
import com.scorbutics.rubyvm.executeWithResult
import com.scorbutics.rubyvm.toMetrics

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "RGSSExample"

        init {
            // Configure library name BEFORE any library loading
            // Must match the name used when publishing the KMP module
            LibraryConfig.libraryName = "rgss_runtime"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val textView = findViewById<TextView>(R.id.textView)
        val output = StringBuilder()
        val logMessages = mutableListOf<String>()

        // Coalescing UI updates - accumulate logs and refresh periodically
        // Unlike debouncing, this never cancels pending updates
        var lastUpdateTime = 0L
        val updateHandler = android.os.Handler(android.os.Looper.getMainLooper())
        val MIN_UPDATE_INTERVAL_MS = 16L  // ~60fps, fast enough for smooth updates

        val updateRunnable = object : Runnable {
            override fun run() {
                lastUpdateTime = System.currentTimeMillis()
                val displayText = buildString {
                    synchronized(output) {
                        append(output)
                    }
                    synchronized(logMessages) {
                        if (logMessages.isNotEmpty()) {
                            appendLine()
                            appendLine("=== Ruby Output ===")

                            logMessages.forEach { msg ->

                                appendLine(msg)
                            }
                        }
                    }
                }
                textView.text = displayText
            }
        }

        // Helper function to filter unwanted messages
        fun shouldDisplayMessage(msg: String, isError: Boolean): Boolean {
            /*if (msg.source == LogSource.RUBY_VM_INTERNAL && !isError) {
                return false
            }*/
            // Filter out OpenGL debug messages from Android emulator
            if (msg.startsWith("s_gl") ||
                msg.contains("BindAttribLocation")) {
                return false
            }
            return true
        }

        // Helper function to update UI with coalescing (not debouncing!)
        // This batches rapid updates but never cancels pending renders
        fun updateDisplay(delayMs: Long = 0) {
            val now = System.currentTimeMillis()
            val timeSinceLastUpdate = now - lastUpdateTime

            if (timeSinceLastUpdate < MIN_UPDATE_INTERVAL_MS && delayMs == 0L) {
                // Too soon since last update, schedule for later
                // Don't cancel existing callback - just schedule a new one
                val actualDelay = MIN_UPDATE_INTERVAL_MS - timeSinceLastUpdate
                updateHandler.postDelayed(updateRunnable, actualDelay)
            } else {
                // Either enough time has passed, or caller requested specific delay
                // Remove any pending updates first to avoid duplicates
                updateHandler.removeCallbacks(updateRunnable)
                updateHandler.postDelayed(updateRunnable, delayMs)
            }
        }

        // Run everything on a background thread to keep UI responsive
        Thread {
            try {
                synchronized(output) {
                    output.appendLine("Initializing Ruby VM...")
                    output.appendLine()
                }
                updateDisplay()

                // Log listener that captures Ruby output with metadata
                // These callbacks are invoked asynchronously on a separate native thread,
                // so they won't cause deadlocks even with synchronous execution
                val logListener = object : LogListener {
                    override fun onLogMessage(logMessage: LogMessage) {
                        // Format message with source prefix
                        val prefix = when (logMessage.source) {
                            LogSource.RUBY_STDOUT -> "[Ruby]"
                            LogSource.RUBY_STDERR -> "[Ruby Error]"
                            LogSource.VMLOGGER -> "[VM]"
                            LogSource.NATIVE_STDOUT -> "[Native]"
                            LogSource.NATIVE_STDERR -> "[Native Error]"
                        }

                        val formattedMessage = "$prefix ${logMessage.message}"

                        // Filter out unwanted messages
                        if (shouldDisplayMessage(logMessage.message, logMessage.isError())) {
                            synchronized(logMessages) {
                                logMessages.add(formattedMessage)
                            }
                            // Update UI with small delay to batch rapid log arrivals
                            // This prevents canceling updates when logs arrive in quick succession
                            updateDisplay(delayMs = 50)
                        }
                    }
                }

                // Get default paths - this handles asset extraction automatically
                val paths = RubyVMPaths.getDefaultPaths(this)
                synchronized(output) {
                    output.appendLine("Install directory: ${paths.installDir}")
                    output.appendLine("Ruby base directory: ${paths.rubyBaseDir}")
                    output.appendLine("Native libs directory: ${paths.nativeLibsDir}")
                    output.appendLine()
                }
                updateDisplay()

                // Create interpreter with auto-cleanup using .use
                RubyInterpreter.create(
                    appPath = ".",
                    rubyBaseDir = paths.rubyBaseDir,
                    nativeLibsDir = paths.nativeLibsDir,
                    listener = logListener
                ).use { interpreter ->
                    interpreter.enableLogging()

                    // Demo 1: Simple Hello World
                    synchronized(output) {
                        output.appendLine("=== Demo 1: Simple Hello World ===")
                    }
                    updateDisplay()

                    val demo1Result = interpreter.executeWithResult(
                        scriptContent = """
                            puts 'Hello from Ruby on Android!'
                            123
                        """.trimIndent(),
                        timeoutSeconds = 10
                    )
                    // Give time for async logs to arrive
                    Thread.sleep(100)

                    synchronized(output) {
                        output.appendLine(formatExecutionResult(demo1Result))
                        output.appendLine()
                    }
                    // Delay update to ensure async logs are captured
                    updateDisplay(delayMs = 50)

                    // Demo 2: Class Definition with Methods
                    synchronized(output) {
                        output.appendLine("=== Demo 2: Require a built-in native extension ===")
                    }
                    updateDisplay()

                    val demo2Result = interpreter.executeWithResult(
                        scriptContent = """
                            require 'readline'
                            puts "Readline module loaded successfully."
                        """.trimIndent(),
                        timeoutSeconds = 10
                    )
                    // Give time for async logs to arrive
                    Thread.sleep(100)

                    synchronized(output) {
                        output.appendLine(formatExecutionResult(demo2Result))
                        output.appendLine()
                    }
                    // Delay update to ensure async logs are captured
                    updateDisplay(delayMs = 50)

                    synchronized(output) {
                        output.appendLine("=== Demo 3: Require the LiteRGSS extension ===")
                    }
                    updateDisplay()

                    val demo3Result = interpreter.executeWithResult(
                        scriptContent = """
                            require 'LiteRGSS'
                            puts "LiteRGSS module loaded successfully."
                            LiteRGSS::Shader.available = false
                        """.trimIndent(),
                        timeoutSeconds = 10
                    )
                    // Give time for async logs to arrive
                    Thread.sleep(100)

                    synchronized(output) {
                        output.appendLine(formatExecutionResult(demo3Result))
                        output.appendLine()
                    }
                    // Delay update to ensure async logs are captured
                    updateDisplay(delayMs = 50)

                    // Demo 3: Batch Execution
                    synchronized(output) {
                        output.appendLine("=== Demo 4: Batch Execution ===")
                    }
                    updateDisplay()

                    val scripts = listOf(
                        """
                            result = (1..10).sum
                            puts "Sum of 1-10: #{result}"
                        """.trimIndent(),
                        """
                            text = "ruby".upcase.reverse
                            puts "Reversed: #{text}"
                        """.trimIndent(),
                        """
                            numbers = [1, 2, 3, 4, 5].map { |n| n * 2 }
                            puts "Doubled: #{numbers.inspect}"
                        """.trimIndent()
                    )

                    val batchResults = interpreter.batch()
                        .apply {
                            scripts.forEachIndexed { index, script ->
                                addScript(script, name = "script_${index + 1}")
                            }
                        }
                        .timeout(30)
                        .execute()

                    // Give time for async logs to arrive
                    Thread.sleep(100)

                    val metrics = batchResults.toMetrics()
                    synchronized(output) {
                        output.appendLine("Batch Metrics:")
                        output.appendLine("  Total: ${metrics.totalScripts}")
                        output.appendLine("  Success: ${metrics.successCount}")
                        output.appendLine("  Failed: ${metrics.failureCount}")
                        output.appendLine()
                    }
                    // Delay update to ensure async logs are captured
                    updateDisplay(delayMs = 50)
                }

                synchronized(output) {
                    output.appendLine("All demos completed successfully!")
                }

                Thread.sleep(200)
                // Final update to display all collected logs
                updateDisplay(delayMs = 100)

            } catch (e: Exception) {
                synchronized(output) {
                    output.appendLine()
                    output.appendLine("ERROR: ${e.message}")
                    output.appendLine()
                    output.appendLine("Stack trace:")
                    output.appendLine(e.stackTraceToString())
                }
                updateDisplay()
                Log.e(TAG, "Error executing Ruby", e)
            }
        }.start()
    }

    private fun formatExecutionResult(result: ExecutionResult): String {
        return when (result) {
            is ExecutionResult.Success -> {
                buildString {
                    appendLine("  Status: Success")
                    //appendLine("  Exit code: ${result.exitCode}")
                    //appendLine("  Duration: ${result.durationMs}ms")
                }
            }
            is ExecutionResult.Failure -> {
                buildString {
                    appendLine("  Status: Failed")
                    appendLine("  Error: ${result.error.message}")
                }
            }
            is ExecutionResult.Timeout -> {
                buildString {
                    appendLine("  Status: Timeout")
                    appendLine("  Timeout: ${result.timeoutSeconds}s")
                }
            }
        }
    }

    private fun formatScriptResult(result: ScriptResult): String {
        return buildString {
            appendLine("  Status: ${if (result.success) "Success" else "Failed"}")
            //appendLine("  Exit code: ${result.exitCode}")
            //appendLine("  Duration: ${result.durationMs}ms")
            //result.name?.let { appendLine("  Name: $it") }
        }
    }
}
