package com.scorbutics.litergss

import android.util.Log
import java.util.concurrent.Executors

/**
 * Posts messages to the scripts of this process's Ruby VM (VMHost.deliver,
 * read with VMHost.each_message), one after the other on a thread of its
 * own: callers never wait, and the scripts get them in the order they were
 * sent. Through an interpreter of its own (one running a long script, a game
 * or a splash, would hold a message until its end): [createPoster] makes it,
 * on that thread, at the first message. Best-effort: a failure is reported
 * to [onFailure], the scripts keep their state.
 *
 * @param createPoster the interpreter's `post` (embedded-ruby-vm's
 *   RubyInterpreter.post, or the host's wrapper of it)
 */
class HostMessageSender(
    threadName: String = "host-messages",
    private val onFailure: (topic: String, error: String, cause: Throwable?) -> Unit = { topic, error, cause ->
        Log.w(TAG, "$topic not delivered: $error", cause)
    },
    private val createPoster: () -> Poster,
) {
    /** Queues [payload] under [topic] for the scripts; 0 once queued. */
    fun interface Poster {
        fun post(topic: String, payload: String): Int
    }

    private val sender = Executors.newSingleThreadExecutor { task ->
        Thread(task, threadName).apply { isDaemon = true }
    }

    /** Created on [sender] at the first message, kept for the process. */
    private var poster: Poster? = null

    fun send(topic: String, payload: String = "") {
        sender.execute { post(topic, payload) }
    }

    /** Like [send], but skipped when nothing was sent before: no script got anything to undo. */
    fun sendIfStarted(topic: String, payload: String = "") {
        sender.execute { if (poster != null) post(topic, payload) }
    }

    private fun post(topic: String, payload: String) {
        try {
            val poster = poster ?: createPoster().also { poster = it }
            val rc = poster.post(topic, payload)
            if (rc != 0) onFailure(topic, "exit code $rc", null)
        } catch (e: Exception) {
            onFailure(topic, e.message ?: e::class.java.simpleName, e)
        }
    }

    private companion object {
        const val TAG = "HostMessageSender"
    }
}
