// Launch Services checks Info.plist. Direct execution enters through dyld instead.
#import <Foundation/Foundation.h>
#include <AvailabilityMacros.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((constructor))
static void requireSupportedMacOS(void) {
    @autoreleasepool {
        const NSInteger target = MAC_OS_X_VERSION_MIN_REQUIRED;
        const NSOperatingSystemVersion minimum = {target / 10000, target / 100 % 100, target % 100};
        if (![NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimum]) {
            fprintf(stderr, "YEN requires macOS %ld.%ld or later.\n", (long)minimum.majorVersion, (long)minimum.minorVersion);
            exit(EXIT_FAILURE);
        }
    }
}
