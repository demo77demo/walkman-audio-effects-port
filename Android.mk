LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := libwalkmanaudioeffect
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := src/effect.cpp
LOCAL_C_INCLUDES := $(LOCAL_PATH)/include
LOCAL_SHARED_LIBRARIES := liblog
LOCAL_EXPORT_C_INCLUDE_DIRS := $(LOCAL_PATH)/include

include $(BUILD_SHARED_LIBRARY)
