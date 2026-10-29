# Unit tests for LiteRGSS::TouchOverlay against a fake LiteRGSS (window events,
# viewports, sprites): which touches reach the game, which keys a button sends,
# where the buttons are.
#
# Run:  ruby ruby/test/test_touch_overlay.rb

require 'minitest/autorun'

# Minimal stand-in for the LiteRGSS C extension: a window whose update
# dispatches queued events to the callbacks set on it, like the real one.
module LiteRGSS
  class DisplayWindow
    class << self
      attr_accessor :desktop_width, :desktop_height
    end

    attr_reader :width, :height, :viewports, :callbacks

    def initialize(width, height)
      @width = width
      @height = height
      @viewports = []
      @callbacks = {}
      @events = []
    end

    %i[key_pressed key_released touch_began touch_moved touch_ended].each do |event|
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

    def resize(width, height)
      @width = width
      @height = height
    end
  end

  class Viewport
    attr_reader :rect
    attr_accessor :z

    def initialize(window, x, y, width, height)
      @rect = [x, y, width, height]
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
    def initialize(data, from_memory)
      raise ArgumentError, 'not a PNG' unless from_memory && data.start_with?("\x89PNG".b)
    end

    def width
      16
    end
  end
end

# Like LiteRGSS: scancode constants, no Sf::Keyboard::Unknown
module Sf
  module Keyboard
    class << self
      attr_reader :virtual_keyboard_calls

      def virtual_keyboard=(shown)
        (@virtual_keyboard_calls ||= []) << shown
      end
    end

    module Scancode
      B = 1; F = 5; G = 6; Enter = 58; Escape = 59; Insert = 77; Pause = 78
      Right = 82; Left = 83; Down = 84; Up = 85; Menu = 124
    end
  end
end

# What the overlay reads of a PSDK text field (UI::UserInput, a LiteRGSS::Text)
# and its viewport
FakeViewport = Struct.new(:rect, :ox, :oy, :zoom, :visible)
FakeRect = Struct.new(:x, :y, :width, :height)
module UI
  class UserInput
    attr_accessor :x, :y, :width, :height, :visible, :viewport

    def initialize(viewport, x, y, width, height, default: '')
      @viewport = viewport
      @x = x
      @y = y
      @width = width
      @height = height
      @default = default
      @visible = true
      @disposed = false
    end

    def dispose
      @disposed = true
    end

    def disposed?
      @disposed
    end
  end
end

module GamePlay
  class NameInput; end
end

require_relative '../litergss/touch_overlay'
LiteRGSS::TouchOverlay.install

