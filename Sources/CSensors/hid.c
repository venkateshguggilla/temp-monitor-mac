#include "CSensors.h"
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>

// Private IOHIDEventSystem API: the source of SoC temperatures on Apple Silicon.
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef, CFDictionaryRef);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef, CFStringRef);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
extern double IOHIDEventGetFloatValue(IOHIDEventRef, int32_t);

enum { kIOHIDEventTypeTemperature = 15 };

static IOHIDEventSystemClientRef client = NULL;

int hid_temperatures(char *names, double *values, int max) {
    if (!client) {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!client) return -1;
        int page = 0xff00, usage = 5; // AppleVendor / TemperatureSensor
        CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &page);
        CFNumberRef u = CFNumberCreate(NULL, kCFNumberIntType, &usage);
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        const void *vals[] = { p, u };
        CFDictionaryRef match = CFDictionaryCreate(NULL, keys, vals, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        IOHIDEventSystemClientSetMatching(client, match);
        CFRelease(match); CFRelease(p); CFRelease(u);
    }

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) return 0;
    int n = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(services) && n < max; i++) {
        IOHIDServiceClientRef svc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        IOHIDEventRef ev = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0);
        if (!ev) continue;
        double v = IOHIDEventGetFloatValue(ev, kIOHIDEventTypeTemperature << 16);
        CFRelease(ev);
        CFStringRef name = IOHIDServiceClientCopyProperty(svc, CFSTR("Product"));
        char *slot = names + n * 64;
        slot[0] = 0;
        if (name) {
            CFStringGetCString(name, slot, 64, kCFStringEncodingUTF8);
            CFRelease(name);
        }
        values[n++] = v;
    }
    CFRelease(services);
    return n;
}
