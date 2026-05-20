# Unit tests for the PSDKVMSnapshot::Native C extension.
#
# Designed to run inside the embedded-ruby-vm test pipeline:
# tests/native/core/test_psdk_vm_snapshot_native.c is a thin C
# harness that creates an interpreter, registers Init_* via
# ruby_set_custom_ext_init(), then execute_sync's this script.
#
# Because SafeRunner intercepts Kernel#exit and Minitest's autorun
# hooks via at_exit (which doesn't fire under SafeRunner.run), we
# call Minitest.run explicitly and exit with its status code so the
# host C harness sees the right exit code via execute_sync.

require 'minitest'

NATIVE_LOADED = defined?(PSDKVMSnapshot::Native) &&
                PSDKVMSnapshot::Native.respond_to?(:unprepend)

class TestPSDKVMSnapshotNative < Minitest::Test
  def setup
    skip "native ext not registered — host must call Init_psdk_vm_snapshot_native " \
         "via ruby_set_custom_ext_init() before execute_sync" unless NATIVE_LOADED
  end

  # --- Existence / surface ---

  def test_unprepend_is_defined
    assert PSDKVMSnapshot::Native.respond_to?(:unprepend)
    assert PSDKVMSnapshot::Native.respond_to?(:subclass_cleanup_available?)
  end

  def test_unprepend_arity
    # singleton_method(:unprepend).arity should be 2.
    assert_equal 2, PSDKVMSnapshot::Native.method(:unprepend).arity
  end

  # --- Type checking ---

  def test_unprepend_rejects_non_module_target
    assert_raises(TypeError) { PSDKVMSnapshot::Native.unprepend(42, Module.new) }
    assert_raises(TypeError) { PSDKVMSnapshot::Native.unprepend("str", Module.new) }
    assert_raises(TypeError) { PSDKVMSnapshot::Native.unprepend(nil, Module.new) }
  end

  def test_unprepend_rejects_non_module_mod
    assert_raises(TypeError) { PSDKVMSnapshot::Native.unprepend(Class.new, 42) }
    assert_raises(TypeError) { PSDKVMSnapshot::Native.unprepend(Class.new, "str") }
    assert_raises(TypeError) { PSDKVMSnapshot::Native.unprepend(Class.new, nil) }
  end

  def test_unprepend_accepts_class_target
    klass = Class.new
    mod = Module.new
    klass.prepend(mod)
    assert PSDKVMSnapshot::Native.unprepend(klass, mod)
  end

  def test_unprepend_accepts_module_target
    outer = Module.new
    mod = Module.new
    outer.prepend(mod)
    assert PSDKVMSnapshot::Native.unprepend(outer, mod)
  end

  def test_unprepend_returns_false_when_target_equals_mod
    # Defensive: passing the same module twice would have nonsensical
    # semantics. The extension just returns false rather than scanning
    # its own chain looking for itself.
    m = Module.new
    refute PSDKVMSnapshot::Native.unprepend(m, m)
  end

  # --- Found / not found ---

  def test_unprepend_returns_false_when_mod_not_in_chain
    refute PSDKVMSnapshot::Native.unprepend(Class.new, Module.new)
  end

  def test_unprepend_returns_true_after_prepend
    klass = Class.new
    mod = Module.new
    klass.prepend(mod)
    assert PSDKVMSnapshot::Native.unprepend(klass, mod)
  end

  def test_unprepend_returns_true_after_include
    klass = Class.new
    mod = Module.new
    klass.include(mod)
    assert PSDKVMSnapshot::Native.unprepend(klass, mod)
  end

  def test_unprepend_is_idempotent_after_success
    klass = Class.new
    mod = Module.new
    klass.prepend(mod)
    assert PSDKVMSnapshot::Native.unprepend(klass, mod)
    refute PSDKVMSnapshot::Native.unprepend(klass, mod),
           "second unprepend should return false (already gone)"
  end

  # --- Ancestor chain effect ---

  def test_unprepend_removes_module_from_ancestors
    klass = Class.new
    mod = Module.new
    klass.prepend(mod)
    assert_includes klass.ancestors, mod
    PSDKVMSnapshot::Native.unprepend(klass, mod)
    refute_includes klass.ancestors, mod
  end

  def test_unprepend_preserves_class_itself_in_ancestors
    klass = Class.new
    mod = Module.new
    klass.prepend(mod)
    PSDKVMSnapshot::Native.unprepend(klass, mod)
    assert_includes klass.ancestors, klass
    assert_includes klass.ancestors, Object
  end

  # --- Method dispatch ---

  def test_unprepend_falls_through_to_class_methods_after_prepend
    klass = Class.new { def kind; "class"; end }
    mod = Module.new { def kind; "module"; end }
    klass.prepend(mod)
    assert_equal "module", klass.new.kind
    PSDKVMSnapshot::Native.unprepend(klass, mod)
    assert_equal "class", klass.new.kind
  end

  def test_unprepend_after_include_makes_method_undefined
    klass = Class.new
    mod = Module.new { def added; 1; end }
    klass.include(mod)
    assert_equal 1, klass.new.added
    PSDKVMSnapshot::Native.unprepend(klass, mod)
    refute klass.new.respond_to?(:added)
  end

  def test_unprepend_with_super_chain_works
    base = Class.new { def stack; ["base"]; end }
    mod = Module.new { def stack; super + ["mod"]; end }
    base.prepend(mod)
    assert_equal ["base", "mod"], base.new.stack
    PSDKVMSnapshot::Native.unprepend(base, mod)
    assert_equal ["base"], base.new.stack
  end

  # --- Multiple prepends ---

  def test_unprepend_specific_module_from_stack
    klass = Class.new { def stack; ["base"]; end }
    a = Module.new { def stack; super + ["a"]; end }
    b = Module.new { def stack; super + ["b"]; end }
    c = Module.new { def stack; super + ["c"]; end }
    klass.prepend(a)
    klass.prepend(b)
    klass.prepend(c)
    assert_equal ["base", "a", "b", "c"], klass.new.stack

    # Remove the middle one; outer modules keep working.
    PSDKVMSnapshot::Native.unprepend(klass, b)
    assert_equal ["base", "a", "c"], klass.new.stack

    # Remove the outer.
    PSDKVMSnapshot::Native.unprepend(klass, c)
    assert_equal ["base", "a"], klass.new.stack

    # Remove the innermost.
    PSDKVMSnapshot::Native.unprepend(klass, a)
    assert_equal ["base"], klass.new.stack
  end

  # --- Sibling isolation: the headline correctness property ---

  def test_unprepending_from_one_target_leaves_sibling_untouched
    shared = Module.new { def tag; "shared"; end }
    a = Class.new { def tag; "a"; end }
    b = Class.new { def tag; "b"; end }
    a.prepend(shared)
    b.prepend(shared)
    assert_equal "shared", a.new.tag
    assert_equal "shared", b.new.tag

    PSDKVMSnapshot::Native.unprepend(a, shared)

    assert_equal "a",      a.new.tag, "a was unprepended"
    assert_equal "shared", b.new.tag, "b's chain must be independent"
  end

  def test_unprepending_does_not_break_shared_module_methods
    shared = Module.new do
      def helper; "from shared"; end
    end
    target = Class.new
    target.prepend(shared)
    PSDKVMSnapshot::Native.unprepend(target, shared)

    # The shared module itself still works — its method table is
    # untouched (only the IClass wrapping was spliced out of `target`).
    user = Class.new { include shared }
    assert_equal "from shared", user.new.helper
  end

  # --- Method cache invalidation ---
  #
  # If the cache wasn't invalidated, the first dispatch after the splice
  # could still hit the spliced-out IClass's cached entry. Force a few
  # warm-up calls before unprepend to populate caches, then test that
  # dispatch correctly switches.

  def test_unprepend_invalidates_method_cache
    klass = Class.new { def x; "base"; end }
    mod = Module.new { def x; "mod"; end }
    klass.prepend(mod)

    # Warm up caches across multiple instances.
    100.times { klass.new.x }
    assert_equal "mod", klass.new.x

    PSDKVMSnapshot::Native.unprepend(klass, mod)

    # First call after splice must see the new dispatch path.
    assert_equal "base", klass.new.x
  end

  # --- Subclass-list cleanup (only when the optional hook is wired) ---
  #
  # Without cleanup, a long-lived mixin's subclass list keeps every
  # IClass we ever created alive, even after we splice them out of
  # their targets' chains. With cleanup, the IClass becomes a GC root
  # only via the chain we just severed, so it gets reclaimed at the
  # next collection.
  #
  # The test holds `mixin` alive across many prepend/unprepend cycles
  # of ephemeral targets, and measures T_ICLASS count growth. With
  # cleanup, growth should be near zero; without, growth should be
  # roughly equal to the iteration count.

  def test_subclass_cleanup_prevents_leak_when_mixin_outlives_target
    skip "subclass-list cleanup hook not exported by this libruby — " \
         "see Native.subclass_cleanup_available?" \
      unless PSDKVMSnapshot::Native.subclass_cleanup_available?

    mixin = Module.new

    GC.start; GC.start
    baseline = ObjectSpace.count_objects[:T_ICLASS]

    iters = 200
    iters.times do
      target = Class.new
      target.prepend(mixin)
      PSDKVMSnapshot::Native.unprepend(target, mixin)
      # `target` goes out of scope; with cleanup, mixin no longer
      # holds onto the IClass that was wrapping it for `target`.
    end

    GC.start; GC.start
    after = ObjectSpace.count_objects[:T_ICLASS]
    growth = after - baseline

    # With cleanup, growth should be near zero. Allow modest slack
    # (~10%) for unrelated allocations the test infrastructure may do.
    assert growth < iters / 10,
           "T_ICLASS count grew by #{growth} over #{iters} iterations; " \
           "cleanup hook may be misbehaving (baseline=#{baseline}, after=#{after})"
  end

  def test_subclass_cleanup_availability_query_returns_boolean
    v = PSDKVMSnapshot::Native.subclass_cleanup_available?
    assert v.equal?(true) || v.equal?(false), "expected literal true/false, got #{v.inspect}"
  end
end

# Drive the runner explicitly: Minitest's autorun uses at_exit, which
# doesn't fire when the script is invoked via SafeRunner.run + execute_sync.
# Minitest.run returns true on success / false on failure — translate to
# a numeric exit code so the C harness can read it from execute_sync.
exit(Minitest.run([]) ? 0 : 1)
