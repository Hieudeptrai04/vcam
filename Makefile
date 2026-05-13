# VcamFullMay — top-level Theos build file (rootless).
#
# Builds tweak + companion app. App is a subproject under App/.
#
# Build:    THEOS_PACKAGE_SCHEME=rootless make package FINALPACKAGE=1
# Install:  scp packages/*.deb <ip>:/tmp && ssh root@<ip> dpkg -i /tmp/*.deb

PACKAGE_VERSION = 1.0.0
ARCHS = arm64 arm64e

TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VcamFullMay
VcamFullMay_FILES   = Tweak.xm
VcamFullMay_CFLAGS  = -fobjc-arc -Wno-deprecated-declarations -Wno-error
VcamFullMay_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo CoreGraphics
VcamFullMay_LDFLAGS    = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += App
include $(THEOS_MAKE_PATH)/aggregate.mk

# Refresh SpringBoard icon cache after install so VCam icon shows up.
after-install::
	install.exec "uicache -p /var/jb/Applications/VcamApp.app || uicache --all || true"
