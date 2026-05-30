/**
 * NEURON IIoT System for Industry 4.0
 **/

#ifndef NEU_PLUGIN_S7_PLUGIN_H
#define NEU_PLUGIN_S7_PLUGIN_H

#include <stdbool.h>
#include <stdint.h>

#include <neuron.h>

#include "s7_addr.h"

typedef enum {
    S7_VARIANT_COMM = 0,
    S7_VARIANT_300  = 1,
} s7_variant_e;

typedef struct neu_plugin neu_plugin_t;

struct neu_plugin {
    neu_plugin_common_t common;
    s7_variant_e        variant;
    char *              host;
    uint16_t            port;
    int                 pdu_size;
    int                 plc_type;
    int                 connection_type;
    int                 rack;
    int                 slot;
    uint16_t            local_tsap;
    uint16_t            remote_tsap;
    int                 t1;
    int                 t2;
    int                 t3;
    bool                started;
    bool                connected;
#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
    uintptr_t client;
#endif
};

int  s7_err_from_snap7(int snap7_err);
void s7_publish_err(neu_plugin_t *plugin, neu_plugin_group_t *group, int err);
int  s7_connect(neu_plugin_t *plugin);
void s7_disconnect(neu_plugin_t *plugin);
int  s7_read_tag(neu_plugin_t *plugin, const neu_datatag_t *tag,
                 neu_dvalue_t *out);
int  s7_write_tag(neu_plugin_t *plugin, const neu_datatag_t *tag,
                  neu_value_u value);
int  s7_group_read(neu_plugin_t *plugin, neu_plugin_group_t *group);

neu_plugin_t *s7_driver_open(s7_variant_e variant);
int           s7_driver_close(neu_plugin_t *plugin);
int           s7_driver_init(neu_plugin_t *plugin, bool load);
int           s7_driver_uninit(neu_plugin_t *plugin);
int           s7_driver_start(neu_plugin_t *plugin);
int           s7_driver_stop(neu_plugin_t *plugin);
int           s7_driver_config(neu_plugin_t *plugin, const char *config);
int           s7_driver_request(neu_plugin_t *plugin, neu_reqresp_head_t *head,
                                void *data);
int           s7_driver_try_connect(neu_plugin_t *plugin);
int           s7_driver_validate_tag(neu_plugin_t *plugin, neu_datatag_t *tag);
int           s7_driver_group_timer(neu_plugin_t *plugin,
                                    neu_plugin_group_t *group);
int           s7_driver_write(neu_plugin_t *plugin, void *req,
                              neu_datatag_t *tag, neu_value_u value);
int           s7_driver_write_tags(neu_plugin_t *plugin, void *req,
                                   UT_array *tags);
int           s7_driver_test_read_tag(neu_plugin_t *plugin, void *req,
                                      neu_datatag_t tag);

#endif
