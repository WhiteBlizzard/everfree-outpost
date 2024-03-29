# Path to the Rust checkout
RUST_SRC ?= ../rust
# Path to the bitflags checkout
LIBBITFLAGS_SRC ?= $(RUST_SRC)/../rust-libs/bitflags
# Path to the emscripten-fastcomp build/install prefix directory
EM_FASTCOMP ?= /usr
# Path to the rust-emscripten-plugins directory
EM_PLUGINS ?= 

RUSTC ?= rustc
PYTHON ?= python
PYTHON3 ?= python3
CLOSURE_COMPILER ?= closure-compiler
YUI_COMPRESSOR ?= yui-compressor

PYTHON3_INC ?= /usr/include/python3.4

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
DIST_DATA = $(DIST)/data
DIST_WWW = $(DIST)/www
DIST_UTIL = $(DIST)/util

$(shell mkdir -p $(BUILD_ASMJS) $(BUILD_NATIVE_DEBUG) $(BUILD_NATIVE_RELEASE) \
	$(BUILD_ASMLIBS) $(BUILD_MIN) \
	$(DIST) $(DIST_BIN) $(DIST_DATA) $(DIST_WWW) $(DIST_UTIL) $(DIST)/scripts)


JS_SRCS = $(shell find $(SRC)/client/js -name \*.js)


all: $(DIST)/all

redist:
	rm -r $(DIST)
	rm $(BUILD)/server.json
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
	RELEASE_CFLAGS_opt = -ggdb
	RELEASE_CXXFLAGS_opt = -ggdb
	RELEASE_RUSTFLAGS_opt =
	RELEASE_RUSTFLAGS_lto =
	BUILD_NATIVE = $(BUILD_NATIVE_DEBUG)
else
	RELEASE_CFLAGS_opt = -O3
	RELEASE_CXXFLAGS_opt = -O3
	RELEASE_RUSTFLAGS_opt = -C opt-level=3
	RELEASE_RUSTFLAGS_lto = -C lto
	BUILD_NATIVE = $(BUILD_NATIVE_RELEASE)
endif

$(shell mkdir -p \
	$(BUILD_NATIVE)/savegame_py \
	$(BUILD_NATIVE)/wrapper_objs \
)

# FIXME: For asmjs, we force opt-level=3 to eliminate some constructs that
# emscripten-fastcomp doesn't like.
RUSTFLAGS_asmjs = -L $(BUILD_ASMJS) -L $(BUILD_NATIVE) \
		-C opt-level=3 --target=$(TARGET) \
		-Z no-landing-pads -C no-stack-check --cfg asmjs \
		-C no-vectorize-loops -C no-vectorize-slp

ifneq ($(RUST_EXTRA_LIBDIR),)
	RUSTFLAGS_extra_libdir = -L $(RUST_EXTRA_LIBDIR) \
							 --extern log=$(RUST_EXTRA_LIBDIR)/liblog.rlib \
							 --extern rand=$(RUST_EXTRA_LIBDIR)/librand.rlib
endif

RUSTFLAGS_native = -L $(BUILD_NATIVE) $(RUSTFLAGS_extra_libdir) \
		$(RELEASE_RUSTFLAGS_opt) --target=$(HOST)

$(BUILD_ASMJS)/lib%.rlib: $(SRC)/%/lib.rs
	$(RUSTC) $< --out-dir $(BUILD_ASMJS) --crate-type=rlib $(RUSTFLAGS_asmjs) \
		--emit=link,dep-info

# Special rule for libcore, since its source code is in a weird location.
$(BUILD_ASMJS)/libcore.rlib: $(RUST_SRC)/src/libcore/lib.rs
	$(RUSTC) $< --out-dir $(BUILD_ASMJS) --crate-type=rlib $(RUSTFLAGS_asmjs)

# Special rules for libbitflags, which needs a little patching to work without
# libstd.
$(BUILD_ASMJS)/bitflags.rs: $(LIBBITFLAGS_SRC)/src/lib.rs
	echo '#![crate_name = "bitflags"]' > $@.tmp
	echo '#![feature(no_std)]' >> $@.tmp
	echo '#![no_std]' >> $@.tmp
	cat $< >>$@.tmp
	mv -v $@.tmp $@

$(BUILD_ASMJS)/libbitflags.rlib: $(BUILD_ASMJS)/bitflags.rs
	$(RUSTC) $< --out-dir $(BUILD_ASMJS) --crate-type=rlib $(RUSTFLAGS_asmjs)

