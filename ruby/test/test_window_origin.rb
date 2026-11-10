# Unit tests for LiteRGSS::WindowOrigin against a fake LiteRGSS: the size and
# the positions a game sees once its window has a game area, and the touch
# overlay still drawn over the whole window.
#
# Run:  ruby ruby/test/test_window_origin.rb
#       OVERLAY_FIRST=1 ruby ruby/test/test_window_origin.rb

require 'minitest/autorun'

# Minimal stand-in for the LiteRGSS C extension, with the window origin
module LiteRGSS
  class DisplayWindow
    class << self
      attr_accessor :desktop_width, :desktop_height
    end

    attr_reader :width, :height, :viewports, :callbacks
    attr_accessor :origin

    def initialize(width, height)
      @width = width
      @height = height
      @origin = [0, 0]
      @viewports = []
      @callbacks = {}
      @events = []
    end

    %i[key_pressed key_released touch_began touch_moved touch_ended mouse_moved].each do |event|
      define_method(:"on_#{event}=") { |proc| @callbacks[event] = proc }
    end

    def queue(event, *args)
      @events << [event, args]
    end

    def update
      @events.shift(@events.size).each { |event, args| @callbacks[event]&.call(*args) }
      nil
    end

    def sort_z; end

    def dispose; end
  end

  class Viewport
    attr_reader :rect
    attr_accessor :z, :screen_space

    def initialize(window, x, y, width, height)
      @rect = [x, y, width, height]
      @screen_space = false
      @disposed = false
      window.viewports << self
    end

    def dispose
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end

  class Sprite
    attr_accessor :bitmap, :zoom, :opacity

    def initialize(_viewport); end
  end

  class Bitmap
    def initialize(_data, _from_memory)
      @disposed = false
    end

    def dispose
      @disposed = true
    end

    def disposed?
      @disposed
    end

    def width
      16
    end
  end

  class Error < StandardError; end
end

module Sf
  module Keyboard
    def self.virtual_keyboard=(_shown); end

    module Scancode
      B = 1; F = 5; G = 6; Enter = 58; Escape = 59; Insert = 77; Pause = 78
      Right = 82; Left = 83; Down = 84; Up = 85; Menu = 124; LShift = 129; RShift = 133
    end
  end
end

require_relative '../litergss/window_origin'
require_relative '../litergss/touch_overlay'
# Each touch must reach the game translated once, whichever module the window
# got first (CI runs both)
if ENV['OVERLAY_FIRST']
  LiteRGSS::TouchOverlay.install
  LiteRGSS::WindowOrigin.install
else
  LiteRGSS::WindowOrigin.install
  LiteRGSS::TouchOverlay.install
end

