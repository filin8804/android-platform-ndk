LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE    := clang-atomic-macros
LOCAL_SRC_FILES := main.c
include $(BUILD_EXECUTABLE)
