# VcamFullMay — Virtual camera tweak Theos build file.
# Build with:  THEOS_PACKAGE_SCHEME=rootless make package
# Install:     make install THEOS_DEVICE_IP=<ip> THEOS_DEVICE_PORT=22

PACKAGE_VERSION = 1.0.0
ARCHS = arm64 arm64e

TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VcamFullMay
VcamFullMay_FILES   = Tweak.xm
VcamFullMay_CFLAGS  = -fobjc-arc -Wno-deprecated-declarations -Wno-error
# Frameworks the hook code references — all present in every iOS app's
# dyld shared cache (camera-capable apps already link these).
VcamFullMay_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo CoreGraphics
VcamFullMay_LDFLAGS    = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
