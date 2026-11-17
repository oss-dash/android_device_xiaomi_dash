# 
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
LOCAL_PATH := $(call my-dir)
include $(LOCAL_PATH)/kernel/dtb.mk
include kernel/platform/kernel-6.6/build/bazel_mgk_rules/android/modules.mk
