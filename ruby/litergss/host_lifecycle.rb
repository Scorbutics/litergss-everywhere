# The host app's lifecycle, for a game running inside one (Android): what to
# do when the app goes to the background, where the system may kill it
# without warning (a phone's memory optimiser), and when it comes back.
#
#   require 'litergss/host_lifecycle'
#   LiteRGSS::HostLifecycle.install        # before the game creates its window
#   LiteRGSS::HostLifecycle.on_background { write_what_must_survive }
#   LiteRGSS::HostLifecycle.on_foreground { ... }
#
# Fed by the window's focus events. Hosted on Android, a window gets its
# LostFocus at the frame boundary before the game pauses in the background
# (LiteCGSS: cgss::android::hostSurfaceFocusLostDelivered): a background
# handler runs while the process is still alive, on the game's thread,
# between two frames. It has no GL surface: files, not drawing.
#
# It only relies on LiteRGSS, never on the game's scripts. The game's own
# focus callbacks keep working (a game pausing its sound on them): they are
# wrapped, and run first. A handler that raises is reported and skipped,
# never the game's problem.
module LiteRGSS
  module HostLifecycle
    @handlers = { background: [], foreground: [] }

    class << self
      # Run the block each time the app goes to the background
      def on_background(&block)
        @handlers[:background] << block
        block
      end

      # Run the block each time the app comes back to the foreground
      def on_foreground(&block)
        @handlers[:foreground] << block
        block
      end

      # Forget a block given to on_background / on_foreground
      def remove(block)
        @handlers.each_value { |list| list.delete(block) }
      end

      # The app is in the background (its last focus event was a loss)
      def background?
        @background == true
      end

      # Hook LiteRGSS::DisplayWindow (idempotent)
      def install
        return if LiteRGSS::DisplayWindow.ancestors.include?(WindowHooks)

        LiteRGSS::DisplayWindow.prepend(WindowHooks)
        LiteRGSS::DisplayWindow.singleton_class.prepend(WindowCreation)
      end

      # @api private: the window's focus callback, the game's one first
      def focus_callback(kind, game_proc)
        proc do |*args|
          result = game_proc&.call(*args)
          HostLifecycle.notify(kind)
          result
        end
      end

      # @api private
      def notify(kind)
        @background = kind == :background
        @handlers[kind].dup.each do |handler|
          handler.call
        rescue StandardError => e
          warn "[HostLifecycle] #{kind} handler failed: #{e.class}: #{e.message}"
        end
      end
    end

    # Prepended to LiteRGSS::DisplayWindow: the game's focus callbacks are
    # wrapped, the lifecycle handlers run after them.
    module WindowHooks
      def on_lost_focus=(proc)
        super(HostLifecycle.focus_callback(:background, proc))
      end

      def on_gained_focus=(proc)
        super(HostLifecycle.focus_callback(:foreground, proc))
      end
    end

    # Prepended to LiteRGSS::DisplayWindow's singleton: a window whose game
    # sets no focus callback still notifies the handlers.
    module WindowCreation
      def new(*args, &block)
        window = super
        window.on_lost_focus = nil
        window.on_gained_focus = nil
        window
      end
    end
  end
end
