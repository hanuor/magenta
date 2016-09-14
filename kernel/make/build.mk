# Copyright 2016 The Fuchsia Authors
# Copyright (c) 2008-2015 Travis Geiselbrecht
#
# Use of this source code is governed by a MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT

# use linker garbage collection, if requested
ifeq ($(WITH_LINKER_GC),1)
GLOBAL_COMPILEFLAGS += -ffunction-sections -fdata-sections
GLOBAL_LDFLAGS += --gc-sections
endif

ifneq (,$(EXTRA_BUILDRULES))
-include $(EXTRA_BUILDRULES)
endif

# enable/disable the size output based on the ENABLE_BUILD_LISTFILES switch
ifeq ($(call TOBOOL,$(ENABLE_BUILD_LISTFILES)),true)
SIZECMD:=$(SIZE)
else
SIZECMD:=true
endif

$(OUTLKBIN): $(OUTLKELF)
	@echo generating image: $@
#	$(NOECHO)$(OBJCOPY) -O binary $< $@

$(OUTLKELF).hex: $(OUTLKELF)
	@echo generating hex file: $@
#	$(NOECHO)$(OBJCOPY) -O ihex $< $@

$(OUTLKELF): $(ALLMODULE_OBJS) $(EXTRA_OBJS) $(LINKER_SCRIPT)
	@echo linking $@
#	$(NOECHO)$(LD) $(GLOBAL_LDFLAGS) -dT $(LINKER_SCRIPT) \
		$(ALLMODULE_OBJS) $(EXTRA_OBJS) $(LIBGCC) -o $@
#	$(NOECHO)$(SIZECMD) -t --common $(sort $(ALLMODULE_OBJS)) $(EXTRA_OBJS)
#	$(NOECHO)$(SIZECMD) $@

$(OUTLKELF).sym: $(OUTLKELF)
	@echo generating symbols: $@
#	$(NOECHO)$(OBJDUMP) -t $< | $(CPPFILT) > $@

$(OUTLKELF).sym.sorted: $(OUTLKELF)
	@echo generating sorted symbols: $@
#	$(NOECHO)$(OBJDUMP) -t $< | $(CPPFILT) | sort > $@

$(OUTLKELF).lst: $(OUTLKELF)
	@echo generating listing: $@
#	$(NOECHO)$(OBJDUMP) $(OBJDUMP_LIST_FLAGS) -d $< | $(CPPFILT) > $@

$(OUTLKELF).debug.lst: $(OUTLKELF)
	@echo generating listing: $@
#	$(NOECHO)$(OBJDUMP) $(OBJDUMP_LIST_FLAGS) -S $< | $(CPPFILT) > $@

$(OUTLKELF).dump: $(OUTLKELF)
	@echo generating objdump: $@
#	$(NOECHO)$(OBJDUMP) -x $< > $@

$(OUTLKELF).size: $(OUTLKELF)
	@echo generating size map: $@
#	$(NOECHO)$(NM) -S --size-sort $< > $@

$(OUTLKELF)-gdb.py: scripts/$(LKNAME).elf-gdb.py
	@echo generating $@
#	$(NOECHO)cp -f $< $@

# print some information about the build
#$(BUILDDIR)/srcfiles.txt:
#	@echo generating $@
#	$(NOECHO)echo $(sort $(ALLSRCS)) | tr ' ' '\n' > $@
#
#.PHONY: $(BUILDDIR)/srcfiles.txt
#GENERATED += $(BUILDDIR)/srcfiles.txt
#
#$(BUILDDIR)/include-paths.txt:
#	@echo generating $@
#	$(NOECHO)echo $(subst -I,,$(sort $(GLOBAL_INCLUDES))) | tr ' ' '\n' > $@
#
#.PHONY: $(BUILDDIR)/include-paths.txt
#GENERATED += $(BUILDDIR)/include-paths.txt
#
#.PHONY: $(BUILDDIR)/user-include-paths.txt
#GENERATED += $(BUILDDIR)/user-include-paths.txt

# userspace app build rule
# NOTE: another rule in engine.mk adds additional deps to individual .elf files
# so they will be reflected in the $^ expansion of the link line
$(BUILDDIR)/%.elf:: $(BUILDDIR)/%.mod.o $(USER_LINKER_SCRIPT)
	@echo linking $@
#	$(NOECHO)$(LD) $(GLOBAL_LDFLAGS) -T $(USER_LINKER_SCRIPT) $(ARCH_LDFLAGS) \
		$(filter-out $(USER_LINKER_SCRIPT),$^) $(LIBGCC) -o $@

$(BUILDDIR)/%.elf.dump: $(BUILDDIR)/%.elf
	@echo generating $@
#	$(NOECHO)$(OBJDUMP) -x $< > $@

$(BUILDDIR)/%.elf.lst: $(BUILDDIR)/%.elf
	@echo generating $@
#	$(NOECHO)$(OBJDUMP) $(OBJDUMP_LIST_FLAGS) -d $< > $@

$(BUILDDIR)/%.elf.strip: $(BUILDDIR)/%.elf
	@echo generating $@
#	$(NOECHO)$(STRIP) -d $< -o $@

# generate a new manifest and compare to see if it differs from the previous one
.PHONY: usermanifestfile
$(USER_MANIFEST): usermanifestfile
	@echo generating $@
#	$(NOECHO)echo $(USER_MANIFEST_LINES) | tr ' ' '\n' | sort > $@.tmp
#	$(NOECHO)$(call TESTANDREPLACEFILE,$@.tmp,$@)

GENERATED += $(USER_MANIFEST)

# build useful tools
MKBOOTFS := $(BUILDDIR)/tools/mkbootfs
BOOTSERVER := $(BUILDDIR)/tools/bootserver
LOGLISTENER := $(BUILDDIR)/tools/loglistener

$(BUILDDIR)/tools/%: system/tools/%.c
	@echo compiling $@
	@$(MKDIR)
	$(NOECHO)cc -Wall -o $@ $<

GENERATED += $(MKBOOTFS) $(BOOTSERVER) $(LOGLISTENER)

# Manifest Lines are bootfspath=buildpath
# Extract the part after the = for each line
# to generate dependencies
USER_MANIFEST_DEPS := $(foreach x,$(USER_MANIFEST_LINES),$(lastword $(subst =,$(SPACE),$(strip $(x)))))

$(USER_BOOTFS): $(MKBOOTFS) $(BOOTSERVER) $(LOGLISTENER) $(USER_MANIFEST) $(USER_MANIFEST_DEPS)
	@echo generating $@
#	@$(MKDIR)
#	$(NOECHO)$(MKBOOTFS) -o $(USER_BOOTFS) $(USER_MANIFEST)

GENERATED += $(USER_BOOTFS)

# build userspace filesystem image
$(USER_FS): $(USER_BOOTFS)
	@echo generating $@
#	$(NOECHO)dd if=/dev/zero of=$@ bs=1048576 count=16
#	$(NOECHO)dd if=$(USER_BOOTFS) of=$@ conv=notrunc

# add the fs image to the clean list
GENERATED += $(USER_FS)
