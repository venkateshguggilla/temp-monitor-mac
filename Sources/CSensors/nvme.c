#include "CSensors.h"
#include <IOKit/IOCFPlugIn.h>

// Private IONVMeFamily SMART plug-in (the interface smartmontools uses on macOS).
#define kIONVMeSMARTUserClientTypeID CFUUIDGetConstantUUIDWithBytes(NULL, \
    0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)
#define kIONVMeSMARTInterfaceID CFUUIDGetConstantUUIDWithBytes(NULL, \
    0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, 0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)

typedef struct {
    IUNKNOWN_C_GUTS;
    UInt16 version;
    UInt16 revision;
    IOReturn (*SMARTReadData)(void *self, uint8_t *log512);
} IONVMeSMARTInterface;

int nvme_smart_read(io_service_t device, int *composite, int sensors[8], int *percent_used) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    if (IOCreatePlugInInterfaceForService(device, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID,
                                          &plugin, &score) != KERN_SUCCESS || !plugin)
        return -1;

    IONVMeSMARTInterface **smart = NULL;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
    if (hr != S_OK || !smart) { IODestroyPlugInInterface(plugin); return -1; }

    // NVMe "SMART / Health Information" log page: temperatures are little-endian Kelvin.
    uint8_t log[512] = {0};
    IOReturn r = (*smart)->SMARTReadData(smart, log);
    (*smart)->Release(smart);
    IODestroyPlugInInterface(plugin);
    if (r != kIOReturnSuccess) return -1;

    int kelvin = log[1] | (log[2] << 8);
    if (kelvin == 0) return -1;
    *composite = kelvin - 273;
    for (int i = 0; i < 8; i++) {
        int k = log[200 + 2 * i] | (log[201 + 2 * i] << 8);
        sensors[i] = k ? k - 273 : 0;
    }
    *percent_used = log[5];
    return 0;
}
