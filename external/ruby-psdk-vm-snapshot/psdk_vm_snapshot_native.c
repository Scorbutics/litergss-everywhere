/*
 * psdk_vm_snapshot_native.c
 *
 * Native helpers for PSDKVMSnapshot. Currently a single op: unprepend.
 *
 * Why this exists: pure-Ruby snapshot restore can't undo `Module#prepend`
 * because MRI's chain is monotonic from the Ruby API. The chain is a
 * linked list of T_ICLASS proxies wrapping included/prepended modules.
 * Removing one means re-linking the predecessor's super pointer past
 * the IClass we want gone — a direct manipulation of MRI internals.
 *
 * Targets MRI 3.1.1 (the version embedded by litergss-everywhere). The
 * struct RClass layout used here is stable across 3.1.x patch versions
 * and 3.0 / 3.2; major-version bumps may need a re-audit (look at
 * `super` field placement in `include/ruby/internal/core/rclass.h`).
 *
 * Risks we accept (see discussion with maintainers):
 *   - `prepended` / `included` callbacks that captured references
 *     during the original prepend are NOT un-called; whatever side
 *     effect they had needs to be undone by the Ruby-side snapshot
 *     restore (ivars/cvars/constants — which it already handles).
 *
 * Risks we mitigate:
 *   - Method cache: invalidated via rb_clear_method_cache_by_class.
 *   - Origin IClass (created by prepend's class-split): naturally
 *     skipped because its RBASIC_CLASS is the target itself, never
 *     the module we're searching for.
 *   - GC: write barrier via RB_OBJ_WRITE on the super pointer.
 *   - Threading: callers hold the GVL (we're in a sync C call).
 *   - Subclass-list leak: after splicing the IClass out of target's
 *     chain, the IClass is still in its source module's internal
 *     subclass-entries linked list (used by MRI to propagate later
 *     method redefinitions on the source mod, and as a strong GC
 *     ref). We call rb_class_remove_from_module_subclasses to unlink
 *     it cleanly. That function is in MRI's internal/class.h, not
 *     public, so we look it up via dlsym; if the symbol isn't
 *     exported by the linked libruby, we skip the cleanup and accept
 *     the small leak (logged once at init).
 */

#include <ruby.h>
#include <dlfcn.h>
#include <stdio.h>

/* Hard guard. The struct RClass layout and the dlsym lookup below are
 * specific to MRI 3.1.x. If you've bumped Ruby, you need to:
 *   1. Verify struct RClass's `super` field placement in the new
 *      version's internal/class.h. Update the redeclaration below.
 *   2. Verify `rb_class_remove_from_module_subclasses` still exists
 *      under that name (it may have been renamed or made truly static).
 *   3. Re-run the rgss_psdk_vm_snapshot_test suite end-to-end.
 *   4. Update this guard and extconf.rb to allow the new minor.
 *
 * Without this guard, silently building against (e.g.) 3.2 would
 * read garbage from RCLASS(c)->super at runtime — exactly the kind
 * of hard-to-track corruption the test pipeline can't reliably catch. */
#if !defined(RUBY_API_VERSION_MAJOR) || !defined(RUBY_API_VERSION_MINOR)
#  error "ruby/version.h didn't define RUBY_API_VERSION_MAJOR/MINOR; cannot verify ABI compatibility."
#elif RUBY_API_VERSION_MAJOR != 3 || RUBY_API_VERSION_MINOR != 1
#  error \
    "ruby-psdk-vm-snapshot targets MRI 3.1.x only. " \
    "The struct RClass layout below comes from MRI 3.1.x internal/class.h; " \
    "add a branch for the new minor and verify the layout before relaxing this guard."
#endif

/* MRI 3.1's public header forward-declares `struct RClass` as opaque
 * (see ruby/internal/core/rclass.h: "Opaque, declared here for
 * RCLASS() macro"). The complete layout lives in internal/class.h,
 * which is not shipped with stock libruby installs — so
 * `RCLASS(c)->super` fails to compile against a public-only install.
 *
 * Provide the 3.1.x layout locally. Each compilation unit can complete
 * a forward declaration with its own definition, and C has no struct-
 * level ODR, so this coexists fine with libruby's own internal
 * definition at link time. The memory layout must match exactly —
 * audit on every Ruby version bump.
 *
 * Source: MRI 3.1.x internal/class.h. Stable across 3.1 patch releases.
 * The trailing `ptr` field is a `struct rb_classext_struct *` we never
 * dereference, modelled as void* to avoid pulling in internal headers. */
struct RClass {
    struct RBasic basic;
    VALUE super;
    void *ptr;
};

