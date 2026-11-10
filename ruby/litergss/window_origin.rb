# A game smaller than its window (a phone in landscape), centred on the window
# by LiteRGSS instead of by the game's scripts.
#
#   require 'litergss/window_origin'
#   LiteRGSS::WindowOrigin.install            # before the game creates its window
#   window.game_area = [107, 0, 320, 240]     # once it did, by a host knowing the game
#
# LiteRGSS moves the game's viewports, and what the game draws on the window
# itself, by (x, y) window pixels (DisplayWindow#origin=), and keeps their rects
# in the game's coordinates. From the game's side the window then IS the game:
# - width / height are the game's;
# - the mouse and touch positions it gets are moved so the game's (0, 0) is the
#   window's (0, 0), in the screen pixels the window reports them in.
# So a script positioning things with the window's size (Graphics.width), or
# snapshotting the screen into a viewport, sees one space only: nothing of the
# game has to know.
#
# What is drawn over the whole window (the touch overlay, in the black bars)
# reads screen_width / screen_height and uses screen space viewports
# (Viewport#screen_space=), which the origin does not move.
#
# Without the native support (a LiteRGSS without DisplayWindow#origin=),
# install does nothing and game_area= raises: a host checks supported?.
module LiteRGSS
  module WindowOrigin
    TOUCH_EVENTS = %i[touch_began touch_moved touch_ended].freeze

    # Prepended to LiteRGSS::DisplayWindow
    module Window
      # The game's place on the window: [x, y, width, height] in window
      # pixels, nil for a game as large as its window
      def game_area
        @__game_area
      end

      # @param area [Array(Integer, Integer, Integer, Integer), nil]
      def game_area=(area)
        area = area&.map(&:to_i)
        raise ArgumentError, "Expected [x, y, width, height], got #{area.inspect}" if area && area.size != 4

        self.origin = area ? area[0, 2] : [0, 0]
        @__game_area = area
      end

      # The game's width: the window's without a game area
      def width
        @__game_area ? @__game_area[2] : super
      end

      # The game's height: the window's without a game area
      def height
        @__game_area ? @__game_area[3] : super
      end

      # The whole window's width, black bars included
      def screen_width
        WindowOrigin.native_width.bind_call(self)
      end

      # The whole window's height, black bars included
      def screen_height
        WindowOrigin.native_height.bind_call(self)
      end

      # A position the window reported (screen pixels), moved so the game's
      # (0, 0) is at (0, 0). The game converts it to its own pixels itself
      # (PSDK: x * window width / desktop width).
      # @return [Array(Integer, Integer)]
      def to_game_pixels(x, y)
        area = @__game_area
        return [x, y] unless area && (area[0] != 0 || area[1] != 0)

        [(x - area[0] * DisplayWindow.desktop_width / screen_width.to_f).round,
         (y - area[1] * DisplayWindow.desktop_height / screen_height.to_f).round]
      end

      def on_mouse_moved=(proc)
        super(proc && WindowOrigin.translated(self, proc, 0))
      end

      # The touch overlay forwards the touches it does not take, translated
      # (TouchOverlay::Overlay#forward_touch): its callbacks see the screen.
      # Without it, the game's callbacks are translated here.
      TOUCH_EVENTS.each do |event|
        define_method(:"on_#{event}=") do |proc|
          return super(proc) if !proc || (respond_to?(:touch_overlay) && touch_overlay)

          super(WindowOrigin.translated(self, proc, 1))
        end
      end
    end

    class << self
      # DisplayWindow's own width / height, before the game area
      attr_reader :native_width, :native_height

      # Does this LiteRGSS move a game on its window?
      def supported?
        LiteRGSS::DisplayWindow.method_defined?(:origin=) &&
          LiteRGSS::Viewport.method_defined?(:screen_space=)
      end

      # Hook LiteRGSS::DisplayWindow (idempotent)
      # @return [Boolean] if the hook is installed
      def install
        return true if LiteRGSS::DisplayWindow.ancestors.include?(Window)
        return false unless supported?

        @native_width = LiteRGSS::DisplayWindow.instance_method(:width)
        @native_height = LiteRGSS::DisplayWindow.instance_method(:height)
        LiteRGSS::DisplayWindow.prepend(Window)
        true
      end

      # The callback with the position its arguments hold from index (the
      # finger comes first in touch events) moved to the game's
      # @return [Proc]
      def translated(window, proc, index)
        lambda do |*args|
          if args.size >= index + 2
            args = args.dup
            args[index, 2] = window.to_game_pixels(args[index], args[index + 1])
          end
          proc.call(*args)
        end
      end
    end
  end
end
