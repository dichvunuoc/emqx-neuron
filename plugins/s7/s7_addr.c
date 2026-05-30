/**
 * NEURON IIoT System for Industry 4.0
 **/

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "s7_addr.h"

/* Snap7 constants (avoid snap7.h here; conflicts with stdbool in neuron.h). */
#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
#define NEU_S7_AREA_PE    0x81
#define NEU_S7_AREA_PA    0x82
#define NEU_S7_AREA_MK    0x83
#define NEU_S7_AREA_DB    0x84
#define NEU_S7_AREA_CT    0x1C
#define NEU_S7_AREA_TM    0x1D
#define NEU_S7_WL_BIT     0x01
#define NEU_S7_WL_BYTE    0x02
#define NEU_S7_WL_WORD    0x04
#define NEU_S7_WL_DWORD   0x06
#define NEU_S7_WL_COUNTER 0x1C
#define NEU_S7_WL_TIMER   0x1D
#endif

static int area_writable(s7_area_kind_e area)
{
    switch (area) {
    case S7_AREA_I:
        return false;
    case S7_AREA_O:
    case S7_AREA_Q:
    case S7_AREA_F:
    case S7_AREA_M:
    case S7_AREA_T:
    case S7_AREA_C:
    case S7_AREA_DB:
        return true;
    }
    return false;
}

static int snap7_area_id(s7_area_kind_e area)
{
#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
    switch (area) {
    case S7_AREA_I:
        return NEU_S7_AREA_PE;
    case S7_AREA_O:
    case S7_AREA_Q:
        return NEU_S7_AREA_PA;
    case S7_AREA_F:
    case S7_AREA_M:
        return NEU_S7_AREA_MK;
    case S7_AREA_T:
        return NEU_S7_AREA_TM;
    case S7_AREA_C:
        return NEU_S7_AREA_CT;
    case S7_AREA_DB:
        return NEU_S7_AREA_DB;
    }
#endif
    return -1;
}

static int type_byte_size(neu_type_e type, int str_len, bool wide)
{
    switch (type) {
    case NEU_TYPE_BIT:
        return 1;
    case NEU_TYPE_INT8:
    case NEU_TYPE_UINT8:
        return 1;
    case NEU_TYPE_INT16:
    case NEU_TYPE_UINT16:
    case NEU_TYPE_WORD:
        return 2;
    case NEU_TYPE_INT32:
    case NEU_TYPE_UINT32:
    case NEU_TYPE_FLOAT:
    case NEU_TYPE_DWORD:
        return 4;
    case NEU_TYPE_INT64:
    case NEU_TYPE_UINT64:
    case NEU_TYPE_DOUBLE:
    case NEU_TYPE_LWORD:
        return 8;
    case NEU_TYPE_STRING:
    case NEU_TYPE_ARRAY_CHAR:
        return str_len > 0 ? str_len + 2 : 0;
    case NEU_TYPE_BOOL:
        return 1;
    default:
        return 0;
    }
    (void) wide;
}

static int snap7_word_len(neu_type_e type, bool is_bit, bool is_timer,
                          bool is_counter)
{
#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
    if (is_bit) {
        return NEU_S7_WL_BIT;
    }
    if (is_timer) {
        return NEU_S7_WL_TIMER;
    }
    if (is_counter) {
        return NEU_S7_WL_COUNTER;
    }
    switch (type) {
    case NEU_TYPE_BIT:
        return NEU_S7_WL_BIT;
    case NEU_TYPE_INT8:
    case NEU_TYPE_UINT8:
        return NEU_S7_WL_BYTE;
    case NEU_TYPE_INT16:
    case NEU_TYPE_UINT16:
    case NEU_TYPE_WORD:
        return NEU_S7_WL_WORD;
    case NEU_TYPE_INT32:
    case NEU_TYPE_UINT32:
    case NEU_TYPE_FLOAT:
    case NEU_TYPE_DWORD:
        return NEU_S7_WL_DWORD;
    case NEU_TYPE_INT64:
    case NEU_TYPE_UINT64:
    case NEU_TYPE_DOUBLE:
    case NEU_TYPE_LWORD:
        return NEU_S7_WL_DWORD;
    case NEU_TYPE_STRING:
    case NEU_TYPE_ARRAY_CHAR:
        return NEU_S7_WL_BYTE;
    case NEU_TYPE_BOOL:
        return NEU_S7_WL_BYTE;
    default:
        return -1;
    }
#else
    (void) type;
    (void) is_bit;
    (void) is_timer;
    (void) is_counter;
    return 1;
#endif
}