/* Internal API, exported by MRI but not in the public ruby.h. Declared
 * here to avoid #include "internal/vm.h", which isn't always shipped
 * with stock Ruby installs. Stable since 2.x. */
extern void rb_clear_method_cache_by_class(VALUE klass);

/* Removes an IClass from its source module's subclass linked list.
 * Declared in MRI's internal/class.h. Looked up at module init via
 * dlsym so we degrade gracefully if libruby doesn't export it. */
typedef void (*remove_from_subclasses_fn)(VALUE klass);
static remove_from_subclasses_fn s_remove_from_subclasses = NULL;

/*
 * PSDKVMSnapshot::Native.unprepend(target, mod) -> true/false
 *
 * Walks `target`'s super chain looking for an IClass wrapping `mod`.
 * If found, splices it out by setting the predecessor's super to the
 * IClass's super, invalidates the method cache for `target`, and
 * returns true. Returns false if no matching IClass is in the chain.
 *
 * Works uniformly for `prepend` and `include` — the IClass is in a
 * different position for each but the splice operation is identical.
 *
 * Caveat: removes the IClass from `target`'s chain only. If `mod` was
 * also prepended into a sibling class, that sibling still sees `mod`
 * via its own (separate) IClass node.
 */
static VALUE
psdk_unprepend(VALUE self, VALUE target, VALUE mod)
{
    if (!(RB_TYPE_P(target, T_CLASS) || RB_TYPE_P(target, T_MODULE))) {
        rb_raise(rb_eTypeError,
                 "expected Module or Class as first arg, got %"PRIsVALUE,
                 rb_obj_class(target));
    }
    if (!(RB_TYPE_P(mod, T_MODULE) || RB_TYPE_P(mod, T_CLASS))) {
        rb_raise(rb_eTypeError,
                 "expected Module or Class as second arg, got %"PRIsVALUE,
                 rb_obj_class(mod));
    }
    if (target == mod) {
        return Qfalse;  /* Defensive: prepending self into self is nonsensical. */
    }

    VALUE prev = target;
    VALUE cur = RCLASS(target)->super;

    while (RTEST(cur)) {
        /* RBASIC_CLASS(iclass) is set to the source module when the
         * IClass is created (see include_class_new in MRI's class.c).
         * The "origin IClass" that prepend creates to hold the target's
         * own methods has its class field set to the target itself, so
         * checking == mod naturally excludes the origin. */
        if (RB_TYPE_P(cur, T_ICLASS) && RBASIC_CLASS(cur) == mod) {
            VALUE next = RCLASS(cur)->super;
            /* Use write barrier — `next` is a Ruby VALUE we're now
             * referencing from `prev`. Without WB, generational GC
             * could miss this reference between collections. */
            RB_OBJ_WRITE(prev, &RCLASS(prev)->super, next);
            /* Unlink the IClass from mod's subclass-entries list, so
             * (1) future method redefinitions on `mod` don't try to
             * propagate to a chain that no longer contains it, and
             * (2) the IClass becomes truly orphaned and GC-eligible
             * even when `mod` outlives the splice. */
            if (s_remove_from_subclasses) {
                s_remove_from_subclasses(cur);
            }
            rb_clear_method_cache_by_class(target);
            return Qtrue;
        }
        prev = cur;
        cur = RCLASS(cur)->super;
    }

    return Qfalse;
}

/* psdk_subclass_cleanup_available? -> true/false
 *
 * Test hook: returns whether the optional subclass-list cleanup hook
 * is wired up at runtime. Tests use this to decide whether to assert
 * on the leak-free path or to skip leak-observability checks. */
static VALUE
psdk_subclass_cleanup_available(VALUE self)
{
    return s_remove_from_subclasses ? Qtrue : Qfalse;
}

void
Init_psdk_vm_snapshot_native(void)
{
    /* RTLD_DEFAULT searches the global symbol scope — includes libruby
     * when we're loaded by MRI. Returns NULL if the symbol isn't
     * exported (e.g. an MRI build that hid internal symbols). */
    s_remove_from_subclasses = (remove_from_subclasses_fn)
        dlsym(RTLD_DEFAULT, "rb_class_remove_from_module_subclasses");

    VALUE mPSDKVMSnapshot = rb_define_module("PSDKVMSnapshot");
    VALUE mNative = rb_define_module_under(mPSDKVMSnapshot, "Native");
    rb_define_singleton_method(mNative, "unprepend", psdk_unprepend, 2);
    rb_define_singleton_method(mNative, "subclass_cleanup_available?",
                               psdk_subclass_cleanup_available, 0);
}
