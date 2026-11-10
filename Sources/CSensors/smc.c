#include "CSensors.h"
#include <string.h>

// Layout of the AppleSMC user-client struct (80 bytes), as used by every SMC tool.
typedef struct { char major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    char result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCGetKeyFromIndex = 8, kSMCGetKeyInfo = 9 };

static io_connect_t conn = 0;

static uint32_t key_to_u32(const char *k) {
    return ((uint32_t)(uint8_t)k[0] << 24) | ((uint32_t)(uint8_t)k[1] << 16) |
           ((uint32_t)(uint8_t)k[2] << 8) | (uint32_t)(uint8_t)k[3];
}

static void u32_to_key(uint32_t v, char out[5]) {
    out[0] = (char)(v >> 24); out[1] = (char)(v >> 16); out[2] = (char)(v >> 8); out[3] = (char)v; out[4] = 0;
}

static int smc_call(SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    kern_return_t kr = IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, in, sizeof(SMCParam), out, &outSize);
    return (kr == KERN_SUCCESS && out->result == 0) ? 0 : -1;
}

int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) { conn = 0; return -1; }
    return 0;
}

void smc_close(void) {
    if (conn) { IOServiceClose(conn); conn = 0; }
}

static int key_info(uint32_t key, SMCKeyInfo *info) {
    SMCParam in = {0}, out = {0};
    in.key = key;
    in.data8 = kSMCGetKeyInfo;
    if (smc_call(&in, &out)) return -1;
    *info = out.keyInfo;
    return 0;
}

int smc_read(const char *key, char type[5], uint8_t bytes[32], uint32_t *size) {
    if (!conn || strlen(key) != 4) return -1;
    uint32_t k = key_to_u32(key);
    SMCKeyInfo info;
    if (key_info(k, &info)) return -1;
    SMCParam in = {0}, out = {0};
    in.key = k;
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = kSMCReadKey;
    if (smc_call(&in, &out)) return -1;
    u32_to_key(info.dataType, type);
    *size = info.dataSize > 32 ? 32 : info.dataSize;
    memcpy(bytes, out.bytes, 32);
    return 0;
}

int smc_key_count(uint32_t *count) {
    char type[5]; uint8_t b[32]; uint32_t size;
    if (smc_read("#KEY", type, b, &size) || size < 4) return -1;
    *count = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
    return 0;
}

int smc_key_at(uint32_t index, char out[5]) {
    if (!conn) return -1;
    SMCParam in = {0}, res = {0};
    in.data8 = kSMCGetKeyFromIndex;
    in.data32 = index;
    if (smc_call(&in, &res)) return -1;
    u32_to_key(res.key, out);
    return 0;
}