class TestTouchOverlay < Minitest::Test
  Overlay = LiteRGSS::TouchOverlay

  def setup
    LiteRGSS::DisplayWindow.desktop_width = 2424
    LiteRGSS::DisplayWindow.desktop_height = 1080
    @window = LiteRGSS::DisplayWindow.new(2424, 1080)
    @game = Hash.new { |h, k| h[k] = [] }
    %i[key_pressed key_released touch_began touch_moved touch_ended].each do |event|
      @window.send(:"on_#{event}=", proc { |*args| @game[event] << args })
    end
  end

  def teardown
    Object.send(:remove_const, :Input) if defined?(::Input)
    LiteRGSS::TouchOverlay::TextEntry.reset
    $scene = nil
    Sf::Keyboard.virtual_keyboard_calls&.clear
  end

  # A 320x180 game drawn x4 at (572, 180) in the 2424x1080 window, as
  # Foret Eternelle on a phone
  def game_viewport
    FakeViewport.new(FakeRect.new(572, 180, 1280, 720), 0, 0, 4, true)
  end

  def test_a_tap_on_a_text_field_shows_the_keyboard_then_hides_it_with_the_field
    frame # the overlay hooks UI::UserInput once the game defined it
    field = UI::UserInput.new(game_viewport, 100, 20, 120, 16, default: 'Yana')
    # Field at x 972..1452, y 260..324 on the window
    @window.queue(:touch_began, 0, 1200, 290)
    frame
    assert_equal [true], Sf::Keyboard.virtual_keyboard_calls
    assert_equal [[0, 1200, 290]], @game[:touch_began], 'the game still gets the tap'
    frame
    assert_equal [true], Sf::Keyboard.virtual_keyboard_calls
    field.dispose
    frame
    assert_equal [true, false], Sf::Keyboard.virtual_keyboard_calls
  end

  def test_a_tap_beside_a_text_field_does_not_show_the_keyboard
    frame
    UI::UserInput.new(game_viewport, 100, 20, 120, 16)
    @window.queue(:touch_began, 0, 700, 900)
    frame
    assert_nil Sf::Keyboard.virtual_keyboard_calls&.first
  end

  def test_a_tap_during_name_input_shows_the_keyboard_until_the_scene_ends
    $scene = GamePlay::NameInput.new
    @window.queue(:touch_began, 0, 1200, 600)
    frame
    assert_equal [true], Sf::Keyboard.virtual_keyboard_calls
    $scene = Object.new
    frame
    assert_equal [true, false], Sf::Keyboard.virtual_keyboard_calls
  end

  # Regression: once the system hid the keyboard (its close key), the
  # overlay still thought it shown and a tap on the text entry did nothing
  def test_a_tap_on_a_text_entry_shows_the_keyboard_again_after_the_system_hid_it
    $scene = GamePlay::NameInput.new
    @window.queue(:touch_began, 0, 1200, 600)
    frame
    # The system hides it: the overlay is not told
    @window.queue(:touch_began, 1, 1200, 600)
    frame
    assert_equal [true, true], Sf::Keyboard.virtual_keyboard_calls
  end

  def test_a_keyboard_shown_with_the_button_stays_without_text_entry
    @window.queue(:touch_began, 0, *center('keyboard'))
    @window.queue(:touch_ended, 0, *center('keyboard'))
    frame
    frame
    frame
    assert_equal [true], Sf::Keyboard.virtual_keyboard_calls
  end


  def center(name)
    button = @window.touch_overlay.layout.buttons.find { |b| b.name == name }
    [button.x + button.size / 2, button.y + button.size / 2]
  end

  def frame
    @window.update
  end

  def test_a_tap_on_a_button_sends_its_key_and_not_the_touch
    @window.queue(:touch_began, 0, *center('a'))
    frame
    assert_equal [[-1, Sf::Keyboard::Scancode::Enter, false, false, false, false]], @game[:key_pressed]
    @window.queue(:touch_ended, 0, *center('a'))
    frame
    assert_equal [[-1, Sf::Keyboard::Scancode::Enter]], @game[:key_released]
    assert_empty @game[:touch_began]
    assert_empty @game[:touch_ended]
  end

  # Regression: a tap shorter than a frame (down and up in the same poll, as
  # `adb shell input tap` does) sent no key at all
  def test_a_tap_within_one_frame_presses_then_releases
    @window.queue(:touch_began, 0, *center('a'))
    @window.queue(:touch_ended, 0, *center('a'))
    frame
    assert_equal [Sf::Keyboard::Scancode::Enter], @game[:key_pressed].map { |a| a[1] }
    assert_empty @game[:key_released]
    frame
    assert_equal [Sf::Keyboard::Scancode::Enter], @game[:key_released].map { |a| a[1] }
    frame
    assert_equal 1, @game[:key_pressed].size
  end

  def test_the_keyboard_button_toggles_the_virtual_keyboard
    Sf::Keyboard.virtual_keyboard_calls&.clear
    2.times do
      @window.queue(:touch_began, 0, *center('keyboard'))
      @window.queue(:touch_ended, 0, *center('keyboard'))
      frame
      frame
    end
    assert_equal [true, false], Sf::Keyboard.virtual_keyboard_calls
    assert_empty @game[:key_pressed]
    assert_empty @game[:touch_began]
  end

  def test_a_game_with_its_own_touch_controls_never_gets_the_overlay
    Object.const_set(:Input, Module.new)
    Input.const_set(:InputTouch, Class.new)
    window = LiteRGSS::DisplayWindow.new(2424, 1080)
    assert_nil window.touch_overlay
    assert_empty window.viewports
    touches = []
    window.on_touch_began = proc { |*args| touches << args }
    window.queue(:touch_began, 0, 2257, 835)
    window.update
    assert_equal [[0, 2257, 835]], touches
  end

  def test_a_touch_outside_the_buttons_reaches_the_game
    @window.queue(:touch_began, 0, 1212, 300)
    @window.queue(:touch_moved, 0, 1220, 310)
    @window.queue(:touch_ended, 0, 1220, 310)
    frame
    assert_equal [[0, 1212, 300]], @game[:touch_began]
    assert_equal [[0, 1220, 310]], @game[:touch_moved]
    assert_equal [[0, 1220, 310]], @game[:touch_ended]
    assert_empty @game[:key_pressed]
  end

  def test_sliding_on_the_dpad_changes_the_direction
    @window.queue(:touch_began, 3, *center('up'))
    frame
    @window.queue(:touch_moved, 3, *center('right'))
    frame
    assert_equal [Sf::Keyboard::Scancode::Up, Sf::Keyboard::Scancode::Right], @game[:key_pressed].map { |a| a[1] }
    assert_equal [Sf::Keyboard::Scancode::Up], @game[:key_released].map { |a| a[1] }
    # Between two buttons: nothing held, the touch still belongs to the overlay
    @window.queue(:touch_moved, 3, 1212, 100)
    @window.queue(:touch_ended, 3, 1212, 100)
    frame
    assert_equal [Sf::Keyboard::Scancode::Up, Sf::Keyboard::Scancode::Right], @game[:key_released].map { |a| a[1] }
    assert_empty @game[:touch_moved]
    assert_empty @game[:touch_ended]
  end

  def test_two_fingers_hold_two_buttons
    @window.queue(:touch_began, 0, *center('left'))
    @window.queue(:touch_began, 1, *center('b'))
    frame
    assert_equal [Sf::Keyboard::Scancode::Left, Sf::Keyboard::Scancode::Escape].sort,
                 @game[:key_pressed].map { |a| a[1] }.sort
    @window.queue(:touch_ended, 0, *center('left'))
    frame
    assert_equal [Sf::Keyboard::Scancode::Left], @game[:key_released].map { |a| a[1] }
  end

  def test_the_game_key_binding_wins_over_the_default
    Object.const_set(:Input, Module.new)
    Input.const_set(:Keys, { A: [-1, 2, 40], START: [-3] })
    @window.queue(:touch_began, 0, *center('a'))
    @window.queue(:touch_began, 1, *center('start'))
    frame
    # First keyboard binding of :A; :START has only a joystick one: default
    assert_equal [2, Sf::Keyboard::Scancode::Insert].sort, @game[:key_pressed].map { |a| a[1] }.sort
  end

  def test_touch_callbacks_set_by_the_game_stay_behind_the_overlay
    replaced = []
    @window.on_touch_began = proc { |*args| replaced << args }
    @window.queue(:touch_began, 0, *center('x'))
    @window.queue(:touch_began, 1, 1212, 300)
    frame
    assert_equal [[1, 1212, 300]], replaced
    assert_equal [Sf::Keyboard::Scancode::Menu], @game[:key_pressed].map { |a| a[1] }
  end

  def test_a_game_with_its_own_touch_controls_disables_the_overlay
    Object.const_set(:Input, Module.new)
    Input.const_set(:InputTouch, Class.new)
    frame
    assert @window.viewports.all?(&:disposed?)
    @window.queue(:touch_began, 0, *center('a'))
    frame
    assert_equal 1, @game[:touch_began].size
    assert_empty @game[:key_pressed]
  end

  # Regression: an error in the overlay (it used Sf::Keyboard::Unknown, which
  # LiteRGSS lacks) went up to the game, which stopped on it
  def test_an_overlay_error_disables_it_instead_of_reaching_the_game
    Object.const_set(:Input, Module.new)
    Input.const_set(:Keys, Object.new.tap { |keys| def keys.[](_) = raise(NameError, 'broken binding') })
    @window.queue(:touch_began, 0, *center('a'))
    _, err = capture_io { frame }
    assert_match(/TouchOverlay\] disabled: NameError/, err)
    refute @window.touch_overlay.enabled?
    assert @window.viewports.all?(&:disposed?)
    # From now on every touch goes to the game
    @window.queue(:touch_began, 1, *center('b'))
    frame
    assert_equal [[1, *center('b')]], @game[:touch_began]
  end

  def test_touches_are_scaled_to_the_window_resolution
    window = LiteRGSS::DisplayWindow.new(1212, 540)
    pressed = []
    window.on_key_pressed = proc { |*args| pressed << args[1] }
    button = window.touch_overlay.layout.buttons.find { |b| b.name == 'down' }
    window.queue(:touch_began, 0, (button.x + button.size / 2) * 2, (button.y + button.size / 2) * 2)
    window.update
    assert_equal [Sf::Keyboard::Scancode::Down], pressed
  end

  def test_hit_areas_fit_the_window_without_overlapping
    [[2424, 1080], [1080, 2424], [320, 240], [1280, 720]].each do |width, height|
      layout = Overlay::Layout.new(width, height, 16)
      layout.buttons.each do |b|
        assert_operator b.x, :>=, 0, "#{b.name} in #{width}x#{height}"
        assert_operator b.y, :>=, 0, "#{b.name} in #{width}x#{height}"
        assert_operator b.x + b.size, :<=, width, "#{b.name} in #{width}x#{height}"
        assert_operator b.y + b.size, :<=, height, "#{b.name} in #{width}x#{height}"
      end
      # Hit areas: each cross as a whole, and the buttons out of the crosses
      cross_names = layout.crosses.flat_map(&:buttons).map(&:name)
      areas = layout.crosses.map { |c| ['cross', c.x, c.y, c.size] } +
              layout.buttons.reject { |b| cross_names.include?(b.name) }.map { |b| [b.name, b.x, b.y, b.size] }
      areas.combination(2).each do |(na, ax, ay, as), (nb, bx, by, bs)|
        overlap = ax < bx + bs && bx < ax + as && ay < by + bs && by < ay + as
        refute overlap, "#{na} overlaps #{nb} in #{width}x#{height}"
      end
    end
  end

  def test_a_cross_resolves_to_the_nearest_button
    layout = Overlay::Layout.new(2424, 1080, 16)
    dpad = layout.crosses.first
    middle = dpad.x + dpad.size / 2
    assert_equal 'up', layout.button_at(middle, dpad.y + 2).name
    assert_equal 'down', layout.button_at(middle, dpad.y + dpad.size - 2).name
    # Upper right corner, closer to the right edge
    assert_equal 'right', layout.button_at(dpad.x + dpad.size - 2, dpad.y + dpad.size / 3).name
    assert_nil layout.button_at(1212, 100)
  end

  def test_a_resized_window_moves_the_buttons
    before = @window.touch_overlay.layout.buttons.map(&:to_a)
    @window.resize(1280, 720)
    frame
    refute_equal before, @window.touch_overlay.layout.buttons.map(&:to_a)
    # The viewports of the old layout (one per button) are disposed, new ones replace them
    buttons = @window.touch_overlay.layout.buttons.size
    assert_equal buttons, @window.viewports.count(&:disposed?)
    assert_equal buttons, @window.viewports.count { |v| !v.disposed? }
  end
end
