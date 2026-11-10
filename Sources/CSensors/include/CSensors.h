#ifndef CSENSORS_H
#define CSENSORS_H

#include <stdint.h>
#include <IOKit/IOKitLib.h>

// ---- SMC (System Management Controller) --------------------------------------
// All functions return 0 on success. Not thread-safe: call from one thread.

int smc_open(void);
void smc_close(void);
/// Number of keys the SMC exposes ("#KEY").
int smc_key_count(uint32_t *count);
/// Four-character key name at `index`, NUL-terminated into `out`.
int smc_key_at(uint32_t index, char out[5]);
/// Raw value of `key`. `type` receives the 4-char data type (e.g. "sp78", "flt ").
int smc_read(const char *key, char type[5], uint8_t bytes[32], uint32_t *size);

// ---- NVMe SMART --------------------------------------------------------------

/// Reads the NVMe SMART/health log from an IONVMeBlockStorageDevice service.
/// `composite` is the drive's own temperature in °C; `sensors` holds up to 8 extra
/// sensor readings in °C (0 = not implemented); `percent_used` is the wear estimate.
int nvme_smart_read(io_service_t device, int *composite, int sensors[8], int *percent_used);

// ---- HID temperature sensors (Apple Silicon) ---------------------------------

/// Fills up to `max` sensors: name i is at names + i*64 (63 chars + NUL), value i in °C.
/// Returns the count, or -1.
int hid_temperatures(char *names, double *values, int max);

#endif
