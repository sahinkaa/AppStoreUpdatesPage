ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = AppStore

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AppStoreUpdatesPage
AppStoreUpdatesPage_FILES = Tweak.m
AppStoreUpdatesPage_CFLAGS = -fobjc-arc
AppStoreUpdatesPage_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
