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
# Each button sends its own keyboard scancode (DEFAULT_KEYS, the ones PSDK's
# former touch controls sent): the game key it drives is the one the game's
# Input::Keys binds that scancode to, so a game rebinds a button by editing
# Input::Keys. When nothing binds it, the button sends the first keyboard
# binding of its virtual key instead. The keyboard button shows / hides the
# system's virtual keyboard. The keyboard also shows by itself when the
# player taps a text entry of the game (TextEntry), and hides once there is
# none left.
#
# Games can tune it (see the module methods): the buttons' size (scale), A / B
# placed as on a Nintendo or an Xbox pad (action_layout), buttons of their own
# in the top corners (add_button, pressed?, triggered?, held_for), the button
# pressed last (consume_pressed_button), the buttons' images (image).
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

      # A / B / X / Y on the action cross: top, right, bottom, left
      # Side of a cross's box, in buttons (PSDK's touch controls in a 480x270 game)
      CROSS_RATIO = 2.5
      ACTION_CROSSES = { nintendo: %w[y a b x], xbox: %w[y b a x] }.freeze

      # @param width [Integer] window width
      # @param height [Integer] window height
      # @param image_size [Integer] side of the (square) button images
      # @param scale [Float] size of the buttons, 1.0 by default
      # @param action_layout [Symbol] :nintendo or :xbox (see ACTION_CROSSES)
      # @param extras [Array<Array(String, Symbol)>] the game's buttons and
      #   their corner (:top_left, :top_right), in order from the corner
      def initialize(width, height, image_size, scale: 1.0, action_layout: :nintendo, extras: [])
        unit = [width, height].min / DESIGN_HEIGHT
        # Integer zoom keeps the pixel art sharp; the box of a cross follows the
        # rounded button size, so the gaps between its buttons scale with them
        @zoom = [([width, height].min * 0.3 * scale / (CROSS_RATIO * image_size)).round, 1].max
        size = image_size * @zoom
        box = (size * CROSS_RATIO).round
        padding = (20 * unit).round

        box_y = ((height - box) * 0.9).round
        dpad_x = padding
        action_x = (width - box - padding).round
        row_y = box_y - size
        @crosses = [cross(dpad_x, box_y, box, size, %w[up right down left]),
                    cross(action_x, box_y, box, size, ACTION_CROSSES.fetch(action_layout))]
        gap = (8 * unit).round
        @row = [Button.new('l', padding, row_y, size),
                Button.new('r', width - padding - size, row_y, size),
                Button.new('select', padding + size + gap, row_y, size),
                Button.new('start', width - padding - 2 * size - gap, row_y, size),
                Button.new(KEYBOARD, padding, row_y - size - gap, size)]
        @buttons = @crosses.flat_map(&:buttons) + @row
        extras.each { |name, anchor| add_extra(name, anchor, width, padding, gap, size) }
      end

      def button_at(px, py)
        cross = @crosses.find { |c| c.include?(px, py) }
        return cross.buttons.min_by { |button| button.distance2(px, py) } if cross

        @row.find { |button| button.include?(px, py) }
      end

      private

      # A game's button in a top corner, moved towards the middle of the top
      # edge past the buttons it would cover (the keyboard button, when the
      # buttons are large; the corner's previous extra buttons)
      def add_extra(name, anchor, width, padding, gap, size)
        step = anchor == :top_right ? -(size + gap) : size + gap
        x = anchor == :top_right ? width - padding - size : padding
        button = Button.new(name, x, gap, size)
        button.x += step while @buttons.any? { |other| overlap?(button, other) } && button.x.between?(0, width - size)
        @row << button
        @buttons << button
      end

      def overlap?(first, second)
        first.x < second.x + second.size && second.x < first.x + first.size &&
          first.y < second.y + second.size && second.y < first.y + first.size
      end

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

    # Key names in the game's messages: PSDK's "\k[A]" (PFM::Text.get_key_name)
    # names the first keyboard key bound to the game key ("C"), meaningless on
    # a touch screen. While the overlay is on, it names the gamepad button
    # sending that key instead ("A"); the D-pad and the keys no button sends
    # keep the game's name.
    module KeyNames
      # Buttons named in messages
      LABELED = (BUTTON_KEYS.keys - %w[up down left right]).freeze
      @hooked = false

      # get_key_name is a module_function: PFM::Text calls its own copy
      # (parse_string_for_messages), the classes including it (PSDK's battle
      # transitions) theirs
      module Label
        def get_key_name(name)
          KeyNames.label(name) || super
        end
      end

      module_function

      # PFM::Text is defined by the game's scripts, after the overlay is
      # installed: hook it once it exists
      def hook
        return if @hooked || !defined?(::PFM::Text) || !::PFM::Text.respond_to?(:get_key_name)

        ::PFM::Text.prepend(Label)
        ::PFM::Text.singleton_class.prepend(Label)
        @hooked = true
      end

      # @param name [String] the game key in the message ('A', 'start'...)
      # @return [String, nil] label of the gamepad button sending it, nil to
      #   keep the game's name
      def label(name)
        return nil unless TouchOverlay.key_labels? && TouchOverlay.current&.enabled?
        return nil unless defined?(::PFM::Text::GameKeys) && defined?(::Input::Keys)

        key = ::PFM::Text::GameKeys[name.to_s.downcase]
        codes = key.is_a?(Symbol) ? Array(::Input::Keys[key]) : []
        LABELED.find { |button| codes.include?(TouchOverlay.button_scancode(button)) }&.upcase
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
        @pressed = {}   # button name => scancode it sent (true: no key, game button)
        @pressed_at = {} # game button name => monotonic time it was pressed
        @triggered = [] # game buttons pressed at the last update
        @last_pressed = nil # gamepad button pressed last, see consume_pressed_button
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
        # PSDK's soft reset disposes every viewport and bitmap, the overlay's too
        build if @viewports&.any?(&:disposed?)
        relayout if @window.width != @width || @window.height != @height ||
                    @config_version != TouchOverlay.config_version
        @triggered.clear
        held = (@fingers.values.select { |name| name } + @touched).uniq
        @touched.clear
        (@pressed.keys - held).each { |name| release(name) }
        (held - @pressed.keys).each { |name| press(name) }
        update_text_entry
        KeyNames.hook
      end

      def enabled?
        @enabled
      end

      # State of a game's button (TouchOverlay.add_button)
      def pressed?(name)
        @pressed.key?(name)
      end

      def triggered?(name)
        @triggered.include?(name)
      end

      # @return [Float, nil] seconds since the button was pressed, nil when it is not
      def held_for(name)
        start = @pressed_at[name]
        start && Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      end

      # Gamepad button pressed last ('a', 'up'...), forgotten once read
      def consume_pressed_button
        name = @last_pressed
        @last_pressed = nil
        name
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
        @config_version = TouchOverlay.config_version
        extras = TouchOverlay.extra_buttons
        @extra_bitmaps = extras.transform_values do |button|
          image = button[:image]
          image.is_a?(String) ? LiteRGSS::Bitmap.new(image, true) : image.call
        end
        @layout = Layout.new(@width, @height, @bitmaps.values.first.width,
                             scale: TouchOverlay.scale, action_layout: TouchOverlay.action_layout,
                             extras: extras.map { |name, button| [name, button[:anchor]] })
        return unless @enabled

        @sprites = {}
        @viewports = @layout.buttons.map do |button|
          viewport = LiteRGSS::Viewport.new(@window, button.x, button.y, button.size, button.size)
          viewport.z = Z
          sprite = LiteRGSS::Sprite.new(viewport)
          bitmap = @bitmaps[button.name] || @extra_bitmaps[button.name]
          sprite.bitmap = bitmap
          # A game's image may have another size than the gamepad's
          sprite.zoom = @bitmaps.key?(button.name) ? @layout.zoom : button.size.to_f / bitmap.width
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

      # Show the keyboard for a tap on a text entry, or when the name input
      # scene starts (PSDK versions before its Android support never open it),
      # hide it with the entry. A tap shows it even when it is thought shown:
      # the system may have hidden it (back gesture, the keyboard's own close
      # key), which the overlay is not told; showing a shown keyboard does
      # nothing.
      def update_text_entry
        TextEntry.hook
        tap = @game_tap
        @game_tap = nil
        name_input = TextEntry.scene?
        name_input_started = name_input && !@name_input
        @name_input = name_input
        if (tap && TextEntry.at?(*tap)) || name_input_started
          show_keyboard(true, automatic: !@keyboard_shown || @keyboard_automatic)
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
        return press_game_button(name) unless BUTTON_KEYS.key?(name)

        @last_pressed = name
        scancode = TouchOverlay.button_scancode(name)
        # Released with the same scancode, whatever the game rebinds meanwhile
        @pressed[name] = scancode if scancode
        forward(:key_pressed, UNKNOWN_KEY, scancode, false, false, false, false) if scancode
      end

      def release(name)
        scancode = @pressed.delete(name)
        @pressed_at.delete(name)
        return if name == KEYBOARD

        @sprites&.[](name)&.opacity = OPACITY
        forward(:key_released, UNKNOWN_KEY, scancode) if scancode.is_a?(Integer)
      end

      # A game's button sends no key: the game reads its state
      def press_game_button(name)
        @pressed_at[name] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @triggered << name
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
        TouchOverlay.current = nil if TouchOverlay.current.equal?(@__touch_overlay)
        @__touch_overlay = nil
        super
      end

      # Attach the overlay; called right after the window is created.
      def __attach_touch_overlay
        overlay = Overlay.new(self)
        @__touch_overlay = overlay
        TouchOverlay.current = overlay
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
    @key_labels = true
    @scale = 1.0
    @action_layout = :nintendo
    @extra_buttons = {}
    # Bumped by every setting change: overlays relayout when they see it change
    @config_version = 0

    class << self
      # Overlay of the window created last (a game has one window)
      attr_accessor :current
      attr_reader :config_version, :scale, :action_layout

      # Size of the buttons: 1.0 by default, 1.5 half as large again...
      def scale=(value)
        @scale = Float(value)
        @config_version += 1
      end

      # Place of A and B on the action cross: :nintendo (A right, B bottom)
      # or :xbox (A bottom, B right). The buttons send the same keys.
      def action_layout=(value)
        Layout::ACTION_CROSSES.fetch(value)
        @action_layout = value
        @config_version += 1
      end

      # A button of the game in a top corner, drawn and hit-tested like the
      # gamepad's but sending no key: the game reads pressed?, triggered? and
      # held_for. Kept across window resizes and soft resets.
      # @param name [String] its name
      # @param image [String, #call] PNG data, or a callable returning a bitmap
      #   (-> { RPG::Cache.interface('touch/reset') }), called again on each
      #   rebuild: a soft reset disposes the bitmaps
      # @param anchor [Symbol] :top_left or :top_right
      def add_button(name, image, anchor: :top_left)
        raise ArgumentError, "#{name} is a gamepad button" if IMAGES.key?(name)
        raise ArgumentError, "unknown anchor #{anchor}" unless %i[top_left top_right].include?(anchor)

        @extra_buttons[name] = { image: image, anchor: anchor }
        @config_version += 1
      end

      def remove_button(name)
        @config_version += 1 if @extra_buttons.delete(name)
      end

      # @return [Hash{String => Hash}] the game's buttons (add_button)
      def extra_buttons
        @extra_buttons.dup
      end

      # Is a button (the game's, or the gamepad's: 'a', 'up'...) held down?
      def pressed?(name)
        @current ? @current.pressed?(name) : false
      end

      # Was a game's button pressed at the last frame?
      def triggered?(name)
        @current ? @current.triggered?(name) : false
      end

      # @return [Float, nil] seconds a game's button has been held, nil when it is not
      def held_for(name)
        @current&.held_for(name)
      end

      # Gamepad button pressed last ('a', 'up'...), nil if none since the
      # last call: lets a key binding menu take a touch button as the new key
      def consume_pressed_button
        @current&.consume_pressed_button
      end

      # @param name [String] a gamepad button ('a', 'up'...)
      # @return [String, nil] its PNG image (to show it in a menu)
      def image(name)
        IMAGES[name]
      end
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

      # false keeps the game's key names in its messages (KeyNames)
      attr_writer :key_labels

      def key_labels?
        @key_labels
      end

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
      # "InputTouch Viewport", still in games exported before the overlay).
      # Only the real ones count: a game script reopening the class (built on
      # them before) defines an empty Input::InputTouch.
      def game_has_touch_controls?
        defined?(::Input::InputTouch) && ::Input::InputTouch.respond_to?(:singleton) ? true : false
      end

      # Keyboard scancode a gamepad button sends: its own (DEFAULT_KEYS) when
      # the game's Input::Keys binds it to a key, so that the game rebinds the
      # button there; otherwise the first keyboard binding of its virtual key.
      # @param name [String] 'a', 'up'...
      # @return [Integer, nil]
      def button_scancode(name)
        own = own_scancode(name)
        return nil unless own
        return own if bound?(own)

        scancode(BUTTON_KEYS[name])
      end

      # Keyboard scancode of a gamepad button itself (DEFAULT_KEYS): the one a
      # key binding menu moves in Input::Keys to rebind the button
      # @param name [String] 'a', 'up'...
      # @return [Integer, nil]
      def own_scancode(name)
        key = BUTTON_KEYS[name]
        key && Sf::Keyboard::Scancode.const_get(DEFAULT_KEYS[key])
      end

      # @return [Hash{String => Integer}] scancode each gamepad button sends now
      def button_scancodes
        BUTTON_KEYS.keys.to_h { |name| [name, button_scancode(name)] }
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

      private

      # Does the game's Input::Keys bind this scancode to a key?
      def bound?(code)
        return false unless defined?(::Input::Keys) && ::Input::Keys.respond_to?(:each_value)

        ::Input::Keys.each_value.any? { |codes| Array(codes).include?(code) }
      end
    end
  end
end
