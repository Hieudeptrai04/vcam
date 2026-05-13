# Companion app — builds VcamApp.app and packages into /var/jb/Applications.

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = VcamApp
VcamApp_FILES = main.m VcamAppDelegate.m VcamViewController.m
VcamApp_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VcamApp_FRAMEWORKS = UIKit Foundation AVFoundation UniformTypeIdentifiers
VcamApp_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
