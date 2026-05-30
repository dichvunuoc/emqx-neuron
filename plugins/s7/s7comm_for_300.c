/**
 * NEURON IIoT System for Industry 4.0
 **/

#include <neuron.h>

#include "s7_plugin.h"

static neu_plugin_t *driver_open(void)
{
    neu_plugin_t *plugin = s7_driver_open(S7_VARIANT_300);
    if (plugin != NULL) {
        plugin->slot = 2;
    }
    return plugin;
}

static const neu_plugin_intf_funs_t plugin_intf_funs = {
    .open               = driver_open,
    .close              = s7_driver_close,
    .init               = s7_driver_init,
    .uninit             = s7_driver_uninit,
    .start              = s7_driver_start,
    .stop               = s7_driver_stop,
    .setting            = s7_driver_config,
    .request            = s7_driver_request,
    .try_connect        = s7_driver_try_connect,
    .driver.validate_tag     = s7_driver_validate_tag,
    .driver.group_timer      = s7_driver_group_timer,
    .driver.group_sync       = s7_driver_group_timer,
    .driver.write_tag        = s7_driver_write,
    .driver.write_tags       = s7_driver_write_tags,
    .driver.test_read_tag    = s7_driver_test_read_tag,
};

const neu_plugin_module_t neu_plugin_module = {
    .version         = NEURON_PLUGIN_VER_1_0,
    .schema          = "s7comm_for_300",
    .module_name     = "Siemens S7 ISOTCP for 300/400",
    .module_descr    =
        "Open-source Siemens S7 ISOTCP driver for S7-300/400 PLCs (Snap7).",
    .module_descr_zh =
        "开源 Siemens S7 ISOTCP 南向驱动（Snap7），用于 S7-300/400 PLC。",
    .intf_funs       = &plugin_intf_funs,
    .kind            = NEU_PLUGIN_KIND_SYSTEM,
    .type            = NEU_NA_TYPE_DRIVER,
    .display         = true,
    .single          = false,
};
