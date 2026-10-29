# On-screen gamepad for touch devices, drawn by LiteRGSS on top of any game.
#
#   require 'litergss/touch_overlay'
#   LiteRGSS::TouchOverlay.install   # before the game creates its window
#
# It only relies on LiteRGSS, never on the game's scripts, so it works the same
# for every PSDK version, compiled or not:
# - every LiteRGSS::DisplayWindow gets the overlay when it is created;
# - a touch on a button never reaches the game: the window's touch callbacks
#   are wrapped, so the game's own touch / mouse emulation only sees the
#   touches outside the buttons;
# - a button sends the key events a keyboard would, through the key callbacks
#   the game registered on the window (same arguments as LiteRGSS passes).
#
# The key a button sends is read from the game's Input::Keys (first keyboard
# binding of its virtual key) when the game has one, else from DEFAULT_KEYS.
# The keyboard button shows / hides the system's virtual keyboard. The
# keyboard also shows by itself when the player taps a text entry of the game
# (TextEntry), and hides once there is none left.
#
# A game drawing its own touch controls (Input::InputTouch, as pokemonsdk did
# for Android) keeps them: the overlay never shows on its windows.
#
# Layout and images come from PSDK's former "InputTouch Viewport" (pokemonsdk),
# in window pixels instead of game pixels.
#
# The runtime ships this directory with the Ruby standard library
# (cmake/litergss-app/ruby-client.cmake): the images are read next to this file.
module LiteRGSS
  module TouchOverlay
    # Virtual key => keyboard scancode name (Sf::Keyboard::Scancode constant),
    # used when the game has no Input::Keys binding for it.
    DEFAULT_KEYS = {
      UP: :Up, DOWN: :Down, LEFT: :Left, RIGHT: :Right,
      A: :Enter, B: :Escape, X: :Menu, Y: :B,
      L: :F, R: :G, START: :Insert, SELECT: :Pause
    }.freeze

    # Image name => virtual key
    BUTTON_KEYS = {
      'up' => :UP, 'down' => :DOWN, 'left' => :LEFT, 'right' => :RIGHT,
      'a' => :A, 'b' => :B, 'x' => :X, 'y' => :Y,
      'l' => :L, 'r' => :R, 'start' => :START, 'select' => :SELECT
    }.freeze

    # Button showing / hiding the virtual keyboard (not a key)
    KEYBOARD = 'keyboard'

    IMAGES = (BUTTON_KEYS.keys + [KEYBOARD]).to_h do |name|
      [name, File.binread(File.join(__dir__, 'touch_overlay', "#{name}.png")).freeze]
    end.freeze

    Z = 999_999
    # Key code sent with the scancode: sf::Keyboard::Unknown (LiteRGSS has no
    # constant for it; games read the scancode)
    UNKNOWN_KEY = -1
    # Opacity of a button at rest / while pressed
    OPACITY = 127
    PRESSED_OPACITY = 220
    # The layout is designed for a 240 pixel high screen (PSDK's), scaled to the window.
    DESIGN_HEIGHT = 240.0

    # Position and size of every button, in window pixels.
    #
    # The D-pad and the A/B/X/Y buttons are crosses of four buttons in a square
    # box: their images overlap at the corners, so a touch in a box goes to the
    # nearest button of the cross, like on a physical pad.
    class Layout
      Button = Struct.new(:name, :x, :y, :size) do
        def include?(px, py)
          px >= x && py >= y && px < x + size && py < y + size
        end

        def distance2(px, py)
          (x + size / 2.0 - px)**2 + (y + size / 2.0 - py)**2
        end
      end

      Cross = Struct.new(:x, :y, :size, :buttons) do
        def include?(px, py)
          px >= x && py >= y && px < x + size && py < y + size
        end
      end

      attr_reader :buttons, :crosses, :zoom

      # @param width [Integer] window width
      # @param height [Integer] window height
      # @param image_size [Integer] side of the (square) button images
      def initialize(width, height, image_size)
        unit = [width, height].min / DESIGN_HEIGHT
        box = [width, height].min * 0.3
        # Buttons were 32 pixels in a 72 pixel box; integer zoom keeps the pixel art sharp
        @zoom = [(box * 32 / 72 / image_size).round, 1].max
        size = image_size * @zoom
        padding = (20 * unit).round

        box_y = ((height - box) * 0.9).round
        dpad_x = padding
        action_x = (width - box - padding).round
        row_y = box_y - size
        @crosses = [cross(dpad_x, box_y, box, size, %w[up right down left]),
                    cross(action_x, box_y, box, size, %w[y a b x])]
        gap = (8 * unit).round
        @row = [Button.new('l', padding, row_y, size),
                Button.new('r', width - padding - size, row_y, size),
                Button.new('select', padding + size + gap, row_y, size),
                Button.new('start', width - padding - 2 * size - gap, row_y, size),
                Button.new(KEYBOARD, padding, row_y - size - gap, size)]
        @buttons = @crosses.flat_map(&:buttons) + @row
      end

      def button_at(px, py)
        cross = @crosses.find { |c| c.include?(px, py) }
        return cross.buttons.min_by { |button| button.distance2(px, py) } if cross

        @row.find { |button| button.include?(px, py) }
      end

      private

      # Four buttons on the edges of a square box: top, right, bottom, left
      def cross(box_x, box_y, box, size, names)
        middle = ((box - size) / 2).round
        far = (box - size).round
        side = far + size
        top, right, bottom, left = names
        Cross.new(box_x, box_y, side, [Button.new(top, box_x + middle, box_y, size),
                                       Button.new(right, box_x + far, box_y + middle, size),
                                       Button.new(bottom, box_x + middle, box_y + far, size),
                                       Button.new(left, box_x, box_y + middle, size)])
      end
    end

    # The text entry a game shows, found through the shared engine (PSDK) it
    # runs on, never through the game's own scripts. Duck-typed: an engine
    # without these classes simply has no automatic keyboard.
    # - UI::UserInput, PSDK's text field (Bag / Storage search...): a
    #   LiteRGSS::Text, whose position on the window is known;
    # - GamePlay::NameInput, the name input scene: the whole screen is the
    #   entry (its field differs between PSDK versions and games).
    module TextEntry
      @fields = []
      @hooked = false

      # Remembers every UI::UserInput created
      module FieldTracking
        # Passes keyword arguments through, whatever the engine's signature
        ruby2_keywords def initialize(*args, &block)
          super
          TextEntry.track(self)
        end
      end

      module_function

      # UI::UserInput is defined by the game's scripts, after the overlay is
      # installed: hook it once it exists
      def hook
        return if @hooked || !defined?(::UI::UserInput)

        ::UI::UserInput.prepend(FieldTracking)
        @hooked = true
      end

      def track(field)
        @fields << field
      end

      # Forget the tracked fields (tests)
      def reset
        @fields.clear
      end

      # @return [Array] the fields on screen
      def fields
        @fields.reject! { |field| field.disposed? }
        @fields.select { |field| field.visible && field.viewport&.visible != false }
      end

      def scene?
        defined?(::GamePlay::NameInput) && $scene.is_a?(::GamePlay::NameInput) ? true : false
      end

      def any?
        scene? || !fields.empty?
      end

      # Is a text entry at this window position?
      def at?(x, y)
        scene? || fields.any? { |field| include?(field, x, y) }
      end

      # The field's rectangle on the window: its viewport's rect, shifted by
      # the viewport's origin and scaled by its zoom (a margin keeps small
      # fields easy to tap)
      def include?(field, x, y)
        viewport = field.viewport
        return false unless viewport

        rect = viewport.rect
        zoom = viewport.zoom.to_f
        left = rect.x + (field.x - viewport.ox) * zoom
        top = rect.y + (field.y - viewport.oy) * zoom
        width = [field.width, field.respond_to?(:real_width) ? field.real_width : 0].max * zoom
        height = [field.height, 16].max * zoom
        margin = height / 2
        x >= left - margin && x < left + width + margin && y >= top - margin && y < top + height + margin
      end
    end

    # The overlay of one window: its sprites, the fingers on its buttons and
    # the keys they hold down.
    class Overlay
      attr_reader :layout

      # @param window [LiteRGSS::DisplayWindow]
      def initialize(window)
        @window = window
        @fingers = {}   # finger => button name, or nil when the game owns the touch
        @pressed = {}   # button name => true
        # Buttons touched since the last frame: held for one frame at least, so
        # a tap shorter than a frame (down and up in the same poll) still presses
        @touched = []
        @game_procs = {}
        build
      end

      # Keep the game's callback for a window event (:key_pressed, :touch_began...)
      def store_game_proc(event, proc)
        @game_procs[event] = proc
      end

      # A finger that began on a button belongs to the overlay until it is
      # lifted: @fingers holds the button under it, or false between buttons.
      # A finger that began elsewhere belongs to the game (nil).
      def touch_began(finger, x, y)
        position = to_window(x, y)
        button = @enabled && @layout.button_at(*position)
        @fingers[finger] = button ? button.name : nil
        @touched << button.name if button
        return if button

        # Checked in update, once the game took the touch into account
        @game_tap = position
        forward(:touch_began, finger, x, y)
      end

      def touch_moved(finger, x, y)
        if owned?(finger)
          # Sliding a finger moves it to the button under it (D-pad direction changes)
          button = @layout.button_at(*to_window(x, y))
          @fingers[finger] = button ? button.name : false
          @touched << button.name if button
        else
          forward(:touch_moved, finger, x, y)
        end
      end

      def touch_ended(finger, x, y)
        owned = owned?(finger)
        @fingers.delete(finger)
        forward(:touch_ended, finger, x, y) unless owned
      end

      # Send the key events of the buttons pressed or released since the last
      # frame; called after the window polled its events.
      def update
        relayout if @window.width != @width || @window.height != @height
        held = (@fingers.values.select { |name| name } + @touched).uniq
        @touched.clear
        (@pressed.keys - held).each { |name| release(name) }
        (held - @pressed.keys).each { |name| press(name) }
        update_text_entry
      end

      def enabled?
        @enabled
      end

      # The game draws its own touch controls, or the overlay failed: stay out
      # of the game's way, every touch goes to it.
      def disable
        @enabled = false
        @fingers.clear
        @touched.clear
        dispose
        # Let the game see the held keys released; each on its own, so a
        # failing one (the reason of the disable) does not keep the others down
        @pressed.keys.each do |name|
          release(name)
        rescue StandardError
          @pressed.delete(name)
        end
      end

      def dispose
        @viewports&.each { |viewport| viewport.dispose unless viewport.disposed? }
        @viewports = nil
        @sprites = nil
      end

      private

      def build
        @enabled = true
        @bitmaps = IMAGES.transform_values { |data| LiteRGSS::Bitmap.new(data, true) }
        relayout
      end

      def relayout
        dispose
        @width = @window.width
        @height = @window.height
        @layout = Layout.new(@width, @height, @bitmaps.values.first.width)
        return unless @enabled

        @sprites = {}
        @viewports = @layout.buttons.map do |button|
          viewport = LiteRGSS::Viewport.new(@window, button.x, button.y, button.size, button.size)
          viewport.z = Z
          sprite = LiteRGSS::Sprite.new(viewport)
          sprite.bitmap = @bitmaps[button.name]
          sprite.zoom = @layout.zoom
          lit = button.name == KEYBOARD ? @keyboard_shown : @pressed[button.name]
          sprite.opacity = lit ? PRESSED_OPACITY : OPACITY
          @sprites[button.name] = sprite
          viewport
        end
        @window.sort_z
      end

      def toggle_keyboard
        show_keyboard(!@keyboard_shown)
      end

      # The button stays lit while the keyboard is shown. The system can also
      # hide it (back gesture): then the next tap only syncs the state.
      # @param automatic [Boolean] shown for a text entry, hidden with it
      def show_keyboard(shown, automatic: false)
        @keyboard_shown = shown
        @keyboard_automatic = shown && automatic
        Sf::Keyboard.virtual_keyboard = shown if Sf::Keyboard.respond_to?(:virtual_keyboard=)
        @sprites&.[](KEYBOARD)&.opacity = shown ? PRESSED_OPACITY : OPACITY
      end

      # Show the keyboard for a tap on a text entry, hide it with the entry
      def update_text_entry
        TextEntry.hook
        tap = @game_tap
        @game_tap = nil
        if tap && !@keyboard_shown && TextEntry.at?(*tap)
          show_keyboard(true, automatic: true)
        elsif @keyboard_automatic && !TextEntry.any?
          show_keyboard(false)
        end
      end

      def owned?(finger)
        @fingers.key?(finger) && !@fingers[finger].nil?
      end

      # Touches come in screen pixels, the window may have another resolution
      def to_window(x, y)
        [x * @width / LiteRGSS::DisplayWindow.desktop_width,
         y * @height / LiteRGSS::DisplayWindow.desktop_height]
      end

      def forward(event, *args)
        @game_procs[event]&.call(*args)
      end

      def press(name)
        @pressed[name] = true
        return toggle_keyboard if name == KEYBOARD

        @sprites&.[](name)&.opacity = PRESSED_OPACITY
        scancode = TouchOverlay.scancode(BUTTON_KEYS[name])
        forward(:key_pressed, UNKNOWN_KEY, scancode, false, false, false, false) if scancode
      end

      def release(name)
        @pressed.delete(name)
        return if name == KEYBOARD

        @sprites&.[](name)&.opacity = OPACITY
        scancode = TouchOverlay.scancode(BUTTON_KEYS[name])
        forward(:key_released, UNKNOWN_KEY, scancode) if scancode
      end
    end

    # Prepended to LiteRGSS::DisplayWindow: keeps the game's event callbacks and
    # puts the overlay in front of the touch ones.
    module WindowHooks
      %i[key_pressed key_released].each do |event|
        define_method(:"on_#{event}=") do |proc|
          @__touch_overlay&.store_game_proc(event, proc)
          super(proc)
        end
      end

      %i[touch_began touch_moved touch_ended].each do |event|
        define_method(:"on_#{event}=") do |proc|
          return super(proc) unless @__touch_overlay

          @__touch_overlay.store_game_proc(event, proc)
          # The overlay's dispatcher stays installed whatever the game sets
          proc
        end
      end

      def update(*args)
        overlay = @__touch_overlay
        # Checked before drawing: a game defining its touch controls after
        # creating its window never shows both
        overlay.disable if overlay&.enabled? && TouchOverlay.game_has_touch_controls?
        result = super
        TouchOverlay.guard(overlay) { overlay.update } if overlay&.enabled?
        result
      end

      def dispose(*args)
        @__touch_overlay&.dispose
        @__touch_overlay = nil
        super
      end

      # Attach the overlay; called right after the window is created.
      def __attach_touch_overlay
        overlay = Overlay.new(self)
        @__touch_overlay = overlay
        %i[touch_began touch_moved touch_ended].each do |event|
          dispatcher = proc do |finger, x, y|
            if overlay.enabled?
              TouchOverlay.guard(overlay) { overlay.send(event, finger, x, y) }
            else
              overlay.send(:forward, event, finger, x, y)
            end
          end
          method(:"on_#{event}=").super_method.call(dispatcher)
        end
        overlay
      end

      # @return [Overlay, nil]
      def touch_overlay
        @__touch_overlay
      end
    end

    # Prepended to LiteRGSS::DisplayWindow's singleton: attaches the overlay to
    # every window created.
    module WindowCreation
      def new(*args, &block)
        window = super
        begin
          window.__attach_touch_overlay if TouchOverlay.enabled? && !TouchOverlay.game_has_touch_controls?
        rescue StandardError => e
          warn "[TouchOverlay] disabled: #{e.class}: #{e.message}"
        end
        window
      end
    end

    @enabled = true

    class << self
      # Hook LiteRGSS::DisplayWindow (idempotent)
      def install
        return if LiteRGSS::DisplayWindow.ancestors.include?(WindowHooks)

        LiteRGSS::DisplayWindow.prepend(WindowHooks)
        LiteRGSS::DisplayWindow.singleton_class.prepend(WindowCreation)
      end

      def enabled?
        @enabled
      end

      # Disable the overlay for the windows created from now on
      attr_writer :enabled

      # Run overlay code; an error disables the overlay instead of reaching the
      # game (an on-screen gamepad must never crash a game)
      def guard(overlay)
        yield
      rescue StandardError => e
        warn "[TouchOverlay] disabled: #{e.class}: #{e.message} (#{e.backtrace&.first})"
        begin
          overlay.disable
        rescue StandardError
          nil
        end
      end

      # The game draws its own touch controls (pokemonsdk's former
      # "InputTouch Viewport", still in games exported before the overlay)
      def game_has_touch_controls?
        defined?(::Input::InputTouch) ? true : false
      end

      # Keyboard scancode a virtual key sends
      # @param key [Symbol] :A, :UP...
      # @return [Integer, nil]
      def scancode(key)
        if defined?(::Input::Keys) && ::Input::Keys.respond_to?(:[]) && (bindings = ::Input::Keys[key])
          # Negative values are joystick bindings
          code = Array(bindings).find { |value| value.is_a?(Integer) && value >= 0 }
          return code if code
        end
        name = DEFAULT_KEYS[key]
        name && Sf::Keyboard::Scancode.const_get(name)
      end
    end
  end
end
