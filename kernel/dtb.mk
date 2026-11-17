# SPDX-License-Identifier: Apache-2.0
#
# DTB for the inline Kleaf 6.6 kernel.
#
# The MGK Kleaf build produces dash.dtb from dash.dts, which is /plugin/ — an
# overlay of fragment@ nodes, not a full tree the bootloader can read. Use the
# known-good flow instead (same as the kernel's build-dtb.sh):
#
#   xiaomi_mt6991_common.dts -> base.dtb  (dtc -@)
#   dash.dts                 -> dash.dtbo (dtc -@)
#   base + overlay           -> merged    (fdtoverlay)
#   merged                   -> +mbox-attr (fdtput, stock mailbox IRQ fix)
#   merged                   -> dtb.img   (64-byte MTK LK wrapper)
#
# The result is seeded into KERNEL_OUT/dtb.img after the kernel build, and
# Evolution X's own rule copies it into dtb.img.

DASH_KERNEL_OBJ := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
DASH_DTB_TARGET := $(PRODUCT_OUT)/dtb.img

DASH_KERNEL_PLATFORM := kernel/platform/kernel-$(TARGET_KERNEL_VERSION)
DASH_DEVMOD := $(DASH_KERNEL_PLATFORM)/kernel_device_modules-6.6
DASH_KERNEL_SRC := $(DASH_KERNEL_PLATFORM)/kernel-6.6
DASH_DTS := $(DASH_DEVMOD)/arch/arm64/boot/dts

DASH_DTB_INTERMEDIATES := $(call intermediates-dir-for,PACKAGING,dash_dtb)
DASH_DTB_BASE := $(DASH_DTB_INTERMEDIATES)/base.dtb
DASH_DTB_OVERLAY_SRC := $(DASH_DTB_INTERMEDIATES)/dash-with-align.dts
DASH_DTB_OVERLAY := $(DASH_DTB_INTERMEDIATES)/dash.dtbo
DASH_DTB_MERGED := $(DASH_DTB_INTERMEDIATES)/dash-merged.dtb
DASH_DTB_WRAPPER := $(LOCAL_PATH)/kernel/mtk_dtb_header.py
DASH_DTB_ALIGN := $(LOCAL_PATH)/kernel/dash-align.dtsi

DASH_DTC := $(HOST_OUT_EXECUTABLES)/dtc
DASH_FDTOVERLAY := $(HOST_OUT_EXECUTABLES)/fdtoverlay
DASH_FDTPUT := $(HOST_OUT_EXECUTABLES)/fdtput
DASH_DTB_CPP := $(lastword $(sort $(wildcard \
    $(DASH_KERNEL_PLATFORM)/prebuilts/clang/host/linux-x86/clang-r*/bin/clang)))

DASH_CPP_FLAGS := -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp
DASH_CPP_INC := -I$(DASH_DTS) -I$(DASH_DTS)/mediatek \
    -I$(DASH_DEVMOD)/include -I$(DASH_KERNEL_SRC)/include -I$(LOCAL_PATH)/kernel
DASH_DTC_FLAGS := -I dts -O dtb -@ -Wno-unit_address_vs_reg

$(DASH_DTB_BASE): $(DASH_DTS)/mediatek/xiaomi_mt6991_common.dts $(DASH_DTC)
	@mkdir -p $(dir $@)
	@$(DASH_DTB_CPP) $(DASH_CPP_FLAGS) $(DASH_CPP_INC) $< | \
	    $(DASH_DTC) $(DASH_DTC_FLAGS) -o $@ -
	@echo "DTB: base <- xiaomi_mt6991_common.dts ($(stat -c %s $@) bytes)"

# The CCC dash.dts lacks MewType's dash-align.dtsi include. Append it to a
# generated copy so the overlay pins the proven-boot tuning values.
$(DASH_DTB_OVERLAY_SRC): $(DASH_DTS)/mediatek/dash.dts $(DASH_DTB_ALIGN)
	@mkdir -p $(dir $@)
	@cp -f $< $@
	@printf '\n#include "dash-align.dtsi"\n' >> $@

$(DASH_DTB_OVERLAY): $(DASH_DTB_OVERLAY_SRC) $(DASH_DTC)
	@mkdir -p $(dir $@)
	@$(DASH_DTB_CPP) $(DASH_CPP_FLAGS) $(DASH_CPP_INC) $< | \
	    $(DASH_DTC) $(DASH_DTC_FLAGS) -o $@ -
	@echo "DTB: overlay <- dash.dts + dash-align.dtsi ($(stat -c %s $@) bytes)"

$(DASH_DTB_MERGED): $(DASH_DTB_BASE) $(DASH_DTB_OVERLAY) $(DASH_FDTOVERLAY) $(DASH_FDTPUT)
	@$(DASH_FDTOVERLAY) -i $(DASH_DTB_BASE) -o $@ $(DASH_DTB_OVERLAY)
	@$(DASH_FDTPUT) -t x $@ /soc/gpueb@4b000000 mbox-attr 0
	@$(DASH_FDTPUT) -t x $@ /scp@1c800000 mbox-attr 0 0 0 0 0 0
	@$(DASH_FDTPUT) -t x $@ /vcp@31800000 mbox-attr 0 0 0
	@$(DASH_FDTPUT) -t x $@ /mmup@31a00000 mbox-attr 0 0
	@echo "DTB: merged + mbox-attr ($(stat -c %s $@) bytes)"

# Real file target (not PHONY): Kati rejects a real file depending on PHONY.
$(DASH_KERNEL_OBJ)/dtb.img: $(DASH_DTB_MERGED) $(DASH_DTB_WRAPPER) $(DASH_KERNEL_OBJ)/$(BOARD_KERNEL_IMAGE_NAME)
	@mkdir -p $(dir $@)
	@cp -f $(DASH_DTB_MERGED) $@
	@python3 $(DASH_DTB_WRAPPER) $@
	@magic=$$(dd if=$@ bs=1 skip=64 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n'); \
	    test "$$magic" = "d00dfeed" || \
	    { echo "ERROR: wrapped DTB has no FDT at offset 64 (got $$magic)" >&2; exit 1; }
	@echo "DTB: $@ ($(stat -c %s $@) bytes, LK header wrapped)"

$(DASH_DTB_TARGET): $(DASH_KERNEL_OBJ)/dtb.img
