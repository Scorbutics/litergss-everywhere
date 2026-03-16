# render_demo.rb
#
# LiteRGSS rendering example for Android NativeActivity.
# A red rectangle spins and moves toward the last touch point on screen.
#
# This script is executed by the native main() function in librgss_runtime.so
# after SFML has set up the OpenGL ES2 rendering context via NativeActivity.

require 'LiteRGSS'

# Disable shaders (not needed for this simple demo)
LiteRGSS::Shader.available = false

# Use the device's actual resolution to preserve aspect ratio
screen_w = LiteRGSS::DisplayWindow.desktop_width
screen_h = LiteRGSS::DisplayWindow.desktop_height

resize_factor = 0.5

# Create display window at portion of the device resolution
screen_w *= resize_factor
screen_h *= resize_factor
window = LiteRGSS::DisplayWindow.new('LiteRGSS Demo', screen_w, screen_h, 1)

# Create a viewport covering the window
viewport = LiteRGSS::Viewport.new(window, screen_w, screen_h)

# Create a red rectangle bitmap
bitmap = LiteRGSS::Bitmap.new(80, 80)
bitmap.fill_rect(0, 0, 80, 80, LiteRGSS::Color.new(255, 0, 0, 255))

# Create the sprite and center its origin so it rotates around its center
sprite = LiteRGSS::Sprite.new(viewport)
sprite.bitmap = bitmap
sprite.set_origin(40, 40)

# Start at the center of the screen
pos_x = screen_w / 2.0
pos_y = screen_h / 2.0
vel_x = 0.0
vel_y = 0.0
accel = 2.0
friction = 0.95
half_size = 40
rotation = 0.0

# Screen bounds (sprite origin is centered)
min_x = half_size.to_f
min_y = half_size.to_f
max_x = screen_w - half_size.to_f
max_y = screen_h - half_size.to_f

# Map device touch coordinates to the resized viewport
touch_scale = resize_factor

# Track touch state: store last known position while finger is down
touching = false
touch_x = 0.0
touch_y = 0.0

window.on_touch_began = proc { |_finger_id, x, y|
  touching = true
  touch_x = x.to_f * touch_scale
  touch_y = y.to_f * touch_scale
}

window.on_touch_moved = proc { |_finger_id, x, y|
  touch_x = x.to_f * touch_scale
  touch_y = y.to_f * touch_scale
}

window.on_touch_ended = proc { |_finger_id, _x, _y|
  touching = false
}

# Main rendering loop
running = true
window.on_closed = proc { running = false }

while running
  # Accelerate toward touch while finger is down
  if touching
    dx = touch_x - pos_x
    dy = touch_y - pos_y
    dist = Math.sqrt(dx * dx + dy * dy)
    if dist > 1
      vel_x += dx / dist * accel
      vel_y += dy / dist * accel
    end
  end

  # Apply velocity with friction decay
  vel_x *= friction
  vel_y *= friction
  pos_x += vel_x
  pos_y += vel_y

  # Clamp to screen borders
  pos_x = min_x if pos_x < min_x
  pos_x = max_x if pos_x > max_x
  pos_y = min_y if pos_y < min_y
  pos_y = max_y if pos_y > max_y

  sprite.x = pos_x.to_i
  sprite.y = pos_y.to_i

  # Keep spinning
  rotation = (rotation + 2) % 360
  sprite.angle = rotation

  window.update
end

window.dispose
