# Unit tests for LiteRGSS::HostLifecycle against a fake LiteRGSS window: the
# handlers run on the focus events, after the game's own callbacks.
#
# Run:  ruby ruby/test/test_host_lifecycle.rb

require 'minitest/autorun'

module LiteRGSS
  # Minimal stand-in for the extension's window: its focus callbacks, called
  # by `focus` as the real event pump does
  class DisplayWindow
    def initialize(*); end

    def on_lost_focus=(proc)
      @lost = proc
    end

    def on_gained_focus=(proc)
      @gained = proc
    end

    def focus(gained)
      (gained ? @gained : @lost)&.call
    end
  end
end

require_relative '../litergss/host_lifecycle'
LiteRGSS::HostLifecycle.install

class TestHostLifecycle < Minitest::Test
  Lifecycle = LiteRGSS::HostLifecycle

  def setup
    @calls = []
    @handlers = [Lifecycle.on_background { @calls << :background },
                 Lifecycle.on_foreground { @calls << :foreground }]
  end

  def teardown
    @handlers.each { |h| Lifecycle.remove(h) }
  end

  def test_a_window_without_game_callbacks_notifies_the_handlers
    window = LiteRGSS::DisplayWindow.new
    window.focus(false)
    assert Lifecycle.background?
    window.focus(true)
    refute Lifecycle.background?
    assert_equal %i[background foreground], @calls
  end

  def test_the_game_callback_runs_first
    window = LiteRGSS::DisplayWindow.new
    window.on_lost_focus = proc { @calls << :game_paused }
    window.focus(false)
    assert_equal %i[game_paused background], @calls
  end

  def test_a_failing_handler_does_not_stop_the_others_nor_the_game
    failing = Lifecycle.on_background { raise 'disk full' }
    window = LiteRGSS::DisplayWindow.new
    _, err = capture_io { window.focus(false) }
    assert_includes err, 'disk full'
    assert_equal [:background], @calls
  ensure
    Lifecycle.remove(failing)
  end

  def test_install_is_idempotent
    Lifecycle.install
    window = LiteRGSS::DisplayWindow.new
    window.focus(false)
    assert_equal [:background], @calls, 'handlers run once'
  end
end
