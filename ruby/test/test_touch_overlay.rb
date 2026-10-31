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
    class << self
      attr_accessor :created
    end
    self.created = 0

    def initialize(data, from_memory)
      raise ArgumentError, 'not a PNG' unless from_memory && data.start_with?("\x89PNG".b)
      raise ArgumentError, 'corrupt PNG' if data.include?('corrupt')

      @disposed = false
      Bitmap.created += 1
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
      Right = 82; Left = 83; Down = 84; Up = 85; Menu = 124; LShift = 129; RShift = 133
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

# PSDK's message helpers: get_key_name names a game key ("\\k[A]") after its
# first keyboard binding, as a module_function
module PFM
  module Text
    GameKeys = { 0 => 'KeyError', 'a' => :A, 'b' => :B, 'up' => :UP, 'home' => :HOME }

    module_function

    def parse_string_for_messages(text)
      text.gsub(/\\k\[([^\]]+)\]/i) { get_key_name($1) }
    end

    def get_key_name(name)
      "keyboard-#{name}"
    end
  end
end

# A PSDK class including PFM::Text (its battle transitions do)
class TextIncluder
  include PFM::Text

  def name_of(key)
    get_key_name(key)
  end
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
    Overlay.scale = 1.0
    Overlay.action_layout = :nintendo
    Overlay.extra_buttons.each_key { |name| Overlay.remove_button(name) }
    Overlay.key_labels = true
    Overlay.clear_layout
    Overlay.on_layout_saved = nil
  end

  # pokemonsdk's former InputTouch: a class with its singleton viewport
  def own_touch_controls
    Class.new { def self.singleton = nil }
  end

  PNG = "\x89PNG fake".b

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

  def test_the_name_input_scene_shows_the_keyboard_until_it_ends
    frame
    $scene = GamePlay::NameInput.new
    frame
    assert_equal [true], Sf::Keyboard.virtual_keyboard_calls
    frame
    $scene = Object.new
    frame
    assert_equal [true, false], Sf::Keyboard.virtual_keyboard_calls
  end

  # Hidden with the button during the scene: it is not shown again by itself
  def test_the_name_input_scene_shows_the_keyboard_once
    $scene = GamePlay::NameInput.new
    frame
    tap_menu(Overlay::KEYBOARD)
    frame
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

  SHIFT = Sf::Keyboard::Scancode::LShift

  def test_shift_presses_do_not_reach_the_game_during_name_input
    $scene = GamePlay::NameInput.new
    frame
    @window.queue(:key_pressed, -1, SHIFT, false, false, false, false)
    @window.queue(:key_pressed, -1, Sf::Keyboard::Scancode::RShift, false, false, false, false)
    @window.queue(:key_pressed, -1, Sf::Keyboard::Scancode::B, false, false, false, false)
    @window.queue(:key_released, -1, SHIFT)
    frame
    assert_equal [Sf::Keyboard::Scancode::B], @game[:key_pressed].map { |a| a[1] }
    assert_equal [SHIFT], @game[:key_released].map { |a| a[1] }, 'a release always reaches the game'
  end

  def test_shift_presses_do_not_reach_the_game_on_a_text_field
    frame
    UI::UserInput.new(game_viewport, 100, 20, 120, 16)
    @window.queue(:key_pressed, -1, SHIFT, false, false, false, false)
    frame
    assert_empty @game[:key_pressed]
  end

  def test_shift_reaches_the_game_without_text_entry
    @window.queue(:key_pressed, -1, SHIFT, false, false, false, false)
    frame
    assert_equal [SHIFT], @game[:key_pressed].map { |a| a[1] }
  end

  def test_a_keyboard_shown_with_the_button_stays_without_text_entry
    tap_menu(Overlay::KEYBOARD)
    frame
    frame
    frame
    assert_equal [true], Sf::Keyboard.virtual_keyboard_calls
  end


  def center(name)
    button = @window.touch_overlay.layout.buttons.find { |b| b.name == name }
    [button.x + button.size / 2, button.y + button.size / 2]
  end

  def tap_at(position, finger = 0)
    @window.queue(:touch_began, finger, *position)
    @window.queue(:touch_ended, finger, *position)
    frame
  end

  # Open the tools menu, tap one of its entries
  def tap_menu(entry)
    tap_at(center(Overlay::TOOLS))
    frame
    button = @window.touch_overlay.send(:menu_buttons).find { |b| b.name == entry }
    tap_at([button.x + button.size / 2, button.y + button.size / 2])
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
      tap_menu(Overlay::KEYBOARD)
      frame
      frame
    end
    assert_equal [true, false], Sf::Keyboard.virtual_keyboard_calls
    assert_empty @game[:key_pressed]
    assert_empty @game[:touch_began]
  end

  def test_a_game_with_its_own_touch_controls_never_gets_the_overlay
    Object.const_set(:Input, Module.new)
    Input.const_set(:InputTouch, own_touch_controls)
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
    Input.const_set(:InputTouch, own_touch_controls)
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

  # Lethalmon's AndroidControls reopened Input::InputTouch to add its buttons:
  # an empty class, not touch controls of the game
  def test_a_game_reopening_input_touch_keeps_the_overlay
    Object.const_set(:Input, Module.new)
    Input.const_set(:InputTouch, Class.new)
    frame
    refute @window.viewports.all?(&:disposed?)
    @window.queue(:touch_began, 0, *center('a'))
    frame
    assert_equal [Sf::Keyboard::Scancode::Enter], @game[:key_pressed].map { |a| a[1] }
  end

  # A key binding menu moves a touch button's own scancode to another key
  # (here, A's Enter to :B): the button keeps sending it, to press that key
  def test_a_button_sends_its_own_scancode_when_the_game_binds_it
    Object.const_set(:Input, Module.new)
    Input.const_set(:Keys, { A: [-1, 40], B: [Sf::Keyboard::Scancode::Enter] })
    @window.queue(:touch_began, 0, *center('a'))
    frame
    assert_equal [Sf::Keyboard::Scancode::Enter], @game[:key_pressed].map { |a| a[1] }
    assert_equal Sf::Keyboard::Scancode::Enter, Overlay.button_scancode('a')
    # Unbound: the first keyboard binding of the button's key, its own one unchanged
    Input::Keys[:B] = [-2]
    assert_equal 40, Overlay.button_scancode('a')
    assert_equal Sf::Keyboard::Scancode::Enter, Overlay.own_scancode('a')
    assert_nil Overlay.own_scancode('keyboard')
  end

  def bind_message_keys
    Object.const_set(:Input, Module.new)
    Input.const_set(:Keys, { A: [2, Sf::Keyboard::Scancode::Enter], B: [Sf::Keyboard::Scancode::Escape],
                             UP: [Sf::Keyboard::Scancode::Up], HOME: [40] })
    frame # the overlay hooks PFM::Text once the game defined it
  end

  def test_messages_name_the_touch_button_of_a_key
    bind_message_keys
    assert_equal 'A, B', PFM::Text.parse_string_for_messages('\\k[A], \\k[b]')
    assert_equal 'A', TextIncluder.new.name_of('A')
    # The D-pad has no label, no button sends HOME: the game names them
    assert_equal 'keyboard-UP keyboard-HOME', PFM::Text.parse_string_for_messages('\\k[UP] \\k[HOME]')
  end

  def test_messages_keep_the_game_key_names_when_asked
    bind_message_keys
    Overlay.key_labels = false
    assert_equal 'keyboard-A', PFM::Text.parse_string_for_messages('\\k[A]')
  end

  def test_messages_keep_the_game_key_names_without_the_overlay
    bind_message_keys
    @window.touch_overlay.disable
    assert_equal 'keyboard-A', TextIncluder.new.name_of('A')
  end

  def test_a_button_is_released_with_the_scancode_it_pressed
    Object.const_set(:Input, Module.new)
    Input.const_set(:Keys, { A: [-1, 40] })
    @window.queue(:touch_began, 0, *center('a'))
    frame
    Input::Keys[:A] = [Sf::Keyboard::Scancode::Enter]
    @window.queue(:touch_ended, 0, *center('a'))
    frame
    assert_equal [40], @game[:key_released].map { |a| a[1] }
  end

  def test_the_last_pressed_button_is_consumed_once
    assert_nil Overlay.consume_pressed_button
    @window.queue(:touch_began, 0, *center('up'))
    @window.queue(:touch_began, 1, *center('b'))
    frame
    assert_includes %w[up b], Overlay.consume_pressed_button
    assert_nil Overlay.consume_pressed_button
    # The tools button is not a game key
    @window.queue(:touch_began, 2, *center(Overlay::TOOLS))
    frame
    assert_nil Overlay.consume_pressed_button
  end

  def test_a_game_button_sends_no_key_and_reports_its_state
    Overlay.add_button('reset', PNG, anchor: :top_right)
    frame
    @window.queue(:touch_began, 0, *center('reset'))
    frame
    assert Overlay.pressed?('reset')
    assert Overlay.triggered?('reset')
    assert_kind_of Float, Overlay.held_for('reset')
    assert_empty @game[:key_pressed]
    assert_empty @game[:touch_began]
    frame
    assert Overlay.pressed?('reset')
    refute Overlay.triggered?('reset')
    @window.queue(:touch_ended, 0, *center('reset'))
    frame
    refute Overlay.pressed?('reset')
    assert_nil Overlay.held_for('reset')
    assert_nil Overlay.consume_pressed_button
  end

  def test_game_buttons_fit_in_their_corner_without_overlapping
    Overlay.scale = 1.5
    Overlay.add_button('keys', PNG, anchor: :top_left)
    Overlay.add_button('reset', PNG, anchor: :top_right)
    Overlay.add_button('menu', PNG, anchor: :top_right)
    [[2424, 1080], [1080, 2424], [1280, 720]].each do |width, height|
      @window.resize(width, height)
      frame
      buttons = @window.touch_overlay.layout.buttons
      extras = buttons.select { |b| %w[keys reset menu].include?(b.name) }
      assert_equal 3, extras.size
      extras.each do |b|
        assert_operator b.x, :>=, 0, "#{b.name} in #{width}x#{height}"
        assert_operator b.x + b.size, :<=, width, "#{b.name} in #{width}x#{height}"
        (buttons - [b]).each do |o|
          overlap = b.x < o.x + o.size && o.x < b.x + b.size && b.y < o.y + o.size && o.y < b.y + b.size
          refute overlap, "#{b.name} overlaps #{o.name} in #{width}x#{height}"
        end
      end
      assert_operator buttons.find { |b| b.name == 'keys' }.x, :<, width / 2
      assert_operator buttons.find { |b| b.name == 'reset' }.x, :>, width / 2
    end
  end

  def test_a_removed_game_button_disappears
    Overlay.add_button('reset', PNG)
    frame
    assert(@window.touch_overlay.layout.buttons.any? { |b| b.name == 'reset' })
    Overlay.remove_button('reset')
    frame
    refute(@window.touch_overlay.layout.buttons.any? { |b| b.name == 'reset' })
  end

  def test_a_game_button_cannot_replace_a_gamepad_one
    assert_raises(ArgumentError) { Overlay.add_button('a', PNG) }
    assert_raises(ArgumentError) { Overlay.add_button('reset', PNG, anchor: :bottom) }
  end

  def test_a_larger_scale_makes_larger_buttons
    size = @window.touch_overlay.layout.buttons.first.size
    Overlay.scale = 1.5
    frame
    assert_operator @window.touch_overlay.layout.buttons.first.size, :>, size
    # The viewports follow
    live = @window.viewports.reject(&:disposed?)
    assert_equal @window.touch_overlay.layout.buttons.size, live.size
  end

  def test_the_xbox_layout_swaps_a_and_b_but_not_their_keys
    a = center('a')
    b = center('b')
    Overlay.action_layout = :xbox
    frame
    assert_equal a, center('b')
    assert_equal b, center('a')
    @window.queue(:touch_began, 0, *center('a'))
    frame
    assert_equal [Sf::Keyboard::Scancode::Enter], @game[:key_pressed].map { |args| args[1] }
    assert_raises(KeyError) { Overlay.action_layout = :sega }
  end

  def test_the_gamepad_images_are_available_to_the_game
    assert Overlay.image('a').start_with?("\x89PNG".b)
    assert_nil Overlay.image('reset')
  end

  # Regression: PSDK's soft reset disposes every viewport, sprite and bitmap;
  # the overlay drew nothing after it, then disabled itself on its next press
  def test_the_overlay_rebuilds_itself_after_a_soft_reset
    loads = 0
    Overlay.add_button('reset', -> { loads += 1; LiteRGSS::Bitmap.new(PNG, true) })
    frame
    assert_equal 1, loads
    @window.viewports.each(&:dispose)
    frame
    assert_equal 2, loads
    live = @window.viewports.reject(&:disposed?)
    assert_equal @window.touch_overlay.layout.buttons.size, live.size
    @window.queue(:touch_began, 0, *center('a'))
    frame
    assert @window.touch_overlay.enabled?
    assert_equal [Sf::Keyboard::Scancode::Enter], @game[:key_pressed].map { |a| a[1] }
  end

  # Regression: the box of a cross came from the scale and the zoom was rounded
  # apart, so the buttons of a cross overlapped at some sizes and resolutions
  def test_the_gaps_of_a_cross_follow_the_button_size
    [[2424, 1080], [2712, 1220], [2027, 912], [1280, 720]].product([1.0, 1.5]).each do |(width, height), scale|
      layout = Overlay::Layout.new(width, height, 16, scale: scale)
      layout.crosses.each do |cross|
        size = cross.buttons.first.size
        assert_in_delta Overlay::Layout::CROSS_RATIO, cross.size.to_f / size, 0.01, "#{width}x#{height} x#{scale}"
      end
    end
  end

  # ── Layout file ──

  def load_file(data, read_image = ->(_path) { PNG })
    Overlay.load_layout(JSON.generate({ 'version' => 1 }.merge(data)), read_image: read_image)
  end

  def button(name)
    @window.touch_overlay.layout.buttons.find { |b| b.name == name }
  end

  def positions
    @window.touch_overlay.layout.buttons.to_h { |b| [b.name, [b.x, b.y, b.size]] }
  end

  def test_an_empty_layout_file_keeps_the_default_layout
    Overlay.add_button('reset', PNG)
    Overlay.add_button('menu', PNG, anchor: :top_right)
    frame
    default = positions
    assert load_file({})
    frame
    assert_equal default, positions
  end

  def test_a_cross_goes_where_the_file_anchors_it
    load_file('groups' => { 'dpad' => { 'anchor' => 'bottom_right', 'x' => 0.1, 'y' => 0.2 } })
    frame
    dpad = @window.touch_overlay.layout.crosses.first
    # 128 pixel buttons by default in this window
    assert_equal 320, dpad.size
    assert_equal [2424 - 242 - 320, 1080 - 216 - 320], [dpad.x, dpad.y]
    assert_equal %w[up right down left], dpad.buttons.map(&:name)
  end

  def test_the_file_sizes_and_spreads_a_cross
    size = button('a').size
    load_file('groups' => { 'action' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0, 'size' => 1.5, 'gap' => 2 } })
    frame
    action = @window.touch_overlay.layout.crosses.last
    big = (size * 1.5).round
    assert_equal big, button('a').size
    assert_equal (big + (Overlay::Layout::CROSS_RATIO - 1) * big * 2).round, action.size
    # The view follows the button size
    assert_in_delta big / 16.0, @window.touch_overlay.instance_variable_get(:@sprites)['a'].zoom
  end

  def test_the_file_moves_and_sizes_a_button
    size = button('start').size
    load_file('buttons' => { 'start' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'size' => 2 } })
    frame
    assert_equal [1212, 540, size * 2], positions['start']
  end

  def test_a_button_stays_inside_the_window
    load_file('buttons' => { 'start' => { 'anchor' => 'bottom_right', 'x' => 1, 'y' => 1 },
                             'select' => { 'anchor' => 'top_left', 'x' => 1, 'y' => 1 } })
    frame
    assert_equal [0, 0], positions['start'][0, 2]
    assert_equal [2424 - 128, 1080 - 128], positions['select'][0, 2]
  end

  def test_an_entry_without_anchor_keeps_the_centre
    before = button('start')
    load_file('buttons' => { 'start' => { 'size' => 2 }, 'select' => { 'visible' => true } })
    frame
    after = button('start')
    assert_equal 256, after.size
    assert_equal [before.x - 64, before.y - 64], [after.x, after.y]
  end

  def test_the_gamepad_images_keep_an_integer_zoom
    load_file('buttons' => { 'start' => { 'size' => 1.1 }, 'l' => { 'size' => 1.2 } })
    frame
    # 140.8 and 153.6 pixels, zoomed x9 and x10
    assert_equal [144, 160], [button('start').size, button('l').size]
  end

  def test_buttons_drawn_on_top_get_the_touch
    load_file('groups' => { 'dpad' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0 } },
              'buttons' => { 'start' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0 } })
    frame
    @window.queue(:touch_began, 0, *center('start'))
    frame
    assert_equal [Sf::Keyboard::Scancode::Insert], @game[:key_pressed].map { |args| args[1] }
  end

  def test_the_game_buttons_the_file_does_not_name_stay_put
    Overlay.add_button('reset', PNG)
    Overlay.add_button('menu', PNG)
    frame
    menu = positions['menu']
    load_file('buttons' => { 'reset' => { 'anchor' => 'bottom_left', 'x' => 0.5, 'y' => 0.5 } })
    frame
    assert_equal menu, positions['menu']
  end

  def test_a_broken_image_only_drops_its_button
    _, err = capture_io do
      assert load_file({ 'buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'r.png' } } },
                       ->(_) { "\x89PNG corrupt".b })
      frame
      @window.resize(1080, 2424)
      frame
    end
    assert_equal 1, err.scan('no run button').size
    assert @window.touch_overlay.enabled?
    assert_nil button('run')
    window = nil
    capture_io { (window = LiteRGSS::DisplayWindow.new(2424, 1080)).update }
    assert window.touch_overlay.enabled?
  end

  def test_relayouts_dispose_the_images_they_replace
    load_file('buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'r.png' } })
    frame
    run = @window.touch_overlay.instance_variable_get(:@sprites)['run'].bitmap
    @window.resize(1080, 2424)
    frame
    assert run.disposed?
    run = @window.touch_overlay.instance_variable_get(:@sprites)['run'].bitmap
    refute run.disposed?
    Overlay.clear_layout
    frame
    assert run.disposed?
  end

  def test_a_broken_file_image_keeps_the_game_button_of_its_name
    Overlay.add_button('run', PNG)
    capture_io do
      load_file({ 'buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'r.png' } } },
                ->(_) { "\x89PNG corrupt".b })
      frame
    end
    @window.queue(:touch_began, 0, *center('run'))
    frame
    assert Overlay.triggered?('run')
  end

  def test_a_game_image_giving_no_bitmap_only_drops_its_button
    disposed = LiteRGSS::Bitmap.new(PNG, true).tap(&:dispose)
    Overlay.add_button('menu', -> {})
    Overlay.add_button('keys', -> { disposed })
    capture_io { frame }
    assert @window.touch_overlay.enabled?
    assert_nil button('menu')
    assert_nil button('keys')
  end

  def test_a_hidden_file_button_needs_no_place_nor_image
    Overlay.add_button('run', PNG)
    read = []
    capture_io do
      assert load_file({ 'buttons' => { 'run' => { 'visible' => false, 'key' => 'LShift', 'image' => 'r.png' },
                                        'start' => { 'visible' => false } } }, ->(path) { read << path; PNG })
    end
    frame
    assert_empty read
    assert_nil button('run')
    assert_nil button('start')
  end

  def test_buttons_sharing_an_image_share_its_bitmap
    run = { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'r.png' }
    image = "\x89PNG shared".b
    load_file({ 'buttons' => { 'run' => run, 'walk' => run.merge('x' => 0.6, 'key' => 'RShift') } }, ->(_) { image })
    frame
    sprites = @window.touch_overlay.instance_variable_get(:@sprites)
    assert_same sprites['run'].bitmap, sprites['walk'].bitmap
    Overlay.clear_layout
    frame
    assert sprites['run'].bitmap.disposed?
  end

  def test_a_file_hiding_everything_survives_a_soft_reset
    load_file('groups' => { 'dpad' => { 'visible' => false }, 'action' => { 'visible' => false } },
              'buttons' => (%w[l r select start] + [Overlay::TOOLS]).to_h { |name| [name, { 'visible' => false }] })
    frame
    assert_empty @window.touch_overlay.layout.buttons
    @window.touch_overlay.instance_variable_get(:@bitmaps).each_value(&:dispose)
    frame
    Overlay.clear_layout
    frame
    assert @window.touch_overlay.enabled?
    refute(@window.touch_overlay.instance_variable_get(:@sprites).each_value.any? { |sprite| sprite.bitmap.disposed? })
  end

  def test_a_resized_window_keeps_the_file_places
    load_file('buttons' => { 'start' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5 } })
    frame
    @window.resize(1080, 2424)
    frame
    assert_equal [540, 1212], positions['start'][0, 2]
  end

  def test_a_file_button_held_while_the_file_goes_is_released_with_its_key
    load_file('buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'r.png' } })
    frame
    run = center('run')
    @window.queue(:touch_began, 0, *run)
    frame
    Overlay.clear_layout
    frame
    @window.queue(:touch_ended, 0, *run)
    frame
    assert_equal [Sf::Keyboard::Scancode::LShift], @game[:key_released].map { |args| args[1] }
  end

  def test_a_hidden_button_lets_its_touches_reach_the_game
    select = center('select')
    load_file('buttons' => { 'select' => { 'visible' => false } }, 'groups' => { 'dpad' => { 'visible' => false } })
    frame
    assert_nil button('select')
    assert_nil button('up')
    @window.queue(:touch_began, 0, *select)
    frame
    assert_equal [[0, *select]], @game[:touch_began]
  end

  def test_a_button_of_the_file_sends_its_key
    paths = []
    load_file({ 'buttons' => { 'run' => { 'anchor' => 'top_right', 'x' => 0, 'y' => 0, 'key' => 'LShift', 'image' => 'touch/run.png' } } },
              ->(path) { paths << path; PNG })
    frame
    assert_equal ['touch/run.png'], paths
    @window.queue(:touch_began, 0, *center('run'))
    frame
    @window.queue(:touch_ended, 0, *center('run'))
    frame
    assert_equal [Sf::Keyboard::Scancode::LShift], @game[:key_pressed].map { |args| args[1] }
    assert_equal [Sf::Keyboard::Scancode::LShift], @game[:key_released].map { |args| args[1] }
    refute Overlay.triggered?('run')
    assert_nil Overlay.consume_pressed_button
  end

  def test_the_file_places_a_game_button
    Overlay.add_button('reset', PNG)
    load_file('buttons' => { 'reset' => { 'anchor' => 'bottom_left', 'x' => 0, 'y' => 0 } })
    frame
    reset = button('reset')
    assert_equal [0, 1080 - reset.size], [reset.x, reset.y]
    @window.queue(:touch_began, 0, *center('reset'))
    frame
    assert Overlay.triggered?('reset')
  end

  def test_a_button_of_the_file_replaces_the_game_button_of_its_name
    Overlay.add_button('run', PNG)
    _, err = capture_io do
      load_file('buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'run.png' } })
    end
    assert_match(/run button replaces the game's/, err)
    frame
    assert_equal 1, @window.touch_overlay.layout.buttons.count { |b| b.name == 'run' }
    @window.queue(:touch_began, 0, *center('run'))
    frame
    assert_equal [Sf::Keyboard::Scancode::LShift], @game[:key_pressed].map { |args| args[1] }
  end

  def test_the_file_action_layout_wins
    a = center('a')
    b = center('b')
    load_file('action_layout' => 'xbox')
    frame
    assert_equal [a, b], [center('b'), center('a')]
  end

  def test_clearing_the_layout_file_restores_the_default
    default = positions
    load_file('buttons' => { 'start' => { 'visible' => false } })
    frame
    Overlay.clear_layout
    frame
    assert_equal default, positions
  end

  def test_an_invalid_layout_file_changes_nothing
    load_file('buttons' => { 'start' => { 'visible' => false } })
    frame
    kept = positions
    invalid = [
      'not json',
      '[]',
      JSON.generate('version' => 2),
      JSON.generate('version' => 1, 'action_layout' => 'sega'),
      JSON.generate('version' => 1, 'groups' => { 'sticks' => {} }),
      JSON.generate('version' => 1, 'groups' => { 'dpad' => { 'anchor' => 'middle', 'x' => 0, 'y' => 0 } }),
      JSON.generate('version' => 1, 'groups' => { 'dpad' => { 'anchor' => 'top_left', 'x' => 2, 'y' => 0 } }),
      JSON.generate('version' => 1, 'groups' => { 'dpad' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0, 'gap' => 0 } }),
      JSON.generate('version' => 1, 'buttons' => { 'start' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0, 'size' => 9 } }),
      JSON.generate('version' => 1, 'buttons' => { 'a' => { 'visible' => false } }),
      JSON.generate('version' => 1, 'buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0, 'key' => 'Nope', 'image' => 'r.png' } }),
      JSON.generate('version' => 1, 'buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0, 'key' => 'LShift' } }),
      JSON.generate('version' => 1, 'buttons' => []),
      JSON.generate('version' => 1, 'buttons' => { 'start' => 5 }),
      JSON.generate('version' => 1, 'buttons' => { 'start' => { 'key' => 'LShift' } }),
      JSON.generate('version' => 1, 'buttons' => { 'run' => { 'key' => 'LShift', 'image' => 'r.png' } }),
      JSON.generate('version' => 1, 'buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0, 'key' => 'lshift', 'image' => 'r.png' } }),
      JSON.generate('version' => 1, 'action_layout' => 5),
      '{"version": 1, "groups": {"dpad": {"size": NaN}}}',
      JSON.generate('version' => 1, 'buttons' => { 'start' => { 'visible' => 'no' } }),
      JSON.generate('version' => 1, 'buttons' => { 'dpad' => { 'visible' => false } }),
      JSON.generate('version' => 1, 'buttons' => { 'start' => { 'visible' => false, 'anchor' => 'bogus', 'x' => 0, 'y' => 0 } }),
      JSON.generate('version' => 1, 'buttons' => { 'run' => { 'anchor' => nil, 'key' => 'LShift', 'image' => 'r.png' } })
    ]
    invalid.each do |json|
      _, err = capture_io { refute Overlay.load_layout(json, read_image: ->(_) { PNG }), json }
      assert_match(/layout file ignored/, err)
    end
    missing = JSON.generate('version' => 1, 'buttons' => { 'run' => { 'anchor' => 'top_left', 'x' => 0, 'y' => 0, 'key' => 'LShift', 'image' => 'r.png' } })
    [->(path) { File.binread("/nonexistent/#{path}") }, ->(_) { nil }, ->(_) { 'GIF89a' }].each do |read_image|
      capture_io { refute Overlay.load_layout(missing, read_image: read_image) }
    end
    frame
    assert_equal kept, positions
  end

  # ── Tools menu and layout editor ──

  def menu_names
    @window.touch_overlay.send(:menu_buttons).map(&:name)
  end

  def editor
    @window.touch_overlay.instance_variable_get(:@editor)
  end

  def toolbar_center(name)
    button = editor.toolbar(@window.touch_overlay.layout).find { |b| b.name == name }
    [button.x + button.size / 2, button.y + button.size / 2]
  end

  def drag(from, to, finger = 0)
    @window.queue(:touch_began, finger, *from)
    frame
    @window.queue(:touch_moved, finger, *to)
    frame
    @window.queue(:touch_ended, finger, *to)
    frame
  end

  def open_editor
    tap_menu(Overlay::EDIT)
    frame
    refute_nil editor
  end

  def saved
    json = nil
    Overlay.on_layout_saved = ->(file) { json = file }
    tap_at(toolbar_center(Overlay::DONE))
    frame
    json && JSON.parse(json)
  end

  def test_the_tools_button_opens_its_menu_beside_it
    tap_at(center(Overlay::TOOLS))
    frame
    tools = button(Overlay::TOOLS)
    entries = @window.touch_overlay.send(:menu_buttons)
    assert_equal [Overlay::KEYBOARD, Overlay::EDIT], entries.map(&:name)
    assert(entries.all? { |b| b.y == tools.y && b.x > tools.x })
    live = @window.viewports.reject(&:disposed?)
    assert_equal @window.touch_overlay.layout.buttons.size + 2, live.size
  end

  def test_a_touch_outside_the_menu_closes_it_without_reaching_the_game
    tap_at(center(Overlay::TOOLS))
    frame
    tap_at([1212, 300])
    frame
    assert_empty @game[:touch_began]
    refute @window.touch_overlay.instance_variable_get(:@menu_open)
    tap_at([1212, 300])
    assert_equal 1, @game[:touch_began].size
  end

  def test_the_editor_takes_every_touch_and_sends_no_key
    open_editor
    tap_at(center('a'))
    frame
    tap_at([1212, 600])
    frame
    assert_empty @game[:key_pressed]
    assert_empty @game[:touch_began]
    assert_empty @game[:touch_ended]
  end

  def test_opening_the_editor_releases_the_held_keys
    @window.queue(:touch_began, 1, *center('a'))
    frame
    tap_menu(Overlay::EDIT)
    frame
    assert_equal [Sf::Keyboard::Scancode::Enter], @game[:key_released].map { |args| args[1] }
    @window.queue(:touch_ended, 1, *center('a'))
    frame
    assert_empty @game[:touch_ended]
  end

  def test_a_dragged_cross_is_saved_where_it_was_dropped
    open_editor
    dpad = @window.touch_overlay.layout.crosses.first
    from = [dpad.x + dpad.size / 2, dpad.y + dpad.size / 2]
    drag(from, [from[0] + 300, from[1] - 100])
    moved = @window.touch_overlay.layout.crosses.first
    assert_equal [dpad.x + 300, dpad.y - 100], [moved.x, moved.y]
    file = saved
    assert_nil editor
    entry = file['groups']['dpad']
    assert_equal 'bottom_left', entry['anchor']
    assert_in_delta (dpad.x + 300) / 2424.0, entry['x'], 0.0001
    assert_in_delta (1080 - dpad.y + 100 - dpad.size) / 1080.0, entry['y'], 0.0001
    # Kept once the editor closed, and the gamepad works again
    assert_equal [dpad.x + 300, dpad.y - 100], @window.touch_overlay.layout.crosses.first.to_a[0, 2]
    tap_at(center('a'))
    assert_equal [Sf::Keyboard::Scancode::Enter], @game[:key_pressed].map { |args| args[1] }
  end

  def test_the_corner_handle_resizes_a_button
    open_editor
    start = button('start')
    tap_at(center('start'))
    frame
    handle = editor.handles(@window.touch_overlay.layout).first
    drag([handle.x + handle.size / 2, handle.y + handle.size / 2], [start.x + 256, start.y + 256])
    assert_equal 256, button('start').size
    assert_in_delta 2.0, saved['buttons']['start']['size'], 0.001
  end

  def test_the_gap_handle_spreads_a_cross
    open_editor
    action = @window.touch_overlay.layout.crosses.last
    tap_at([action.x + action.size / 2, action.y + action.size / 2])
    frame
    handle = editor.handles(@window.touch_overlay.layout).last
    assert_equal :gap, handle.kind
    # 320 pixel box of 128 pixel buttons: gap 1; a 512 pixel one is gap 2
    drag([handle.x + handle.size / 2, handle.y + handle.size / 2], [action.x + 512, handle.y])
    assert_equal 512, @window.touch_overlay.layout.crosses.last.size
    assert_in_delta 2.0, saved['groups']['action']['gap'], 0.001
  end

  def test_reset_drops_the_places_but_keeps_the_players_buttons
    run = { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'run.png' }
    Overlay.load_layout(JSON.generate('version' => 1, 'buttons' => { 'run' => run, 'select' => { 'visible' => false } }),
                        read_image: ->(_) { PNG }, player: true)
    frame
    default_start = positions['start']
    open_editor
    drag(center('start'), [600, 300])
    drag(center('run'), [900, 300])
    refute_equal default_start, positions['start']
    tap_at(toolbar_center(Overlay::RESET))
    frame
    assert_equal default_start, positions['start']
    file = saved
    # The file's own button has no default place: it keeps where it went
    moved_run = run.merge('x' => (900 - 64) / 2424.0, 'y' => (300 - 64) / 1080.0)
    assert_equal({ 'version' => 1, 'buttons' => { 'run' => moved_run.transform_values { |v| v.is_a?(Float) ? v.round(4) : v },
                                                  'select' => { 'visible' => false } } }, file)
  end

  def test_the_players_layout_goes_over_the_games
    capture_io do
      Overlay.load_layout(JSON.generate('version' => 1, 'buttons' => {
                                          'start' => { 'anchor' => 'top_left', 'x' => 0.1, 'y' => 0.1 },
                                          'run' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'r.png' },
                                          'jump' => { 'anchor' => 'top_left', 'x' => 0.6, 'y' => 0.5, 'key' => 'RShift', 'image' => 'j.png' }
                                        }), read_image: ->(_) { PNG })
      Overlay.load_layout(JSON.generate('version' => 1, 'buttons' => {
                                          'start' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.0 },
                                          'jump' => { 'visible' => false }
                                        }), read_image: ->(_) { PNG }, player: true)
    end
    frame
    assert_equal [1212, 0], positions['start'][0, 2]
    refute_nil button('run')
    assert_nil button('jump')
  end

  def test_a_failing_host_callback_keeps_the_saved_layout
    open_editor
    Overlay.on_layout_saved = ->(_) { raise IOError, 'disk full' }
    _, err = capture_io do
      tap_at(toolbar_center(Overlay::DONE))
      frame
    end
    assert_match(/not handed to the host/, err)
    assert_nil editor
    assert @window.touch_overlay.enabled?
  end

  def load_game_file(buttons: {}, groups: {})
    capture_io do
      assert Overlay.load_layout(JSON.generate('version' => 1, 'buttons' => buttons, 'groups' => groups), read_image: ->(_) { PNG })
    end
    frame
  end

  def test_moving_keeps_the_size_the_game_file_gives
    load_game_file(buttons: { 'start' => { 'size' => 1.5 } }, groups: { 'dpad' => { 'size' => 1.5, 'gap' => 2 } })
    start = button('start').size
    dpad = @window.touch_overlay.layout.crosses.first.size
    open_editor
    drag(center('start'), [600, 300])
    from = [@window.touch_overlay.layout.crosses.first.x + 10, @window.touch_overlay.layout.crosses.first.y + 10]
    drag(from, [from[0] + 50, from[1] - 50])
    file = saved
    assert_equal start, button('start').size
    assert_equal dpad, @window.touch_overlay.layout.crosses.first.size
    # Only what changed is written: the game's file gives the rest
    assert_equal %w[anchor x y], file['buttons']['start'].keys
  end

  def test_moving_a_button_of_the_game_file_keeps_it
    load_game_file(buttons: { 'run' => { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'r.png' } })
    open_editor
    drag(center('run'), [600, 300])
    saved
    refute_nil button('run')
    tap_at(center('run'))
    assert_equal [Sf::Keyboard::Scancode::LShift], @game[:key_pressed].map { |args| args[1] }
  end

  def test_a_lost_touch_end_does_not_lock_the_editor
    open_editor
    @window.queue(:touch_began, 0, *center('start'))
    frame
    # Its end never comes: Done still works
    tap_at(toolbar_center(Overlay::DONE), 1)
    frame
    assert_nil editor
  end

  def test_a_finger_left_on_done_stays_the_overlays
    open_editor
    @window.queue(:touch_began, 3, *toolbar_center(Overlay::DONE))
    frame
    @window.queue(:touch_moved, 3, *center('a'))
    @window.queue(:touch_ended, 3, *center('a'))
    frame
    frame
    assert_empty @game[:touch_moved]
    assert_empty @game[:touch_ended]
    assert_empty @game[:key_pressed]
  end

  def test_resizing_keeps_the_top_left_corner_whatever_the_size_becomes
    open_editor
    start = button('start')
    tap_at(center('start'))
    frame
    handle = editor.handles(@window.touch_overlay.layout).first
    grab = [handle.x + handle.size / 2, handle.y + handle.size / 2]
    # Far up-left of its corner: the smallest size, still at the same place
    drag(grab, [start.x - 500, start.y - 500])
    small = button('start')
    assert_equal [start.x, start.y, 32], small.to_a[1, 3]
    # 1.4 times the size snaps to x11: no jump either
    handle = editor.handles(@window.touch_overlay.layout).first
    drag([handle.x + handle.size / 2, handle.y + handle.size / 2], [start.x + 180, start.y + 180])
    assert_equal [start.x, start.y, 176], button('start').to_a[1, 3]
  end

  def test_the_handles_stay_inside_the_window
    open_editor
    action = @window.touch_overlay.layout.crosses.last
    drag([action.x + action.size / 2, action.y + action.size / 2], [3000, 2000])
    layout = @window.touch_overlay.layout
    editor.handles(layout).each do |handle|
      assert_operator handle.x + handle.size, :<=, 2424
      assert_operator handle.y + handle.size, :<=, 1080
    end
  end

  def test_sliding_onto_the_tools_button_does_not_open_the_menu
    @window.queue(:touch_began, 0, *center('l'))
    frame
    @window.queue(:touch_moved, 0, *center(Overlay::TOOLS))
    frame
    @window.queue(:touch_ended, 0, *center(Overlay::TOOLS))
    frame
    refute @window.touch_overlay.instance_variable_get(:@menu_open)
  end

  def test_a_layout_loaded_while_editing_closes_the_editor
    open_editor
    drag(center('start'), [600, 300])
    load_game_file(buttons: { 'select' => { 'visible' => false } })
    assert_nil editor
    assert_nil button('select')
  end

  def test_the_editor_reads_the_players_images_once
    reads = 0
    run = { 'anchor' => 'top_left', 'x' => 0.5, 'y' => 0.5, 'key' => 'LShift', 'image' => 'run.png' }
    Overlay.load_layout(JSON.generate('version' => 1, 'buttons' => { 'run' => run }), read_image: ->(_) { reads += 1; PNG }, player: true)
    frame
    open_editor
    3.times { |i| drag(center('start'), [600 + i * 10, 300]) }
    assert_equal 1, reads
  end

  def test_a_game_button_added_while_editing_keeps_the_edits
    open_editor
    drag(center('start'), [600, 300])
    moved = positions['start']
    Overlay.add_button('reset', PNG)
    frame
    refute_nil editor
    assert_equal moved, positions['start']
    refute_nil button('reset')
  end

  def test_a_cross_the_game_file_grows_stays_inside_the_window
    load_game_file(groups: { 'dpad' => { 'gap' => 2 } })
    dpad = @window.touch_overlay.layout.crosses.first
    assert_operator dpad.x, :>=, 0
    assert_operator dpad.y + dpad.size, :<=, 1080
  end

  def test_a_game_button_cannot_take_a_group_name
    assert_raises(ArgumentError) { Overlay.add_button('dpad', PNG) }
  end

  def test_a_layout_loaded_with_a_soft_reset_still_closes_the_editor
    open_editor
    drag(center('start'), [600, 300])
    capture_io { Overlay.load_layout(JSON.generate('version' => 1, 'buttons' => { 'select' => { 'visible' => false } }), read_image: ->(_) { PNG }) }
    @window.viewports.each(&:dispose)
    frame
    assert_nil editor
    assert_nil button('select')
  end

  def test_done_after_a_new_player_file_does_not_overwrite_it
    open_editor
    done = toolbar_center(Overlay::DONE)
    drag(center('start'), [600, 300])
    player = JSON.generate('version' => 1, 'buttons' => { 'select' => { 'visible' => false } })
    Overlay.load_layout(player, read_image: ->(_) { PNG }, player: true)
    saves = []
    Overlay.on_layout_saved = ->(json) { saves << json }
    # The tap comes before the next update
    tap_at(done)
    assert_empty saves
    assert_nil editor
    assert_nil button('select')
  end
end