static int parse_area_letter(char c, s7_area_kind_e *area)
{
    switch (toupper((unsigned char) c)) {
    case 'I':
        *area = S7_AREA_I;
        return 0;
    case 'O':
        *area = S7_AREA_O;
        return 0;
    case 'Q':
        *area = S7_AREA_Q;
        return 0;
    case 'F':
        *area = S7_AREA_F;
        return 0;
    case 'M':
        *area = S7_AREA_M;
        return 0;
    case 'T':
        *area = S7_AREA_T;
        return 0;
    case 'C':
        *area = S7_AREA_C;
        return 0;
    default:
        return -1;
    }
}

static int parse_db_address(const char *addr, s7_parsed_addr_t *out,
                            neu_type_e type)
{
    int    db  = 0;
    int    off = 0;
    char   suffix[8] = { 0 };
    char * dot       = NULL;
    char * end       = NULL;

    if (strncasecmp(addr, "DB", 2) != 0) {
        return -1;
    }

    db = (int) strtol(addr + 2, &end, 10);
    if (end == NULL || *end != '.') {
        return -1;
    }

    if (strncasecmp(end + 1, "DBW", 3) != 0 && strncasecmp(end + 1, "DBB", 3) != 0 &&
        strncasecmp(end + 1, "DBD", 3) != 0) {
        return -1;
    }

    strncpy(suffix, end + 1, sizeof(suffix) - 1);
    off = (int) strtol(end + 4, &dot, 10);
    if (dot != NULL && dot[0] == '.') {
        if (type == NEU_TYPE_BIT || strchr(dot + 1, '.') == NULL) {
            out->has_bit = true;
            out->bit     = (int) strtol(dot + 1, NULL, 10);
        } else {
            char *len_end = NULL;
            out->str_len = (int) strtol(dot + 1, &len_end, 10);
            if (len_end != NULL && toupper((unsigned char) *len_end) == 'D') {
                out->wide_str = true;
            }
        }
    }

    out->area      = S7_AREA_DB;
    out->db_number = db;
    out->start     = off;
    out->writable  = true;
    return 0;
}

int s7_addr_parse(const char *address, neu_type_e type, s7_parsed_addr_t *out)
{
    char              buf[256] = { 0 };
    char *            p        = NULL;
    s7_area_kind_e    area     = S7_AREA_I;
    int               off      = 0;
    char *            dot      = NULL;

    if (address == NULL || out == NULL) {
        return -1;
    }

    memset(out, 0, sizeof(*out));
    strncpy(buf, address, sizeof(buf) - 1);

    for (p = buf; *p; p++) {
        *p = (char) toupper((unsigned char) *p);
    }
    p = buf;

    if (strncasecmp(p, "DB", 2) == 0) {
        if (parse_db_address(p, out, type) != 0) {
            return -1;
        }
    } else {
        if (parse_area_letter(p[0], &area) != 0) {
            return -1;
        }
        off = (int) strtol(p + 1, &dot, 10);
        out->area     = area;
        out->start    = off;
        out->writable = area_writable(area);
        if (dot != NULL && dot[0] == '.') {
            if (type == NEU_TYPE_BIT) {
                out->has_bit = true;
                out->bit     = (int) strtol(dot + 1, NULL, 10);
            } else {
                char *len_end = NULL;
                out->str_len = (int) strtol(dot + 1, &len_end, 10);
                if (len_end != NULL && *len_end == 'D') {
                    out->wide_str = true;
                }
            }
        }
    }

    out->amount = type_byte_size(type, out->str_len, out->wide_str);
    if (out->amount <= 0 && type != NEU_TYPE_BIT) {
        return -1;
    }

    if (type == NEU_TYPE_BIT && !out->has_bit) {
        out->has_bit = true;
        out->bit     = 0;
    }

    if (out->wide_str && out->str_len > 0) {
        out->amount = out->str_len * 2 + 2;
    }

    out->word_len = snap7_word_len(type, out->has_bit, out->area == S7_AREA_T,
                                  out->area == S7_AREA_C);
    if (out->word_len < 0) {
        return -1;
    }

    if (out->has_bit) {
        out->start  = out->start * 8 + out->bit;
        out->amount = 1;
    } else if (out->area == S7_AREA_T || out->area == S7_AREA_C) {
        out->amount = 1;
    }

    (void) snap7_area_id;
    return 0;
}

int s7_addr_validate(const char *address, neu_type_e type)
{
    s7_parsed_addr_t addr = { 0 };
    return s7_addr_parse(address, type, &addr);
}
