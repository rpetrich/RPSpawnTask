LIBRARY_NAME = test

test_FILES = RPSpawnTask.m
test_FRAMEWORKS = Foundation

THEOS_IPHONEOS_DEPLOYMENT_VERSION = 4.0

include framework/makefiles/common.mk
include framework/makefiles/library.mk