$(BUILD_NATIVE)/lib%.rlib: $(SRC)/%/lib.rs
	$(RUSTC) $< --out-dir $(BUILD_NATIVE) --crate-type=rlib $(RUSTFLAGS_native) \
		--emit=link,dep-info

$(BUILD_NATIVE)/lib%.so: $(SRC)/%/lib.rs
	$(RUSTC) $< --out-dir $(BUILD_NATIVE) --crate-type=dylib $(RUSTFLAGS_native) \
		--emit=link,dep-info

-include $(wildcard $(BUILD_ASMJS)/*.d $(BUILD_NATIVE)/*.d)


# Rules for building asmlibs.js

ASMLIBS = $(BUILD_ASMLIBS)/asmlibs

$(ASMLIBS).ll: $(SRC)/client/asmlibs.rs $(foreach dep,$(DEPS_asmlibs),$(BUILD_ASMJS)/lib$(dep).rlib)
	$(RUSTC) $< -o $@ --emit=llvm-ir --crate-type=staticlib $(RUSTFLAGS_asmjs) -C lto

$(ASMLIBS).clean.ll: $(ASMLIBS).ll
	sed -e '' \
		-e 's/\<dereferenceable([0-9]*)//g' \
		-e '/^!/s/\(.\)!/\1metadata !/g' \
		-e '/^!/s/distinct //g' \
		$< >$@
		#-e 's/\<\(readonly\|readnone\|cold\)\>//g' \
		#x

$(ASMLIBS).bc: $(ASMLIBS).clean.ll
	$(EM_FASTCOMP)/bin/llvm-as $< -o $@

ASMLIBS_APIS = $(shell tr '\n' ',' <$(SRC)/client/asmlibs_exports.txt)
$(ASMLIBS).opt.bc: $(ASMLIBS).bc $(SRC)/client/asmlibs_exports.txt
	$(EM_FASTCOMP)/bin/opt $< \
		-load=$(EM_PLUGINS)/RemoveOverflowChecks.so \
		-load=$(EM_PLUGINS)/RemoveAssume.so \
		-strip-debug \
		-internalize -internalize-public-api-list=$(ASMLIBS_APIS) \
		-remove-overflow-checks \
		-remove-assume \
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
			  --output_wrapper='(function(){%output%})();' \
			  --jscomp_error=undefinedNames \
			  --jscomp_error=undefinedVars \
			  --create_name_map_files

$(BUILD_MIN)/asmlibs.js: $(BUILD_ASMLIBS)/asmlibs.js
	$(YUI_COMPRESSOR) --disable-optimizations --line-break 200 $< | \
		sed -e '1s/{/{"use asm";/' >$@

$(BUILD_MIN)/outpost.js: $(JS_SRCS)
	$(CLOSURE_COMPILER) $(CLOSURE_FLAGS) \
		$(shell $(PYTHON3) $(SRC)/util/collect_js_deps.py $(SRC)/client/client.html | \
			sed -e 's:.*:$(SRC)/client/js/&.js:') \
		--js_output_file=$@ --compilation_level=ADVANCED_OPTIMIZATIONS \
		--process_common_js_modules --common_js_entry_module=main \
		--common_js_module_path_prefix=$(SRC)/client/js \
		--externs=$(SRC)/util/closure_externs.js

$(BUILD_MIN)/%.js: $(JS_SRCS)
	$(CLOSURE_COMPILER) $(CLOSURE_FLAGS) \
		$(shell $(PYTHON3) $(SRC)/util/collect_js_deps.py $(SRC)/client/$*.html | \
			sed -e 's:.*:$(SRC)/client/js/&.js:') \
		--js_output_file=$@ --compilation_level=ADVANCED_OPTIMIZATIONS \
		--process_common_js_modules --common_js_entry_module=$* \
		--common_js_module_path_prefix=$(SRC)/client/js \
		--externs=$(SRC)/util/closure_externs.js


# Rules for building the server

$(BUILD_NATIVE)/backend: $(SRC)/server/main.rs \
		$(foreach dep,$(DEPS_backend),$(BUILD_NATIVE)/lib$(dep).rlib)
	$(RUSTC) $< --out-dir $(BUILD_NATIVE) $(RUSTFLAGS_native) $(RUSTFLAGS_extra_libdir) \
		$(RELEASE_RUSTFLAGS_lto) --emit=link,dep-info
		


# Rules for building the server wrapper

# Running without this option seems to cause segfaults.
WRAPPER_CXXFLAGS = -DWEBSOCKETPP_STRICT_MASKING $(CXXFLAGS)

$(BUILD_NATIVE)/wrapper_objs/%.o: $(SRC)/wrapper/%.cpp $(wildcard $(SRC)/wrapper/*.hpp)
	$(CXX) -c $< -o $@ -std=c++14 $(WRAPPER_CXXFLAGS) $(RELEASE_CXXFLAGS_opt)

WRAPPER_SRCS = $(wildcard $(SRC)/wrapper/*.cpp)
WRAPPER_OBJS = $(patsubst $(SRC)/wrapper/%.cpp,$(BUILD_NATIVE)/wrapper_objs/%.o,$(WRAPPER_SRCS))

$(BUILD_NATIVE)/wrapper: $(WRAPPER_OBJS)
	$(CXX) $^ -o $@ -std=c++14 $(WRAPPER_CXXFLAGS) $(LDFLAGS) -lboost_system -lpthread -static


# Rules for building outpost_savegame python module

$(BUILD_NATIVE)/savegame_py/%.o: $(SRC)/util/savegame_py/%.c \
	$(wildcard $(SRC)/util/savegame_py/*.h)
	$(CC) -c $< -o $@ -std=c99 -fPIC -I$(PYTHON3_INC) $(RELEASE_CFLAGS_opt)

SAVEGAME_SRCS = $(wildcard $(SRC)/util/savegame_py/*.c)
SAVEGAME_OBJS = $(patsubst $(SRC)/util/savegame_py/%.c,$(BUILD_NATIVE)/savegame_py/%.o,$(SAVEGAME_SRCS))

$(BUILD_NATIVE)/outpost_savegame.so: $(SAVEGAME_OBJS)
	$(CC) $^ -o $@ -shared $(LDFLAGS)


# Rules for misc files

$(BUILD)/font.png \
$(BUILD)/metrics.json: \
		$(SRC)/util/process_font.py \
		$(SRC)/assets/misc/NeoSans.png
	$(PYTHON3) $(SRC)/util/process_font.py \
		--font-image-in=$(SRC)/assets/misc/NeoSans.png \
		--first-char=0x21 \
		--font-image-out=$(BUILD)/font.png \
		--font-metrics-out=$(BUILD)/metrics.json

$(BUILD)/%.debug.html: $(SRC)/client/%.html \
	$(SRC)/util/collect_js_deps.py $(SRC)/util/patch_script_tags.py $(JS_SRCS)
	$(PYTHON3) $(SRC)/util/collect_js_deps.py $< | \
		$(PYTHON3) $(SRC)/util/patch_script_tags.py $< >$@

$(BUILD)/credits.html: $(SRC)/util/gen_credits.py \
		$(SRC)/assets/used.txt \
		$(BUILD)/data/used_assets.txt
	cat $(SRC)/assets/used.txt $(BUILD)/data/used_assets.txt | \
		grep -vE '(\.frag|\.vert)$$' |\
		$(PYTHON3) $(SRC)/util/gen_credits.py >$@.tmp
	mv -v $@.tmp $@

$(BUILD)/server.json: $(SRC)/util/gen_server_json.py
	$(PYTHON3) $< >$@

$(BUILD)/day_night.json: $(SRC)/util/gen_day_night.py $(SRC)/assets/misc/day_night_pixels.png
	$(PYTHON3) $^ >$@


# Rules for client asset pack

# List of generated files that go in the client pack.  Does *not* include
# anything under $(BUILD)/data - those are handled by the dependency on
# $(BUILD)/data/stamp.
PACK_GEN_FILES = font.png metrics.json day_night.json

$(BUILD)/outpost.pack: \
		$(SRC)/util/make_pack.py \
		$(BUILD)/data/stamp \
		$(patsubst %,$(SRC)/assets/%,$(shell cat $(SRC)/assets/used.txt)) \
		$(foreach file,$(PACK_GEN_FILES),$(BUILD)/$(file))
	$(PYTHON3) $< $(SRC) $(BUILD) $@

$(BUILD)/data/stamp \
$(BUILD)/data/blocks_server.json \
$(BUILD)/data/structures_server.json \
$(BUILD)/data/items_server.json \
$(BUILD)/data/recipes_server.json: \
		$(shell find $(SRC)/data -name \*.py) \
		$(shell find $(SRC)/assets -name \*.png)
	mkdir -pv $(BUILD)/data
	rm -f $(BUILD)/data/structures*.png
	$(PYTHON3) $(SRC)/data/main.py $(SRC)/assets $(BUILD)/data
	touch $@


# Rules for copying files into dist/

define DIST_FILE_
$(DIST_$(1))/$(2): $(3)
	cp -v $$< $$@

$(DIST)/all: $(DIST_$(1))/$(2)
endef
BIN_FILE = $(call DIST_FILE_,BIN,$(strip $(1)),$(strip $(2)))
WWW_FILE = $(call DIST_FILE_,WWW,$(strip $(1)),$(strip $(2)))
DATA_FILE = $(call DIST_FILE_,DATA,$(strip $(1)),$(strip $(2)))
UTIL_FILE = $(call DIST_FILE_,UTIL,$(strip $(1)),$(strip $(2)))

$(eval $(call BIN_FILE,		run_server.sh,		$(SRC)/util/run_server.sh))
$(eval $(call BIN_FILE,		wrapper.py,			$(SRC)/server/wrapper.py))

$(eval $(call DATA_FILE, 	blocks.json,		$(BUILD)/data/blocks_server.json))
$(eval $(call DATA_FILE, 	items.json,			$(BUILD)/data/items_server.json))
$(eval $(call DATA_FILE, 	recipes.json,		$(BUILD)/data/recipes_server.json))
$(eval $(call DATA_FILE, 	structures.json,	$(BUILD)/data/structures_server.json))
$(eval $(call WWW_FILE, 	credits.html,		$(BUILD)/credits.html))
$(eval $(call WWW_FILE, 	instructions.html,	$(SRC)/client/instructions.html))
$(eval $(call WWW_FILE, 	server.json,		$(SRC)/build/server.json))
$(eval $(call WWW_FILE, 	outpost.pack,		$(BUILD)/outpost.pack))
$(eval $(call WWW_FILE, 	maresprite.png,		$(SRC)/assets/sprites/maresprite.png))
$(eval $(call UTIL_FILE,	outpost_savegame.so,	$(BUILD_NATIVE)/outpost_savegame.so))
$(eval $(call UTIL_FILE,	render_map.py, 		$(SRC)/util/render_map.py))
$(eval $(call UTIL_FILE,	map.tmpl.html, 		$(SRC)/util/map.tmpl.html))

ifeq ($(RELEASE),)
$(eval $(call WWW_FILE, client.html, 		$(BUILD)/client.debug.html))
$(eval $(call WWW_FILE, animtest.html, 		$(BUILD)/animtest.debug.html))
$(eval $(call WWW_FILE, configedit.html, 	$(BUILD)/configedit.debug.html))
$(eval $(call WWW_FILE, shim.js, 			$(SRC)/client/shim.js))
$(eval $(call WWW_FILE, asmlibs.js, 		$(BUILD_ASMLIBS)/asmlibs.js))
$(shell mkdir -p $(DIST_WWW)/js)
dist/all: $(patsubst $(SRC)/client/js/%,$(DIST_WWW)/js/%,$(JS_SRCS))
else
$(eval $(call WWW_FILE, client.html, 		$(SRC)/client/client.html))
$(eval $(call WWW_FILE, outpost.js, 		$(BUILD_MIN)/outpost.js))
$(eval $(call WWW_FILE, animtest.html, 		$(SRC)/client/animtest.html))
$(eval $(call WWW_FILE, animtest.js, 		$(BUILD_MIN)/animtest.js))
$(eval $(call WWW_FILE, configedit.html, 	$(SRC)/client/configedit.html))
$(eval $(call WWW_FILE, configedit.js, 		$(BUILD_MIN)/configedit.js))
$(eval $(call WWW_FILE, asmlibs.js, 		$(BUILD_MIN)/asmlibs.js))
endif

$(DIST)/all: \
	$(patsubst scripts/%,$(DIST)/scripts/%,$(shell find scripts -name \*.lua))

$(DIST)/scripts/%: $(SRC)/scripts/%
	mkdir -p $$(dirname $@)
	cp -v $< $@

$(DIST_WWW)/js/%: $(SRC)/client/js/%
	mkdir -p $$(dirname $@)
	cp -v $< $@

$(DIST_BIN)/backend: $(BUILD_NATIVE)/backend
	rm -fv $@
	cp -v $< $@

$(DIST_BIN)/wrapper: $(BUILD_NATIVE)/wrapper
	rm -fv $@
	cp -v $< $@

$(DIST)/all: $(DIST_BIN)/backend $(DIST_BIN)/wrapper

.PHONY: all clean $(DIST)/all
