/**
 * Include snap7 before stdbool (via neuron.h). snap7 typedefs bool as int.
 **/
#ifndef NEU_PLUGIN_S7_SNAP7_H
#define NEU_PLUGIN_S7_SNAP7_H

#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
#include <snap7.h>
#undef false
#undef true
#undef bool
#endif

#endif