class TestWindowOrigin < Minitest::Test
  # A 320x240 game x4 on a 2136x960 phone: a 534x240 window, the game at x 107
  AREA = [107, 0, 320, 240].freeze

  def setup
    LiteRGSS::DisplayWindow.desktop_width = 2136
    LiteRGSS::DisplayWindow.desktop_height = 960
    LiteRGSS::TouchOverlay.enabled = false
    @window = LiteRGSS::DisplayWindow.new(534, 240)
  end

  def teardown
    LiteRGSS::TouchOverlay.enabled = true
  end

  def test_install_is_idempotent
    assert LiteRGSS::WindowOrigin.install
    assert LiteRGSS::WindowOrigin.install
    assert_equal 1, LiteRGSS::DisplayWindow.ancestors.count(LiteRGSS::WindowOrigin::Window)
  end

  def test_a_window_without_game_area_is_the_game
    assert_nil @window.game_area
    assert_equal [534, 240], [@window.width, @window.height]
    assert_equal [534, 240], [@window.screen_width, @window.screen_height]
    assert_equal [1000, 500], @window.to_game_pixels(1000, 500)
  end

  def test_the_game_area_moves_the_game_and_is_its_size
    @window.game_area = AREA
    assert_equal [107, 0], @window.origin, 'LiteRGSS moves the game'
    assert_equal [320, 240], [@window.width, @window.height], 'what Graphics.width reads'
    assert_equal [534, 240], [@window.screen_width, @window.screen_height]
  end

  def test_no_game_area_puts_the_game_back
    @window.game_area = AREA
    @window.game_area = nil
    assert_equal [0, 0], @window.origin
    assert_equal 534, @window.width
  end

  def test_a_game_area_needs_four_numbers
    assert_raises(ArgumentError) { @window.game_area = [107, 0] }
  end

  def test_the_mouse_reaches_the_game_at_its_place
    moves = []
    @window.on_mouse_moved = proc { |x, y| moves << [x, y] }
    @window.game_area = AREA
    # The game's centre: window x 267, screen pixel 1068
    @window.queue(:mouse_moved, 1068, 480)
    @window.update
    assert_equal [[640, 480]], moves
    # What PSDK's Mouse makes of it: x * window width / desktop width
    assert_equal 160, moves[0][0] * 534 / 2136
  end

  def test_the_position_is_read_when_the_event_comes
    moves = []
    @window.on_mouse_moved = proc { |x, y| moves << [x, y] }
    @window.queue(:mouse_moved, 1068, 480)
    @window.update
    @window.game_area = AREA
    @window.queue(:mouse_moved, 1068, 480)
    @window.update
    assert_equal [[1068, 480], [640, 480]], moves
  end

  def test_touches_reach_the_game_at_its_place_without_overlay
    touches = []
    @window.on_touch_began = proc { |finger, x, y| touches << [finger, x, y] }
    @window.game_area = AREA
    @window.queue(:touch_began, 2, 1068, 480)
    @window.update
    assert_equal [[2, 640, 480]], touches
  end

  def test_a_vertical_origin_moves_y
    moves = []
    @window.on_mouse_moved = proc { |x, y| moves << [x, y] }
    @window.game_area = [107, 30, 320, 240]
    # 300 high window on a 960 pixel screen: 3.2 screen pixels a window pixel
    @window.instance_variable_set(:@height, 300)
    @window.queue(:mouse_moved, 1068, 480)
    @window.update
    assert_equal [[640, 384]], moves
  end
end

class TestWindowOriginWithOverlay < Minitest::Test
  AREA = TestWindowOrigin::AREA

  def setup
    LiteRGSS::DisplayWindow.desktop_width = 2136
    LiteRGSS::DisplayWindow.desktop_height = 960
    LiteRGSS::TouchOverlay.enabled = true
    @window = LiteRGSS::DisplayWindow.new(534, 240)
    @touches = []
    @window.on_touch_began = proc { |finger, x, y| @touches << [finger, x, y] }
    @window.game_area = AREA
    @window.update
  end

  def test_a_touch_outside_the_buttons_reaches_the_game_translated_once
    @window.queue(:touch_began, 0, 1068, 480)
    @window.update
    assert_equal [[0, 640, 480]], @touches
  end

  def test_the_overlay_viewports_are_in_screen_space
    refute_empty @window.viewports
    assert @window.viewports.all?(&:screen_space)
  end

  def test_the_overlay_lays_out_on_the_whole_window
    layout = @window.touch_overlay.layout
    assert_equal [534, 240], [layout.width, layout.height]
    right_most = layout.buttons.map { |button| button.x + button.size }.max
    assert_operator right_most, :>, AREA[0] + AREA[2], 'the action buttons sit in the right black bar'
  end

  def test_a_tap_on_a_button_never_reaches_the_game
    a = @window.touch_overlay.layout.buttons.find { |button| button.name == 'a' }
    @window.queue(:touch_began, 0, (a.x + a.size / 2) * 4, (a.y + a.size / 2) * 4)
    @window.update
    assert_empty @touches
  end
end
