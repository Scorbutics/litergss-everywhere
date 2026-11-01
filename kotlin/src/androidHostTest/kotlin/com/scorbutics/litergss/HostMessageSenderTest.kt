package com.scorbutics.litergss

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals

class HostMessageSenderTest {
    private val posted = CopyOnWriteArrayList<String>()
    private val failures = CopyOnWriteArrayList<String>()
    private val flushed = LinkedBlockingQueue<Unit>()
    private var created = 0

    private fun sender(rc: (String) -> Int = { 0 }, create: () -> Unit = {}) =
        HostMessageSender(onFailure = { topic, error, _ -> failures += "$topic: $error" }) {
            create()
            created++
            HostMessageSender.Poster { topic, payload ->
                if (topic == FLUSH) flushed += Unit else posted += "$topic=$payload"
                rc(topic)
            }
        }

    /** Waits for the messages sent before it: the sender posts in order */
    private fun HostMessageSender.flush() {
        send(FLUSH)
        assertEquals(Unit, flushed.poll(5, TimeUnit.SECONDS), "not flushed")
    }

    @Test
    fun messages_arrive_in_order_through_one_interpreter() {
        val sender = sender()
        sender.send("a", "1")
        sender.send("b")
        sender.send("c", "3")
        sender.flush()
        assertEquals(listOf("a=1", "b=", "c=3"), posted)
        assertEquals(1, created)
    }

    @Test
    fun nothing_sent_before_nothing_to_undo() {
        val sender = sender()
        sender.sendIfStarted("clear")
        sender.flush()
        assertEquals(emptyList(), posted)
        sender.sendIfStarted("clear")
        sender.flush()
        assertEquals(listOf("clear="), posted)
    }

    @Test
    fun a_failure_is_reported_and_the_next_messages_still_go() {
        val sender = sender(rc = { if (it == "bad") 3 else 0 })
        sender.send("bad")
        sender.send("good")
        sender.flush()
        assertEquals(listOf("bad: exit code 3"), failures)
        assertEquals(listOf("bad=", "good="), posted)
    }

    @Test
    fun an_interpreter_that_cannot_start_is_reported_and_made_again() {
        var attempts = 0
        val sender = sender(create = { if (attempts++ == 0) throw IllegalStateException("no VM") })
        sender.send("a")
        sender.send("b")
        sender.flush()
        assertEquals(listOf("a: no VM"), failures)
        assertEquals(listOf("b="), posted)
    }

    private companion object {
        const val FLUSH = "flush"
    }
}
