RUSTC ?= rustc
PYTHON ?= python
PYTHON3 ?= python3
RUST_SRC ?= ../rust
EM_FASTCOMP ?= /usr
EM_PLUGINS ?= 
CLOSURE_COMPILER ?= closure-compiler
YUI_COMPRESSOR ?= yui-compressor

HOST = x86_64-unknown-linux-gnu
TARGET = i686-unknown-linux-gnu

SRC = .
BUILD = build
DIST = dist

BUILD_ASMJS := $(BUILD)/asmjs
BUILD_NATIVE_DEBUG := $(BUILD)/native
BUILD_NATIVE_RELEASE := $(BUILD)/native.opt
BUILD_ASMLIBS := $(BUILD)/asmlibs
BUILD_MIN := $(BUILD)/min

DIST_BIN = $(DIST)/bin
DIST_WWW = $(DIST)/www

$(shell mkdir -p $(BUILD_ASMJS) $(BUILD_NATIVE_DEBUG) $(BUILD_NATIVE_RELEASE) \
	$(BUILD_ASMLIBS) $(BUILD_MIN) \
	$(DIST) $(DIST_BIN) $(DIST_WWW) $(DIST_WWW)/assets)


JS_SRCS = $(wildcard $(SRC)/client/js/*.js)


all: $(DIST)/all

redist:
	rm -r $(DIST)
	$(MAKE) -f $(SRC)/Makefile $(DIST)/all

clean:
	rm -rf $(BUILD) $(DIST)

# Dependencies of Rust libraries

define LIB_DEPS
$(BUILD)/$(1)/lib$(2).rlib: $(foreach dep,$(3),$(BUILD)/$(1)/lib$(dep).rlib)
$(BUILD)/$(1)/lib$(2).so: $(foreach dep,$(3),$(BUILD)/$(1)/lib$(dep).so)
endef

DEPS_physics_asmjs = core asmrt
DEPS_physics_native =
DEPS_graphics_asmjs = core asmrt physics
DEPS_graphics_native = physics
ALL_LIBS = asmrt physics graphics

$(foreach mode,asmjs native, \
 $(eval $(foreach lib,$(ALL_LIBS), \
  $(eval $(call LIB_DEPS,$(mode),$(lib),$(DEPS_$(lib)_$(mode)))))))


DEPS_asmlibs = core asmrt physics graphics
DEPS_backend = physics


# Rules for building Rust libraries

ifeq ($(RELEASE),)
	RELEASE_RUSTFLAGS_opt = 
	RELEASE_RUSTFLAGS_lto = 
	RELEASE_ext = 
	BUILD_NATIVE = $(BUILD_NATIVE_DEBUG)
else
	RELEASE_RUSTFLAGS_opt = --opt-level=3
	RELEASE_RUSTFLAGS_lto = -C lto
	RELEASE_ext = .opt
	BUILD_NATIVE = $(BUILD_NATIVE_RELEASE)
endif

# FIXME: For asmjs, we force opt-level=3 to eliminate some constructs that
# emscripten-fastcomp doesn't like.
RUSTFLAGS_asmjs = -L $(BUILD_ASMJS) -L $(BUILD_NATIVE) \
		--opt-level=3 --target=$(TARGET) \
		-Z no-landing-pads -C no-stack-check --cfg asmjs

RUSTFLAGS_native = -L $(BUILD_NATIVE) \
		$(RELEASE_RUSTFLAGS_opt) --target=$(HOST)

$(BUILD_ASMJS)/lib%.rlib: $(SRC)/%/lib.rs
	$(RUSTC) $< --out-dir $(BUILD_ASMJS) --crate-type=rlib $(RUSTFLAGS_asmjs) \
		--dep-info $(BUILD_ASMJS)/$*.d

# Special rule for libcore, since its source code is in a weird location.
$(BUILD_ASMJS)/libcore.rlib: $(RUST_SRC)/src/libcore/lib.rs
	$(RUSTC) $< --out-dir $(BUILD_ASMJS) --crate-type=rlib $(RUSTFLAGS_asmjs)

$(BUILD_NATIVE)/lib%.rlib: $(SRC)/%/lib.rs
	$(RUSTC) $< --out-dir $(BUILD_NATIVE) --crate-type=rlib $(RUSTFLAGS_native) \
		--dep-info $(BUILD_NATIVE)/$*.d

$(BUILD_NATIVE)/lib%.so: $(SRC)/%/lib.rs
	$(RUSTC) $< --out-dir $(BUILD_NATIVE) --crate-type=dylib $(RUSTFLAGS_native) \
		--dep-info $(BUILD_NATIVE)/$*.d

-include $(wildcard $(BUILD_ASMJS)/*.d $(BUILD_NATIVE)/*.d)


# Rules for building asmlibs.js

ASMLIBS = $(BUILD_ASMLIBS)/asmlibs

$(ASMLIBS).ll: $(SRC)/client/asmlibs.rs $(foreach dep,$(DEPS_asmlibs),$(BUILD_ASMJS)/lib$(dep).rlib)
	$(RUSTC) $< -o $@ --emit=ir --crate-type=staticlib $(RUSTFLAGS_asmjs) -C lto

$(ASMLIBS).clean.ll: $(ASMLIBS).ll
	sed -e 's/\<\(readonly\|readnone\|cold\)\>//g' \
		-e 's/\<dereferenceable([0-9]*)//g' \
		$< >$@

$(ASMLIBS).bc: $(ASMLIBS).clean.ll
	$(EM_FASTCOMP)/bin/llvm-as $< -o $@

ASMLIBS_APIS = $(shell tr '\n' ',' <$(SRC)/client/asmlibs_exports.txt)
$(ASMLIBS).opt.bc: $(ASMLIBS).bc $(SRC)/client/asmlibs_exports.txt
	$(EM_FASTCOMP)/bin/opt $< \
		-load=$(EM_PLUGINS)/BreakStructArguments.so \
		-strip-debug \
		-internalize -internalize-public-api-list=$(ASMLIBS_APIS) \
		-break-struct-arguments \
		-globaldce \
		-pnacl-abi-simplify-preopt -pnacl-abi-simplify-postopt \
		-enable-emscripten-cxx-exceptions \
		-o $@

$(ASMLIBS).0.js: $(ASMLIBS).opt.bc
	$(EM_FASTCOMP)/bin/llc $< \
		-march=js -filetype=asm \
		-emscripten-assertions=1 \
		-emscripten-no-aliasing-function-pointers \
		-emscripten-max-setjmps=20 \
		-O3 \
		-o $@

$(ASMLIBS).1.js: $(ASMLIBS).0.js $(SRC)/util/asmjs_function_tables.py
	$(PYTHON) $(SRC)/util/asmjs_function_tables.py <$< >$@

$(ASMLIBS).js: $(SRC)/client/asmlibs.tmpl.js $(ASMLIBS).1.js \
		$(SRC)/util/asmjs_insert_functions.awk
	awk -f $(SRC)/util/asmjs_insert_functions.awk <$< >$@



# Rules for running closure compiler

CLOSURE_FLAGS=--language_in=ECMASCRIPT5_STRICT \
			  --output_wrapper='(function(){%output%})();'

$(BUILD_MIN)/asmlibs.js: $(BUILD_ASMLIBS)/asmlibs.js
	$(YUI_COMPRESSOR) --disable-optimizations --line-break 200 $< | \
		sed -e '1s/{/{"use asm";/' >$@

$(BUILD_MIN)/outpost.js: $(JS_SRCS)
	$(CLOSURE_COMPILER) $(CLOSURE_FLAGS) \
		$^ --js_output_file=$@ --compilation_level=ADVANCED_OPTIMIZATIONS \
		--process_common_js_modules --common_js_entry_module=main \
		--common_js_module_path_prefix=$$(dirname $<) \
		--externs=$(SRC)/util/closure_externs.js


# Rules for building the server

$(BUILD_NATIVE)/backend: $(SRC)/server/main.rs \
		$(foreach dep,$(DEPS_backend),$(BUILD_NATIVE)/lib$(dep).rlib)
	$(RUSTC) $< -o $@ $(RUSTFLAGS_native) $(RELEASE_RUSTFLAGS_lto) \
		--dep-info $(BUILD_NATIVE)/backend.d


# Rules for misc files

$(BUILD)/tiles.json $(BUILD)/tiles.png: \
		$(SRC)/util/process_tiles.py \
		$(SRC)/client/assets/tiles.yaml \
		$(SRC)/client/assets/blocks.yaml
	$(PYTHON3) $^ >$(BUILD)/tiles.json \
		--gen-atlas-file=$(BUILD)/tiles.png \
		--atlas-input-dir=$(SRC)/client/assets/tiles

$(BUILD)/client.debug.html: $(SRC)/client/client.html \
	$(SRC)/util/collect_js_deps.py $(SRC)/util/patch_script_tags.py $(JS_SRCS)
	$(PYTHON3) $(SRC)/util/collect_js_deps.py $(SRC)/client/js/main.js | \
		$(PYTHON3) $(SRC)/util/patch_script_tags.py $< >$@


# Rules for copying files into dist/

define WWW_FILE_
$(DIST_WWW)/$(1): $(2)
	cp -v $$< $$@

$(DIST)/all: $(DIST_WWW)/$(1)
endef
WWW_FILE = $(call WWW_FILE_,$(strip $(1)),$(strip $(2)))

$(eval $(call WWW_FILE, tiles.json, 	$(BUILD)/tiles.json))
$(eval $(call WWW_FILE, assets/tiles.png, 	$(BUILD)/tiles.png))

ifeq ($(RELEASE),)
$(eval $(call WWW_FILE, client.html, 	$(BUILD)/client.debug.html))
$(eval $(call WWW_FILE, shim.js, 		$(SRC)/client/shim.js))
$(eval $(call WWW_FILE, asmlibs.js, 	$(BUILD_ASMLIBS)/asmlibs.js))
$(shell mkdir -p $(DIST_WWW)/js)
dist/all: $(patsubst $(SRC)/client/js/%,$(DIST_WWW)/js/%,$(JS_SRCS))
else
$(eval $(call WWW_FILE, client.html, 	$(SRC)/client/client.html))
$(eval $(call WWW_FILE, outpost.js, 	$(BUILD_MIN)/outpost.js))
$(eval $(call WWW_FILE, asmlibs.js, 	$(BUILD_MIN)/asmlibs.js))
endif

$(DIST)/all: $(patsubst %,$(DIST_WWW)/assets/%,$(shell cat $(SRC)/client/assets/used.txt))

$(DIST_WWW)/assets/%: $(SRC)/client/assets/%
	mkdir -p $$(dirname $@)
	cp -v $< $@

$(DIST_WWW)/js/%: $(SRC)/client/js/%
	cp -v $< $@

$(DIST_BIN)/backend: $(BUILD_NATIVE)/backend
	rm -fv $@
	cp -v $< $@

$(DIST_BIN)/wrapper.py: $(SRC)/server/wrapper.py
	cp -v $< $@

$(DIST)/all: $(DIST_BIN)/backend $(DIST_BIN)/wrapper.py

.PHONY: all clean $(DIST)/all
