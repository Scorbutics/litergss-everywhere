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
# binding of its virtual key instead. The tools button opens a menu: show /
# hide the system's virtual keyboard, edit the layout (Editor, saved as the
# player's layout file, see on_layout_saved). The keyboard also shows by
# itself when the player taps a text entry of the game (TextEntry), and hides
# once there is none left.
#
# Games can tune it (see the module methods): the buttons' size (scale), A / B
# placed as on a Nintendo or an Xbox pad (action_layout), buttons of their own
# in the top corners (add_button, pressed?, triggered?, held_for), the button
# pressed last (consume_pressed_button), the buttons' images (image). A layout
# file (load_layout, see LayoutFile) moves, resizes and hides buttons, and adds
# buttons sending a key of its choice.
#
# A game drawing its own touch controls (Input::InputTouch, as pokemonsdk did
# for Android) keeps them: the overlay never shows on its windows.
#
# Layout and images come from PSDK's former "InputTouch Viewport" (pokemonsdk),
# in window pixels instead of game pixels.
#
# The runtime ships this directory with the Ruby standard library
# (cmake/litergss-app/ruby-client.cmake): the images are read next to this file.
require 'json'

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

    # Button opening the tools menu (not a key). The overlay's names besides
    # the gamepad's (and keyboard) start with overlay_: a game's buttons may
    # be named anything else.
    TOOLS = 'overlay_tools'
    # The tools menu: show / hide the virtual keyboard, edit the layout (Editor)
    KEYBOARD = 'keyboard'
    EDIT = 'overlay_edit'
    TOOLS_MENU = [KEYBOARD, EDIT].freeze
    # The editor's: save, back to the game's layout, resize / spread handle
    DONE = 'overlay_done'
    RESET = 'overlay_reset'
    HANDLE = 'overlay_handle'

    IMAGES = (BUTTON_KEYS.keys + [TOOLS] + TOOLS_MENU + [DONE, RESET, HANDLE]).to_h do |name|
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

    # A layout file: where the groups and buttons it names go, and the buttons
    # it adds. What it doesn't name keeps its computed place, so a file holds
    # only what differs from the default layout.
    #
    #   {
    #     "version": 1,
    #     "action_layout": "nintendo",
    #     "groups": {
    #       "dpad": { "anchor": "bottom_left", "x": 0.04, "y": 0.1, "size": 1.2, "gap": 0.8 }
    #     },
    #     "buttons": {
    #       "select": { "visible": false },
    #       "start":  { "anchor": "bottom_right", "x": 0.2, "y": 0.45 },
    #       "run":    { "anchor": "top_right", "x": 0.02, "y": 0.03,
    #                   "key": "LShift", "image": "touch/run.png" }
    #     }
    #   }
    #
    # - groups: "dpad" and "action", the crosses (their buttons move with them);
    #   buttons: "l", "r", "select", "start", "overlay_tools", the game's
    #   (add_button), and the file's own: a "key" (a Sf::Keyboard::Scancode
    #   name) and an "image" (a PNG, read by the loader's read_image)
    # - anchor: the window corner x / y count from, to the same corner of the
    #   group or button; x / y: fractions of the window width / height. All
    #   three or none: without, the group or button keeps its centre (the
    #   file's own buttons need them)
    # - size: of the buttons, 1.0 being the default one (scale included);
    #   gap: of a cross's buttons apart, 1.0 being the default. The gamepad's
    #   images keep an integer zoom: their size snaps to it
    # - visible: false hides a group or button (hiding overlay_tools also
    #   removes the keyboard toggle and the editor)
    # - action_layout: wins over TouchOverlay.action_layout
    class LayoutFile
      VERSION = 1
      ANCHORS = %w[top_left top_right bottom_left bottom_right].freeze
      GROUPS = %w[dpad action].freeze
      PLACEABLE = %w[l r select start].push(TOOLS).freeze
      SIZES = (0.25..4.0).freeze
      GAPS = (0.5..3.0).freeze
      PNG_SIGNATURE = "\x89PNG".b.freeze

      Placement = Struct.new(:anchor, :x, :y, :size, :gap, :visible)
      Custom = Struct.new(:scancode, :image)

      # @return [Symbol, nil] :nintendo / :xbox
      attr_reader :action_layout
      # @return [Hash{String => Placement}]
      attr_reader :groups, :buttons
      # @return [Hash{String => Custom}] the buttons the file adds
      attr_reader :customs
      # @return [Hash] the parsed file
      attr_reader :data

      # @return [String, nil] the data of an image the file read
      def image_data(path)
        @images&.[](path)
      end

      # @param json [String]
      # @param read_image [#call] image path of the file => PNG data
      # @raise [ArgumentError] the file is invalid
      def initialize(json, read_image)
        @data = data = JSON.parse(json)
        raise ArgumentError, 'not a JSON object' unless data.is_a?(Hash)
        raise ArgumentError, "version #{data['version'].inspect}, #{VERSION} expected" unless data['version'] == VERSION

        @action_layout = parse_action_layout(data['action_layout'])
        @groups = entries(data, 'groups').to_h do |name, entry|
          raise ArgumentError, "unknown group #{name}" unless GROUPS.include?(name)

          [name, placement(name, entry)]
        end
        @customs = {}
        @buttons = entries(data, 'buttons').to_h do |name, entry|
          raise ArgumentError, "#{name} is a group" if GROUPS.include?(name)

          if IMAGES.key?(name)
            raise ArgumentError, "#{name} can't be placed (a cross's moves with it)" unless PLACEABLE.include?(name)
            raise ArgumentError, "#{name} has its own key and image" if entry.key?('key') || entry.key?('image')
          end
          placement = placement(name, entry)
          # A hidden one needs no image: its entry still hides a game button
          if entry.key?('key') && !IMAGES.key?(name) && placement.visible
            raise ArgumentError, "#{name}: anchor, x and y are needed" unless placement.anchor

            @customs[name] = custom(name, entry, read_image)
          end
          [name, placement]
        end
      end

      # This file with another on top (the player's on the game's)
      # @param over [LayoutFile]
      # @return [LayoutFile]
      def merge(over)
        dup.tap { |merged| merged.absorb!(over) }
      end

      protected

      # The other's entries on this file's, field by field: moving a button
      # keeps the size this file gives it. Only a key replaces a button this
      # file adds, only visible: false hides it.
      def absorb!(over)
        @action_layout = over.action_layout || @action_layout
        @groups = @groups.merge(merged_placements('groups', over))
        @buttons = @buttons.merge(merged_placements('buttons', over))
        @customs = @customs.dup
        over.buttons.each do |name, placement|
          if over.customs.key?(name)
            @customs[name] = over.customs[name]
          elsif !placement.visible
            @customs.delete(name)
          end
        end
      end

      private

      def merged_placements(section, over)
        own = entries(@data, section)
        entries(over.data, section).to_h { |name, entry| [name, placement(name, own.fetch(name, {}).merge(entry))] }
      end

      def parse_action_layout(value)
        return nil if value.nil?
        raise ArgumentError, "action_layout #{value.inspect}" unless value.is_a?(String) && Layout::ACTION_CROSSES.key?(value.to_sym)

        value.to_sym
      end

      def entries(data, key)
        entries = data.fetch(key, {})
        raise ArgumentError, "#{key} is not an object" unless entries.is_a?(Hash)
        raise ArgumentError, "an entry of #{key} is not an object" unless entries.each_value.all?(Hash)

        entries
      end

      def placement(name, entry)
        visible = entry.fetch('visible', true)
        raise ArgumentError, "#{name}: visible true or false expected" unless [true, false].include?(visible)

        size = number(name, entry, 'size', SIZES)
        gap = number(name, entry, 'gap', GAPS)
        anchor, x, y = entry.values_at('anchor', 'x', 'y')
        return Placement.new(nil, nil, nil, size, gap, visible) if [anchor, x, y].all?(&:nil?)
        raise ArgumentError, "#{name}: anchor #{anchor.inspect}" unless ANCHORS.include?(anchor)
        raise ArgumentError, "#{name}: x / y between 0 and 1 expected" unless [x, y].all? { |v| v.is_a?(Numeric) && v.between?(0, 1) }

        Placement.new(anchor.to_sym, x.to_f, y.to_f, size, gap, visible)
      end

      def number(name, entry, key, range)
        value = entry.fetch(key, 1.0)
        raise ArgumentError, "#{name}: #{key} in #{range} expected" unless value.is_a?(Numeric) && range.cover?(value)

        value.to_f
      end

      def custom(name, entry, read_image)
        key = entry['key']
        scancode = Sf::Keyboard::Scancode.const_get(key, false) if key.is_a?(String) && key.match?(/\A[A-Z]\w*\z/) &&
                                                                    Sf::Keyboard::Scancode.const_defined?(key, false)
        raise ArgumentError, "#{name}: unknown key #{key.inspect}" unless scancode.is_a?(Integer) && scancode >= 0
        raise ArgumentError, "#{name}: an image is needed" unless entry['image'].is_a?(String)

        Custom.new(scancode, image(name, entry['image'], read_image))
      end

      # Each image read once: buttons sharing one share its bitmap
      def image(name, path, read_image)
        @images ||= {}
        @images[path] ||= begin
          data = read_image.call(path)
          raise ArgumentError, "#{name}: #{path} is not a PNG" unless data.is_a?(String) && data.b.start_with?(PNG_SIGNATURE)

          data.b.freeze
        end
      end
    end

    # Position and size of every button, in window pixels.
    #
    # The D-pad and the A/B/X/Y buttons are crosses of four buttons in a square
    # box: their images overlap at the corners, so a touch in a box goes to the
    # nearest button of the cross, like on a physical pad.
    class Layout
      # A square of side size at x, y
      module Square
        def include?(px, py)
          px >= x && py >= y && px < x + size && py < y + size
        end
      end

      Button = Struct.new(:name, :x, :y, :size) do
        include Square

        def distance2(px, py)
          (x + size / 2.0 - px)**2 + (y + size / 2.0 - py)**2
        end
      end

      Cross = Struct.new(:x, :y, :size, :buttons, :name) do
        include Square
      end

      attr_reader :buttons, :crosses, :width, :height
      # @return [Integer] side of a button by default (scale included)
      attr_reader :unit

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
      # @param file [LayoutFile, nil] moves, resizes, hides what it names
      # @param customs [Hash{String => Integer}] the buttons of the file to add
      #   and the scancode they send
      def initialize(width, height, image_size, scale: 1.0, action_layout: :nintendo, extras: [], file: nil, customs: {})
        @width = width
        @height = height
        @image_size = image_size
        @customs = customs
        unit = [width, height].min / DESIGN_HEIGHT
        # Integer zoom keeps the pixel art sharp; the box of a cross follows the
        # rounded button size, so the gaps between its buttons scale with them
        zoom = [([width, height].min * 0.3 * scale / (CROSS_RATIO * image_size)).round, 1].max
        size = image_size * zoom
        @unit = size
        box = (size * CROSS_RATIO).round
        padding = (20 * unit).round

        box_y = ((height - box) * 0.9).round
        dpad_x = padding
        action_x = (width - box - padding).round
        row_y = box_y - size
        @crosses = [cross(dpad_x, box_y, box, size, %w[up right down left], 'dpad'),
                    cross(action_x, box_y, box, size, ACTION_CROSSES.fetch(file&.action_layout || action_layout), 'action')]
        gap = (8 * unit).round
        @row = [Button.new('l', padding, row_y, size),
                Button.new('r', width - padding - size, row_y, size),
                Button.new('select', padding + size + gap, row_y, size),
                Button.new('start', width - padding - 2 * size - gap, row_y, size),
                Button.new(TOOLS, padding, row_y - size - gap, size)]
        @buttons = @crosses.flat_map(&:buttons) + @row
        extras.each { |name, anchor| add_extra(name, anchor, width, padding, gap, size) }
        apply(file, size) if file
      end

      # @return [Integer, nil] scancode a button of the layout file sends
      def scancode(name)
        @customs[name]
      end

      # The button drawn on top at this point (the last drawn: crosses first)
      def button_at(px, py)
        element = element_at(px, py)
        element.is_a?(Cross) ? element.buttons.min_by { |b| b.distance2(px, py) } : element
      end

      # The cross or row button drawn on top at this point
      # @return [Cross, Button, nil]
      def element_at(px, py)
        @row.reverse_each.find { |b| b.include?(px, py) } || @crosses.reverse_each.find { |c| c.include?(px, py) }
      end

      # @param name [String] a group ('dpad', 'action') or a row button
      # @return [Cross, Button, nil]
      def element(name)
        @crosses.find { |c| c.name == name } || @row.find { |b| b.name == name }
      end

      # Side of a button of this name at this size: the gamepad's images keep
      # an integer zoom (sharp pixel art)
      def snap(name, side)
        return side.round unless IMAGES.key?(name)

        [(side / @image_size).round, 1].max * @image_size
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

      # The layout file on the default layout: what it doesn't name stays put
      def apply(file, size)
        @crosses = @crosses.filter_map { |c| placed_cross(c, file.groups[c.name]) }
        @row = @row.filter_map { |button| placed(button, file.buttons[button.name]) }
        @customs.each_key do |name|
          button = placed(Button.new(name, 0, 0, size), file.buttons[name])
          @row << button if button
        end
        @buttons = @crosses.flat_map(&:buttons) + @row
      end

      # The button as the file places it, nil when it hides it
      def placed(button, placement)
        return button unless placement
        return nil unless placement.visible

        side = snap(button.name, button.size * placement.size)
        x, y = position(placement, button, side)
        Button.new(button.name, x, y, side)
      end

      # The cross as the file places it, nil when it hides it
      def placed_cross(cross, placement)
        return cross unless placement
        return nil unless placement.visible

        size = snap(cross.buttons.first.name, cross.buttons.first.size * placement.size)
        box = (size + (CROSS_RATIO - 1) * size * placement.gap).round
        cross(*position(placement, cross, box), box, size, cross.buttons.map(&:name), cross.name)
      end

      # Window position of a square of this side, kept inside the window:
      # from the file's anchor, or the element's centre when it gives none
      def position(placement, element, side)
        if placement.anchor
          x = (placement.x * @width).round
          y = (placement.y * @height).round
          x = @width - x - side if %i[top_right bottom_right].include?(placement.anchor)
          y = @height - y - side if %i[bottom_left bottom_right].include?(placement.anchor)
        else
          x = element.x + (element.size - side) / 2
          y = element.y + (element.size - side) / 2
          # Where the default layout put it while its size is unchanged (a
          # game button the default pushed out stays out); resized, inside
          return [x, y] if side == element.size
        end
        [x.clamp(0, [@width - side, 0].max), y.clamp(0, [@height - side, 0].max)]
      end

      def overlap?(first, second)
        first.x < second.x + second.size && second.x < first.x + first.size &&
          first.y < second.y + second.size && second.y < first.y + first.size
      end

      # Four buttons on the edges of a square box: top, right, bottom, left
      def cross(box_x, box_y, box, size, names, name)
        middle = ((box - size) / 2).round
        far = (box - size).round
        side = far + size
        top, right, bottom, left = names
        Cross.new(box_x, box_y, side, [Button.new(top, box_x + middle, box_y, size),
                                       Button.new(right, box_x + far, box_y + middle, size),
                                       Button.new(bottom, box_x + middle, box_y + far, size),
                                       Button.new(left, box_x, box_y + middle, size)], name)
      end
    end

    # The layout editor (the tools menu's edit button): drag a cross or a
    # button to move it, the handle at its corner to resize it, a cross's
    # second handle to spread its buttons. Done keeps the player's layout file
    # (TouchOverlay.save_player_layout), Reset puts back every place the
    # game's layout gives. It edits the player's file only, writing just what
    # the player changes (the game's file gives the rest): its other entries
    # (the buttons it adds, hides) stay. While open it takes every touch: the
    # game gets none, and no key is sent (see Overlay).
    class Editor
      # A handle: :size (a corner) or :gap (a cross's right edge)
      Handle = Struct.new(:name, :x, :y, :size, :kind) do
        include Layout::Square
      end
      Drag = Struct.new(:finger, :kind, :start_x, :start_y, :element, :gap)
      PLACE_KEYS = %w[anchor x y size gap].freeze

      # @return [String, nil] name of the group or button being edited
      attr_reader :selected

      # @param layers [Hash] TouchOverlay.layout_layers
      # @raise [StandardError] the player's file can't be edited
      def initialize(layers)
        @game = layers[:game]
        player = layers[:player]
        @data = player ? JSON.parse(JSON.generate(player.data)) : { 'version' => LayoutFile::VERSION }
        read_image = layers[:read_image]
        # Each change parses the player's file again: its images are read once
        @read_image = ->(path) { player&.image_data(path) || read_image.call(path) }
        @file = compose
      end

      # @return [LayoutFile, nil] the game's layout file, the edited player's on
      #   top; composed once per change, the last valid one kept
      def file
        if @stale
          @stale = false
          begin
            @file = compose
          rescue StandardError => e
            warn "[TouchOverlay] layout edit not applied: #{e.class}: #{e.message}"
          end
        end
        @file
      end

      # Done and Reset, at the top of the window
      def toolbar(layout)
        size = layout.unit
        gap = size / 4
        [Layout::Button.new(DONE, layout.width / 2 - size - gap / 2, gap, size),
         Layout::Button.new(RESET, layout.width / 2 + gap / 2, gap, size)]
      end

      # Inside the window, wherever the element is
      def handles(layout)
        element = @selected && layout.element(@selected)
        return [] unless element

        size = [layout.unit / 2, 1].max
        inside = lambda do |kind, x, y|
          Handle.new(HANDLE, x.clamp(0, [layout.width - size, 0].max), y.clamp(0, [layout.height - size, 0].max), size, kind)
        end
        right = element.x + element.size - size / 2
        handles = [inside.call(:size, right, element.y + element.size - size / 2)]
        handles << inside.call(:gap, right, element.y + (element.size - size) / 2) if element.is_a?(Layout::Cross)
        handles
      end

      # Is this button drawn lit: the edited element, or one of its cross's
      def lit?(name, layout)
        element = @selected && layout.element(@selected)
        element.is_a?(Layout::Cross) ? element.buttons.any? { |b| b.name == name } : @selected == name
      end

      # A new touch takes over: a drag whose end was lost must not lock the editor
      # @return [Symbol] :done once closed, :changed when to draw again
      def touch_began(finger, x, y, layout)
        @drag = nil
        button = toolbar(layout).find { |b| b.include?(x, y) }
        return button.name == DONE ? done : reset if button

        handle = handles(layout).find { |h| h.include?(x, y) }
        element = handle ? layout.element(@selected) : layout.element_at(x, y)
        @selected = element&.name
        @drag = Drag.new(finger, handle ? handle.kind : :move, x, y, element.dup, gap(element)) if element
        :changed
      end

      # @return [Symbol, nil] :changed when to draw again
      def touch_moved(finger, x, y, layout)
        drag = @drag
        return unless drag&.finger == finger

        element = drag.element
        case drag.kind
        when :move
          place(element, layout, element.x + x - drag.start_x, element.y + y - drag.start_y, element.size)
        when :size then resize(element, layout, [x - element.x, y - element.y].max, drag.gap)
        when :gap then spread(element, layout, x - element.x)
        end
        @stale = true
        :changed
      end

      def touch_ended(finger)
        @drag = nil if @drag&.finger == finger
      end

      private

      # The corner handle at this distance from the element's top left corner:
      # the size it gets once clamped and snapped, the top left corner kept
      def resize(element, layout, side, gap)
        cross = element.is_a?(Layout::Cross)
        spread = cross ? 1 + (Layout::CROSS_RATIO - 1) * gap : 1
        size = ((cross ? side / spread : side).to_f / layout.unit).clamp(LayoutFile::SIZES.min, LayoutFile::SIZES.max)
        button = layout.snap(cross ? element.buttons.first.name : element.name, layout.unit * size)
        side = cross ? (button * spread).round : button
        place(element, layout, element.x, element.y, side, size: button.to_f / layout.unit)
      end

      # The gap handle at this distance from the cross's left edge
      def spread(element, layout, box)
        button = element.buttons.first.size
        gap = ((box - button).to_f / ((Layout::CROSS_RATIO - 1) * button)).clamp(LayoutFile::GAPS.min, LayoutFile::GAPS.max)
        place(element, layout, element.x, element.y, (button + (Layout::CROSS_RATIO - 1) * button * gap).round, gap: gap)
      end

      # The gap of a cross as the edited layout has it
      def gap(element)
        return 1.0 unless element.is_a?(Layout::Cross)

        file&.groups&.[](element.name)&.gap || 1.0
      end

      # Write the element's place: anchored at the window corner nearest to
      # its centre, kept inside the window
      def place(element, layout, x, y, side, size: nil, gap: nil)
        width = layout.width
        height = layout.height
        x = x.clamp(0, [width - side, 0].max)
        y = y.clamp(0, [height - side, 0].max)
        left = x + side / 2.0 < width / 2.0
        top = y + side / 2.0 < height / 2.0
        group = element.is_a?(Layout::Cross)
        entry = (@data[group ? 'groups' : 'buttons'] ||= {})[element.name] ||= {}
        entry['anchor'] = "#{top ? 'top' : 'bottom'}_#{left ? 'left' : 'right'}"
        entry['x'] = ((left ? x : width - x - side).to_f / width).clamp(0.0, 1.0).round(4)
        entry['y'] = ((top ? y : height - y - side).to_f / height).clamp(0.0, 1.0).round(4)
        entry['size'] = size.round(3) if size
        entry['gap'] = gap.round(3) if gap
      end

      # The buttons the player's file adds keep their place: they have no other
      def reset
        %w[groups buttons].each do |section|
          entries = @data[section] or next
          entries.each_value { |entry| PLACE_KEYS.each { |key| entry.delete(key) } unless entry.key?('key') }
          entries.reject! { |_, entry| entry.empty? }
        end
        @selected = nil
        @stale = true
        :changed
      end

      def done
        TouchOverlay.save_player_layout(@data)
        :done
      end

      def compose
        player = LayoutFile.new(JSON.generate(@data), @read_image)
        @game ? @game.merge(player) : player
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

    # The virtual keyboard's Shift reaches the game as a real LShift / RShift
    # key, which a game may bind to an action (PSDK: B and Y): typing a capital
    # letter in the name input cancelled it. While a text entry is on screen,
    # Shift presses don't reach the game's key callback; the typed text still
    # comes through on_text_entered. Releases always do, not to leave a key held.
    module TypingKeys
      SHIFT_KEYS = %i[LShift RShift].freeze

      module_function

      # @param overlay [Overlay]
      # @param game_proc [Proc, nil] the game's on_key_pressed callback
      # @return [Proc, nil] the callback the window calls
      def filter(overlay, game_proc)
        return game_proc unless game_proc

        shift = SHIFT_KEYS.filter_map do |name|
          Sf::Keyboard::Scancode.const_get(name) if Sf::Keyboard::Scancode.const_defined?(name)
        end
        proc do |*args|
          next if shift.include?(args[1]) && typing?(overlay)

          game_proc.call(*args)
        end
      end

      # A text entry is on screen (an error there must never cost the game a key)
      def typing?(overlay)
        overlay.enabled? && TextEntry.any?
      rescue StandardError
        false
      end
    end

    # The overlay of one window: its sprites, the fingers on its buttons and
    # the keys they hold down.
    class Overlay
      # A finger the tools menu or the editor took: no button, no game
      CAPTURED = :captured

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
      # A finger that began elsewhere belongs to the game (nil). While the
      # tools menu or the editor is open, every finger is theirs (CAPTURED).
      def touch_began(finger, x, y)
        position = to_window(x, y)
        close_stale_editor
        if @editor
          @fingers[finger] = CAPTURED
          return editor_result(@editor.touch_began(finger, *position, @layout))
        end
        return menu_touched(finger, position) if @menu_open

        button = @enabled && @layout.button_at(*position)
        @fingers[finger] = button ? button.name : nil
        @touched << button.name if button
        return if button

        # Checked in update, once the game took the touch into account
        @game_tap = position
        forward(:touch_began, finger, x, y)
      end

      def touch_moved(finger, x, y)
        if @fingers[finger] == CAPTURED
          close_stale_editor
          editor_result(@editor&.touch_moved(finger, *to_window(x, y), @layout))
        elsif owned?(finger)
          # Sliding a finger moves it to the button under it (D-pad direction
          # changes), but only a tap opens the tools menu
          button = @layout.button_at(*to_window(x, y))
          button = nil if button&.name == TOOLS
          @fingers[finger] = button ? button.name : false
          @touched << button.name if button
        else
          forward(:touch_moved, finger, x, y)
        end
      end

      def touch_ended(finger, x, y)
        @editor&.touch_ended(finger)
        owned = owned?(finger)
        @fingers.delete(finger)
        forward(:touch_ended, finger, x, y) unless owned
      end

      # Send the key events of the buttons pressed or released since the last
      # frame; called after the window polled its events.
      def update
        close_stale_editor
        # PSDK's soft reset disposes every viewport and bitmap, the overlay's too
        build if @bitmaps.each_value.first.disposed? || @viewports&.any?(&:disposed?)
        relayout if @window.width != @width || @window.height != @height ||
                    @config_version != TouchOverlay.config_version
        @triggered.clear
        held = (@fingers.values.grep(String) + @touched).uniq
        @touched.clear
        (@pressed.keys - held).each { |name| release(name) }
        (held - @pressed.keys).each { |name| press(name) }
        update_text_entry
        KeyNames.hook
        lay_out if @dirty
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
        @editor = nil
        @menu_open = false
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
        @layout_version = TouchOverlay.layout_version
        file = layout_file
        extras = TouchOverlay.extra_buttons
        customs = file ? file.customs : {}
        game, own = button_bitmaps(extras.transform_values { |button| button[:image] }, customs.transform_values(&:image))
        # The file's button of a name replaces the game's, once its image works
        @extra_bitmaps = game.merge(own)
        @extras = extras.select { |name, _| game.key?(name) && !own.key?(name) }.map { |name, button| [name, button[:anchor]] }
        @customs = own.keys.to_h { |name| [name, customs[name].scancode] }
        lay_out
      end

      # The layout and its sprites, the images loaded (relayout)
      def lay_out
        @dirty = false
        dispose
        @layout = Layout.new(@width, @height, @bitmaps.values.first.width,
                             scale: TouchOverlay.scale, action_layout: TouchOverlay.action_layout,
                             extras: @extras, file: layout_file, customs: @customs)
        return unless @enabled

        @sprites = {}
        @viewports = []
        @layout.buttons.each { |button| draw(button, lit?(button.name)) }
        menu_buttons.each { |button| draw(button, button.name == KEYBOARD && @keyboard_shown) } if @menu_open
        if @editor
          @editor.toolbar(@layout).each { |button| draw(button, false) }
          @editor.handles(@layout).each { |handle| draw(handle, true) }
        end
        @window.sort_z
      end

      def draw(button, lit)
        viewport = LiteRGSS::Viewport.new(@window, button.x, button.y, button.size, button.size)
        viewport.z = Z
        sprite = LiteRGSS::Sprite.new(viewport)
        bitmap = @bitmaps[button.name] || @extra_bitmaps[button.name]
        sprite.bitmap = bitmap
        # A game's image may have another size than the gamepad's
        sprite.zoom = button.size.to_f / bitmap.width
        sprite.opacity = lit ? PRESSED_OPACITY : OPACITY
        @sprites[button.name] = sprite
        @viewports << viewport
      end

      def lit?(name)
        return @editor.lit?(name, @layout) if @editor
        return @keyboard_shown || @menu_open if name == TOOLS

        @pressed.key?(name)
      end

      # The editor's layout while it is open (not saved yet)
      def layout_file
        @editor ? @editor.file : TouchOverlay.layout_file
      end

      # The tools menu, beside the tools button towards the window's middle
      def menu_buttons
        tools = @layout.element(TOOLS)
        return [] unless tools

        step = (tools.x + tools.size / 2 < @width / 2 ? 1 : -1) * (tools.size + tools.size / 8)
        TOOLS_MENU.each_with_index.map { |name, i| Layout::Button.new(name, tools.x + step * (i + 1), tools.y, tools.size) }
      end

      # A touch while the menu is open: on an entry it does it, anywhere it
      # closes the menu, and never reaches the game
      def menu_touched(finger, position)
        @fingers[finger] = CAPTURED
        entry = menu_buttons.find { |button| button.include?(*position) }
        @menu_open = false
        @dirty = true
        case entry&.name
        when KEYBOARD then toggle_keyboard
        when EDIT then open_editor
        end
      end

      # The keys held are released: the editor sends none
      def open_editor
        editor = Editor.new(TouchOverlay.layout_layers)
        @pressed.keys.each { |name| release(name) }
        @touched.clear
        @fingers.transform_values! { |name| name.nil? ? nil : CAPTURED }
        @editor = editor
        relayout
      rescue StandardError => e
        warn "[TouchOverlay] no layout editor: #{e.class}: #{e.message}"
      end

      # A layout file loaded since the editor opened: its edits, saved, would
      # overwrite it. Checked before anything can rebuild the layout (which
      # takes the new version) and before any touch reaches the editor.
      def close_stale_editor
        return unless @editor && @layout_version != TouchOverlay.layout_version

        @editor = nil
        relayout
      end

      def editor_result(result)
        case result
        when :done
          @editor = nil
          relayout
        when :changed
          @dirty = true
        end
      end

      # Bitmaps of the game's and the layout file's buttons, for one layout:
      # those decoded from PNG data are disposed at the next one, a
      # callable's belong to the game. A failing image only drops its button
      # (warned once): it must not take the whole gamepad away.
      # @param sources [Array<Hash{String => String, #call}>] name => image
      # @return [Array<Hash{String => LiteRGSS::Bitmap}>] for each of sources
      def button_bitmaps(*sources)
        @decoded&.each { |bitmap| bitmap.dispose unless bitmap.disposed? }
        decoded = {}.compare_by_identity
        failed = @failed_images || {}.compare_by_identity
        @failed_images = {}.compare_by_identity
        result = sources.map do |images|
          images.each_with_object({}) do |(name, image), bitmaps|
            bitmap = image.is_a?(String) ? decoded[image] ||= LiteRGSS::Bitmap.new(image, true) : image.call
            raise TypeError, "#{bitmap.inspect} is no live bitmap" unless bitmap.is_a?(LiteRGSS::Bitmap) && !bitmap.disposed?

            bitmaps[name] = bitmap
          rescue StandardError => e
            warn "[TouchOverlay] no #{name} button: #{e.class}: #{e.message}" unless failed[image]
            @failed_images[image] = true
          end
        end
        @decoded = decoded.values
        result
      end

      def toggle_keyboard
        show_keyboard(!@keyboard_shown)
      end

      def toggle_menu
        @menu_open = !@menu_open
        @dirty = true
      end

      # The button stays lit while the keyboard is shown. The system can also
      # hide it (back gesture): then the next tap only syncs the state.
      # @param automatic [Boolean] shown for a text entry, hidden with it
      def show_keyboard(shown, automatic: false)
        @keyboard_shown = shown
        @keyboard_automatic = shown && automatic
        Sf::Keyboard.virtual_keyboard = shown if Sf::Keyboard.respond_to?(:virtual_keyboard=)
        @sprites&.[](TOOLS)&.opacity = lit?(TOOLS) ? PRESSED_OPACITY : OPACITY
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
        return toggle_menu if name == TOOLS

        @sprites&.[](name)&.opacity = PRESSED_OPACITY
        if BUTTON_KEYS.key?(name)
          @last_pressed = name
          scancode = TouchOverlay.button_scancode(name)
        else
          scancode = @layout.scancode(name)
          return press_game_button(name) unless scancode
        end
        # Released with the same scancode, whatever the game rebinds meanwhile
        @pressed[name] = scancode if scancode
        forward(:key_pressed, UNKNOWN_KEY, scancode, false, false, false, false) if scancode
      end

      def release(name)
        scancode = @pressed.delete(name)
        @pressed_at.delete(name)
        return if name == TOOLS

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
      def on_key_pressed=(proc)
        @__touch_overlay&.store_game_proc(:key_pressed, proc)
        super(@__touch_overlay ? TypingKeys.filter(@__touch_overlay, proc) : proc)
      end

      def on_key_released=(proc)
        @__touch_overlay&.store_game_proc(:key_released, proc)
        super(proc)
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
    @layout_files = {} # :game / :player => LayoutFile
    @layout_file = nil # the two merged
    @player_read_image = nil
    # Bumped by every setting change: overlays relayout when they see it change
    @config_version = 0
    # Bumped by every layout file change: an open editor's edits are stale
    @layout_version = 0

    class << self
      # Overlay of the window created last (a game has one window)
      attr_accessor :current
      attr_reader :config_version, :layout_version, :scale, :action_layout
      # @return [LayoutFile, nil] the layout files, merged (see load_layout)
      attr_reader :layout_file
      # Called with the player's layout file (JSON) once the editor saved it:
      # the host stores it, to load it again (load_layout player: true) at the
      # next start
      attr_accessor :on_layout_saved

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
        raise ArgumentError, "#{name} is a gamepad button" if IMAGES.key?(name) || LayoutFile::GROUPS.include?(name)
        raise ArgumentError, "unknown anchor #{anchor}" unless %i[top_left top_right].include?(anchor)

        @extra_buttons[name] = { image: image, anchor: anchor }
        warn_replaced([name])
        @config_version += 1
      end

      def remove_button(name)
        @config_version += 1 if @extra_buttons.delete(name)
      end

      # Move, resize, hide buttons and add some, as a layout file says (see
      # LayoutFile). Two of them: the game's, and the player's on top (written
      # by the editor, see on_layout_saved), whose entries win. An invalid file
      # is reported and changes nothing: the overlay must never stop a game.
      # @param json [String] the file's content
      # @param read_image [#call] PNG data of an image path of the file (by
      #   default read from the working directory, not the file's)
      # @param player [Boolean] the player's file, else the game's
      # @return [Boolean] whether the file was taken
      def load_layout(json, read_image: ->(path) { File.binread(path) }, player: false)
        @layout_files[player ? :player : :game] = LayoutFile.new(json, read_image)
        @player_read_image = read_image if player
        game, player = @layout_files.values_at(:game, :player)
        @layout_file = game && player ? game.merge(player) : player || game
        warn_replaced(@extra_buttons.keys)
        @config_version += 1
        @layout_version += 1
        true
      rescue StandardError => e
        warn "[TouchOverlay] layout file ignored: #{e.class}: #{e.message}"
        false
      end

      # Back to the default layout (no layout file)
      def clear_layout
        @config_version += 1 if @layout_file
        @layout_version += 1 if @layout_file
        @layout_files.clear
        @layout_file = nil
        @player_read_image = nil
      end

      # The layout files apart, for the editor: the game's and the player's
      # LayoutFile (nil when none), and how the player's images are read
      # @return [Hash{Symbol => Object}] :game, :player, :read_image
      def layout_layers
        { game: @layout_files[:game], player: @layout_files[:player],
          read_image: @player_read_image || ->(path) { File.binread(path) } }
      end

      # Keep the player's layout file the editor made, and hand it to the host
      # @param data [Hash]
      # @return [Boolean] whether it was taken
      def save_player_layout(data)
        json = JSON.pretty_generate(data)
        return false unless load_layout(json, read_image: layout_layers[:read_image], player: true)

        begin
          @on_layout_saved&.call(json)
        rescue StandardError => e
          warn "[TouchOverlay] layout not handed to the host: #{e.class}: #{e.message}"
        end
        true
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

      def warn_replaced(names)
        (names & (@layout_file&.customs&.keys || [])).each do |name|
          warn "[TouchOverlay] the layout file's #{name} button replaces the game's"
        end
      end

      # Does the game's Input::Keys bind this scancode to a key?
      def bound?(code)
        return false unless defined?(::Input::Keys) && ::Input::Keys.respond_to?(:each_value)

        ::Input::Keys.each_value.any? { |codes| Array(codes).include?(code) }
      end
    end
  end
end
