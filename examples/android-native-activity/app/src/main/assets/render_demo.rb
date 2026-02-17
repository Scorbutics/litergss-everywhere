# render_demo.rb
#
# Minimal LiteRGSS rendering example for Android NativeActivity.
# Displays a red rectangle on a black background.
#
# This script is executed by the native main() function in librgss_runtime.so
# after SFML has set up the OpenGL ES2 rendering context via NativeActivity.

require 'LiteRGSS'

# Disable shaders (not needed for this simple demo)
LiteRGSS::Shader.available = false

# Create display window
# On Android with NativeActivity, SFML uses the full-screen ANativeWindow
window = LiteRGSS::DisplayWindow.new('LiteRGSS Demo', 640, 480, 1)

# Create a viewport covering the window
viewport = LiteRGSS::Viewport.new(window, 640, 480)

# Create a red rectangle bitmap
bitmap = LiteRGSS::Bitmap.new(100, 100)
bitmap.fill_rect(0, 0, 100, 100, LiteRGSS::Color.new(255, 0, 0, 255))

# Create a sprite and attach the bitmap
sprite = LiteRGSS::Sprite.new(viewport)
sprite.bitmap = bitmap
sprite.set_position(270, 190)

# Main rendering loop
running = true
window.on_closed = proc { running = false }

while running
  window.update
end

window.dispose
