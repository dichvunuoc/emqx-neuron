/**
 * NEURON IIoT System for Industry 4.0
 **/

#ifndef NEU_PLUGIN_S7_ADDR_H
#define NEU_PLUGIN_S7_ADDR_H

#include <stdbool.h>
#include <stdint.h>

#include <neuron.h>

typedef enum {
    S7_AREA_I = 0,
    S7_AREA_O,
    S7_AREA_Q,
    S7_AREA_F,
    S7_AREA_M,
    S7_AREA_T,
    S7_AREA_C,
    S7_AREA_DB,
} s7_area_kind_e;

typedef struct {
    s7_area_kind_e area;
    int            db_number;
    int            start;
    int            amount;
    int            word_len;
    int            bit;
    bool           has_bit;
    int            str_len;
    bool           wide_str;
    bool           writable;
} s7_parsed_addr_t;

int s7_addr_parse(const char *address, neu_type_e type, s7_parsed_addr_t *out);
int s7_addr_validate(const char *address, neu_type_e type);

#endif
