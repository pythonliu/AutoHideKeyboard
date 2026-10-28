TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoHideKeyboard
AutoHideKeyboard_FILES = Tweak.x
AutoHideKeyboard_CFLAGS = -fobjc-arc -Wno-error=unused-variable

include $(THEOS_MAKE_PATH)/tweak.mk
