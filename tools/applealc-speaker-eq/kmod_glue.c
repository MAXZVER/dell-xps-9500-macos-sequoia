#include <mach/mach_types.h>

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);

extern kern_return_t AppleALC_kern_start(kmod_info_t *ki, void *data);
extern kern_return_t AppleALC_kern_stop(kmod_info_t *ki, void *data);

__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(as.vit9696.AppleALC, "1.9.7", _start, _stop)

__private_extern__ kmod_start_func_t *_realmain = AppleALC_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = AppleALC_kern_stop;
