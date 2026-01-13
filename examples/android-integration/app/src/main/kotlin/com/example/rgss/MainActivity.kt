package com.example.rgss

import android.os.Bundle
import android.util.Log
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.scorbutics.rubyvm.ExecutionResult
import com.scorbutics.rubyvm.LibraryConfig
import com.scorbutics.rubyvm.LogListener
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

        try {
            output.appendLine("Initializing Ruby VM...")
            output.appendLine()

            // Create a log listener to capture Ruby output
            val logListener = object : LogListener {
                override fun onLog(message: String) {
                    Log.d(TAG, "Ruby: $message")
                }

                override fun onError(message: String) {
                    Log.e(TAG, "Ruby Error: $message")
                }
            }

            // Get default paths - this handles asset extraction automatically
            val paths = RubyVMPaths.getDefaultPaths(this)
            output.appendLine("Install directory: ${paths.installDir}")
            output.appendLine("Ruby base directory: ${paths.rubyBaseDir}")
            output.appendLine("Native libs directory: ${paths.nativeLibsDir}")
            output.appendLine()

            // Create interpreter with auto-cleanup using .use
            RubyInterpreter.create(
                appPath = ".",
                rubyBaseDir = paths.rubyBaseDir,
                nativeLibsDir = paths.nativeLibsDir,
                listener = logListener
            ).use { interpreter ->

                // Demo 1: Simple Hello World
                output.appendLine("=== Demo 1: Simple Hello World ===")
                val demo1Result = interpreter.executeWithResult(
                    scriptContent = """
                        puts 'Hello from Ruby on Android!'
                        "Welcome to embedded Ruby VM"
                    """.trimIndent(),
                    timeoutSeconds = 10
                )
                output.appendLine(formatExecutionResult(demo1Result))
                output.appendLine()

                // Demo 2: Class Definition with Methods
                output.appendLine("=== Demo 2: Class Definition ===")
                val demo2Result = interpreter.executeWithResult(
                    scriptContent = """
                        class Game
                          def initialize(title)
                            @title = title
                          end

                          def greet(player)
                            "Welcome to #{@title}, #{player}!"
                          end
                        end

                        game = Game.new("My RGSS Game")
                        game.greet("Android User")
                    """.trimIndent(),
                    timeoutSeconds = 10
                )
                output.appendLine(formatExecutionResult(demo2Result))
                output.appendLine()

                // Demo 3: Batch Execution
                output.appendLine("=== Demo 3: Batch Execution ===")
                val scripts = listOf(
                    """
                        result = (1..10).sum
                        "Sum of 1-10: #{result}"
                    """.trimIndent(),
                    """
                        text = "ruby".upcase.reverse
                        "Reversed: #{text}"
                    """.trimIndent(),
                    """
                        numbers = [1, 2, 3, 4, 5].map { |n| n * 2 }
                        "Doubled: #{numbers.inspect}"
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

                batchResults.forEachIndexed { index, result ->
                    output.appendLine("Script ${index + 1}:")
                    output.appendLine(formatScriptResult(result))
                    output.appendLine()
                }

                val metrics = batchResults.toMetrics()
                output.appendLine("Batch Metrics:")
                output.appendLine("  Total: ${metrics.totalScripts}")
                output.appendLine("  Success: ${metrics.successCount}")
                output.appendLine("  Failed: ${metrics.failureCount}")
                output.appendLine()
            }

            output.appendLine("All demos completed successfully!")

        } catch (e: Exception) {
            output.appendLine()
            output.appendLine("ERROR: ${e.message}")
            output.appendLine()
            output.appendLine("Stack trace:")
            output.appendLine(e.stackTraceToString())
            Log.e(TAG, "Error executing Ruby", e)
        }

        textView.text = output.toString()
    }

    private fun formatExecutionResult(result: ExecutionResult): String {
        return when (result) {
            is ExecutionResult.Success -> {
                buildString {
                    appendLine("  Status: Success")
                    appendLine("  Exit code: ${result.exitCode}")
                    appendLine("  Duration: ${result.durationMs}ms")
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
            appendLine("  Exit code: ${result.exitCode}")
            appendLine("  Duration: ${result.durationMs}ms")
            result.name?.let { appendLine("  Name: $it") }
        }
    }
}
