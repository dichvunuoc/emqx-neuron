/**
 * NEURON IIoT System for Industry 4.0
 **/

#include <arpa/inet.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
#include "s7_snap7.h"
#endif

#include <neuron.h>

#include "s7_plugin.h"

#define S7_DEFAULT_SLOT 1

static int snap7_area_from_parsed(const s7_parsed_addr_t *addr)
{
#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
    switch (addr->area) {
    case S7_AREA_I:
        return S7AreaPE;
    case S7_AREA_O:
    case S7_AREA_Q:
        return S7AreaPA;
    case S7_AREA_F:
    case S7_AREA_M:
        return S7AreaMK;
    case S7_AREA_T:
        return S7AreaTM;
    case S7_AREA_C:
        return S7AreaCT;
    case S7_AREA_DB:
        return S7AreaDB;
    }
#endif
    (void) addr;
    return -1;
}

int s7_err_from_snap7(int snap7_err)
{
    if (snap7_err == 0) {
        return NEU_ERR_SUCCESS;
    }
    switch (snap7_err) {
    case 0x00010000:
    case 0x00020000:
        return NEU_ERR_S7COMM_COTP_DISCONNECTED;
    case 0x00100000:
        return NEU_ERR_S7COMM_DISCONNECTED;
    case 0x00900000:
        return NEU_ERR_S7COMM_INVALID_ADDRESS;
    case 0x00500000:
    case 0x00A00000:
        return NEU_ERR_S7COMM_TYPE_NOT_SUPPORTED;
    case 0x00D00000:
        return NEU_ERR_S7COMM_TYPE_INCONSISTENT;
    case 0x00C00000:
        return NEU_ERR_S7COMM_OBJECT_NOT_EXIST;
    case 0x02300000:
    case 0x01D00000:
        return NEU_ERR_S7COMM_ACCESS_DENIED;
    case 0x02200000:
        return NEU_ERR_S7COMM_VALUE_TOO_SHORT;
    default:
        if ((snap7_err & 0xFFF00000) == 0x00100000) {
            return NEU_ERR_S7COMM_DISCONNECTED;
        }
        return NEU_ERR_S7COMM_HARDWARE_ERROR;
    }
}

void s7_publish_err(neu_plugin_t *plugin, neu_plugin_group_t *group, int err)
{
    utarray_foreach(group->tags, neu_datatag_t *, tag)
    {
        neu_dvalue_t dvalue = { .type = NEU_TYPE_ERROR };
        dvalue.value.i32    = err;
        plugin->common.adapter_callbacks->driver.update(
            plugin->common.adapter, group->group_name, tag->name, dvalue);
    }
}

#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7

static int bytes_to_dvalue(const uint8_t *buf, int len, neu_type_e type,
                           bool is_bit, neu_dvalue_t *out)
{
    memset(out, 0, sizeof(*out));
    out->type = type;

    if (is_bit) {
        out->type       = NEU_TYPE_BIT;
        out->value.u8   = (buf[0] & 0x01) ? 1 : 0;
        return 0;
    }

    switch (type) {
    case NEU_TYPE_BIT:
        out->value.u8 = (buf[0] & 0x01) ? 1 : 0;
        break;
    case NEU_TYPE_BOOL:
        out->type        = NEU_TYPE_BOOL;
        out->value.boolean = buf[0] ? true : false;
        break;
    case NEU_TYPE_INT8:
        out->value.i8 = (int8_t) buf[0];
        break;
    case NEU_TYPE_UINT8:
        out->value.u8 = buf[0];
        break;
    case NEU_TYPE_INT16: {
        uint16_t be = 0;
        memcpy(&be, buf, 2);
        out->value.i16 = (int16_t) ntohs(be);
        break;
    }
    case NEU_TYPE_UINT16: {
        uint16_t be = 0;
        memcpy(&be, buf, 2);
        out->value.u16 = ntohs(be);
        break;
    }
    case NEU_TYPE_INT32: {
        uint32_t be = 0;
        memcpy(&be, buf, 4);
        out->value.i32 = (int32_t) ntohl(be);
        break;
    }
    case NEU_TYPE_UINT32: {
        uint32_t be = 0;
        memcpy(&be, buf, 4);
        out->value.u32 = ntohl(be);
        break;
    }
    case NEU_TYPE_FLOAT: {
        uint32_t be = 0;
        memcpy(&be, buf, 4);
        be = ntohl(be);
        memcpy(&out->value.f32, &be, sizeof(float));
        break;
    }
    case NEU_TYPE_DOUBLE: {
        uint64_t be = 0;
        if (len < 8) {
            return -1;
        }
        memcpy(&be, buf, 8);
        be = ((uint64_t) ntohl((uint32_t) (be >> 32)) << 32) |
             ntohl((uint32_t) be);
        memcpy(&out->value.d64, &be, sizeof(double));
        break;
    }
    case NEU_TYPE_STRING:
    case NEU_TYPE_ARRAY_CHAR: {
        int hdr = len >= 2 ? 2 : 0;
        int slen = len > hdr ? len - hdr : 0;
        if (slen >= NEU_VALUE_SIZE) {
            slen = NEU_VALUE_SIZE - 1;
        }
        memcpy(out->value.str, buf + hdr, slen);
        out->value.str[slen] = '\0';
        break;
    }
    default:
        return -1;
    }
    return 0;
}

static int dvalue_to_bytes(neu_type_e type, neu_value_u value, uint8_t *buf,
                           int buf_len)
{
    switch (type) {
    case NEU_TYPE_BIT:
        buf[0] = value.u8 ? 0x01 : 0x00;
        return 1;
    case NEU_TYPE_BOOL:
        buf[0] = value.boolean ? 0x01 : 0x00;
        return 1;
    case NEU_TYPE_INT8:
        buf[0] = (uint8_t) value.i8;
        return 1;
    case NEU_TYPE_UINT8:
        buf[0] = value.u8;
        return 1;
    case NEU_TYPE_INT16: {
        uint16_t be = htons((uint16_t) value.i16);
        memcpy(buf, &be, 2);
        return 2;
    }
    case NEU_TYPE_UINT16: {
        uint16_t be = htons(value.u16);
        memcpy(buf, &be, 2);
        return 2;
    }
    case NEU_TYPE_INT32: {
        uint32_t be = htonl((uint32_t) value.i32);
        memcpy(buf, &be, 4);
        return 4;
    }
    case NEU_TYPE_UINT32: {
        uint32_t be = htonl(value.u32);
        memcpy(buf, &be, 4);
        return 4;
    }
    case NEU_TYPE_FLOAT: {
        uint32_t raw = 0;
        memcpy(&raw, &value.f32, sizeof(float));
        raw = htonl(raw);
        memcpy(buf, &raw, 4);
        return 4;
    }
    case NEU_TYPE_STRING: {
        size_t slen = strnlen(value.str, NEU_VALUE_SIZE - 1);
        if (buf_len < (int) slen + 2) {
            return -1;
        }
        buf[0] = (uint8_t) slen;
        buf[1] = (uint8_t) slen;
        memcpy(buf + 2, value.str, slen);
        return (int) slen + 2;
    }
    default:
        return -1;
    }
}

#endif

void s7_disconnect(neu_plugin_t *plugin)
{
#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
    if (plugin->client != 0 && plugin->connected) {
        Cli_Disconnect((S7Object) plugin->client);
    }
#endif
    plugin->connected         = false;
    plugin->common.link_state = NEU_NODE_LINK_STATE_DISCONNECTED;
}

int s7_connect(neu_plugin_t *plugin)
{
#if !defined(NEU_S7_HAS_SNAP7) || !NEU_S7_HAS_SNAP7
    (void) plugin;
    return NEU_ERR_LIBRARY_NOT_FOUND;
#else
    int  rc  = 0;
    int  pdu = plugin->pdu_size;
    word conn_type = (word) plugin->connection_type;

    if (plugin->client == 0) {
        return NEU_ERR_EINTERNAL;
    }

    s7_disconnect(plugin);

    Cli_SetConnectionType((S7Object) plugin->client, conn_type);

    if (plugin->plc_type == 0) {
        word local  = plugin->local_tsap;
        word remote = plugin->remote_tsap;
        rc = Cli_SetConnectionParams((S7Object) plugin->client, plugin->host,
                                     local, remote);
        if (rc == 0) {
            rc = Cli_Connect((S7Object) plugin->client);
        }
    } else {
        rc = Cli_ConnectTo((S7Object) plugin->client, plugin->host,
                           plugin->rack, plugin->slot);
    }

    if (rc != 0) {
        int last = 0;
        Cli_GetLastError((S7Object) plugin->client, &last);
        return s7_err_from_snap7(last);
    }

    if (pdu > 0) {
        Cli_SetParam((S7Object) plugin->client, p_i32_PDURequest, &pdu);
    }

    int port = plugin->port;
    if (port > 0 && port != 102) {
        Cli_SetParam((S7Object) plugin->client, p_u16_RemotePort, &port);
    }

    plugin->connected         = true;
    plugin->common.link_state = NEU_NODE_LINK_STATE_CONNECTED;
    return NEU_ERR_SUCCESS;
#endif
}

int s7_read_tag(neu_plugin_t *plugin, const neu_datatag_t *tag,
                neu_dvalue_t *out)
{
#if !defined(NEU_S7_HAS_SNAP7) || !NEU_S7_HAS_SNAP7
    (void) plugin;
    (void) tag;
    (void) out;
    return NEU_ERR_LIBRARY_NOT_FOUND;
#else
    s7_parsed_addr_t addr = { 0 };
    uint8_t          buf[4096];
    int              area = 0;
    int              rc   = 0;

    if (!plugin->connected) {
        return NEU_ERR_S7COMM_DISCONNECTED;
    }

    if (s7_addr_parse(tag->address, tag->type, &addr) != 0) {
        return NEU_ERR_S7COMM_INVALID_ADDRESS;
    }

    area = snap7_area_from_parsed(&addr);
    if (area < 0) {
        return NEU_ERR_S7COMM_INVALID_ADDRESS;
    }

    if (addr.area == S7_AREA_T) {
        rc = Cli_TMRead((S7Object) plugin->client, addr.start, addr.amount, buf);
    } else if (addr.area == S7_AREA_C) {
        rc = Cli_CTRead((S7Object) plugin->client, addr.start, addr.amount, buf);
    } else if (addr.area == S7_AREA_DB) {
        rc = Cli_DBRead((S7Object) plugin->client, addr.db_number, addr.start,
                        addr.amount, buf);
    } else if (addr.area == S7_AREA_I) {
        rc = Cli_EBRead((S7Object) plugin->client, addr.start, addr.amount, buf);
    } else if (addr.area == S7_AREA_O || addr.area == S7_AREA_Q) {
        rc = Cli_ABRead((S7Object) plugin->client, addr.start, addr.amount, buf);
    } else {
        rc = Cli_MBRead((S7Object) plugin->client, addr.start, addr.amount, buf);
    }

    if (rc != 0) {
        int last = 0;
        Cli_GetLastError((S7Object) plugin->client, &last);
        return s7_err_from_snap7(last);
    }

    if (tag->type == NEU_TYPE_BIT || addr.has_bit) {
        rc = Cli_ReadArea((S7Object) plugin->client, area, addr.db_number,
                          addr.start, 1, S7WLBit, buf);
        if (rc != 0) {
            int last = 0;
            Cli_GetLastError((S7Object) plugin->client, &last);
            return s7_err_from_snap7(last);
        }
        if (bytes_to_dvalue(buf, 1, NEU_TYPE_BIT, true, out) != 0) {
            return NEU_ERR_S7COMM_TYPE_INCONSISTENT;
        }
        return NEU_ERR_SUCCESS;
    }

    if (bytes_to_dvalue(buf, addr.amount, tag->type, false, out) != 0) {
        return NEU_ERR_S7COMM_TYPE_INCONSISTENT;
    }
    return NEU_ERR_SUCCESS;
#endif
}

int s7_write_tag(neu_plugin_t *plugin, const neu_datatag_t *tag,
                 neu_value_u value)
{
#if !defined(NEU_S7_HAS_SNAP7) || !NEU_S7_HAS_SNAP7
    (void) plugin;
    (void) tag;
    (void) value;
    return NEU_ERR_LIBRARY_NOT_FOUND;
#else
    s7_parsed_addr_t addr = { 0 };
    uint8_t          buf[4096];
    int              area = 0;
    int              rc   = 0;
    int              n    = 0;

    if (!plugin->connected) {
        return NEU_ERR_S7COMM_DISCONNECTED;
    }

    if (!neu_tag_attribute_test(tag, NEU_ATTRIBUTE_WRITE)) {
        return NEU_ERR_PLUGIN_TAG_NOT_ALLOW_WRITE;
    }

    if (s7_addr_parse(tag->address, tag->type, &addr) != 0) {
        return NEU_ERR_S7COMM_INVALID_ADDRESS;
    }

    if (!addr.writable) {
        return NEU_ERR_PLUGIN_TAG_NOT_ALLOW_WRITE;
    }

    area = snap7_area_from_parsed(&addr);
    n    = dvalue_to_bytes(tag->type, value, buf, sizeof(buf));
    if (n <= 0) {
        return NEU_ERR_S7COMM_TYPE_NOT_SUPPORTED;
    }

    if (tag->type == NEU_TYPE_BIT || addr.has_bit) {
        rc = Cli_WriteArea((S7Object) plugin->client, area, addr.db_number,
                           addr.start, 1, S7WLBit, buf);
    } else if (addr.area == S7_AREA_DB) {
        rc = Cli_DBWrite((S7Object) plugin->client, addr.db_number, addr.start,
                         n, buf);
    } else if (addr.area == S7_AREA_T) {
        rc = Cli_TMWrite((S7Object) plugin->client, addr.start, 1, buf);
    } else if (addr.area == S7_AREA_C) {
        rc = Cli_CTWrite((S7Object) plugin->client, addr.start, 1, buf);
    } else if (addr.area == S7_AREA_O || addr.area == S7_AREA_Q) {
        rc = Cli_ABWrite((S7Object) plugin->client, addr.start, n, buf);
    } else {
        rc = Cli_MBWrite((S7Object) plugin->client, addr.start, n, buf);
    }

    if (rc != 0) {
        int last = 0;
        Cli_GetLastError((S7Object) plugin->client, &last);
        return s7_err_from_snap7(last);
    }
    return NEU_ERR_SUCCESS;
#endif
}

int s7_group_read(neu_plugin_t *plugin, neu_plugin_group_t *group)
{
    utarray_foreach(group->tags, neu_datatag_t *, tag)
    {
        neu_dvalue_t dvalue = { 0 };
        int          err    = s7_read_tag(plugin, tag, &dvalue);

        if (err != NEU_ERR_SUCCESS) {
            dvalue.type      = NEU_TYPE_ERROR;
            dvalue.value.i32 = err;
        }

        plugin->common.adapter_callbacks->driver.update(
            plugin->common.adapter, group->group_name, tag->name, dvalue);

        if (plugin->t2 > 0) {
            usleep((useconds_t) plugin->t2 * 1000);
        }
    }
    return 0;
}

neu_plugin_t *s7_driver_open(s7_variant_e variant)
{
    neu_plugin_t *plugin = calloc(1, sizeof(neu_plugin_t));
    neu_plugin_common_init(&plugin->common);
    plugin->variant = variant;
    if (variant == S7_VARIANT_300) {
        plugin->slot = 2;
    }
    plugin->host            = strdup("127.0.0.1");
    plugin->port            = 102;
    plugin->pdu_size        = 960;
    plugin->rack            = 0;
    plugin->slot            = (variant == S7_VARIANT_300) ? 2 : S7_DEFAULT_SLOT;
    plugin->connection_type = 1;
    plugin->t1              = 1;
    plugin->t2              = 0;
    plugin->t3              = 20;
    return plugin;
}

static int driver_close(neu_plugin_t *plugin)
{
    free(plugin->host);
    free(plugin);
    return 0;
}

int s7_driver_close(neu_plugin_t *plugin)
{
    return driver_close(plugin);
}

int s7_driver_init(neu_plugin_t *plugin, bool load)
{
    (void) load;
#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
    plugin->client = (uintptr_t) Cli_Create();
#endif
    plog_notice(plugin, "%s init success", plugin->common.name);
    return 0;
}

int s7_driver_uninit(neu_plugin_t *plugin)
{
    s7_disconnect(plugin);
#if defined(NEU_S7_HAS_SNAP7) && NEU_S7_HAS_SNAP7
    if (plugin->client != 0) {
        S7Object c = (S7Object) plugin->client;
        Cli_Destroy(&c);
        plugin->client = 0;
    }
#endif
    free(plugin->host);
    return 0;
}

int s7_driver_start(neu_plugin_t *plugin)
{
    plugin->started = true;
    return s7_driver_try_connect(plugin);
}

int s7_driver_stop(neu_plugin_t *plugin)
{
    plugin->started = false;
    s7_disconnect(plugin);
    return 0;
}

int s7_driver_config(neu_plugin_t *plugin, const char *config)
{
    char *          err_param = NULL;
    neu_json_elem_t host      = { .name = "host", .t = NEU_JSON_STR };
    neu_json_elem_t port      = { .name = "port", .t = NEU_JSON_INT };
    neu_json_elem_t pdu_size  = { .name = "pdu_size", .t = NEU_JSON_INT };
    neu_json_elem_t plc_type  = { .name = "plc_type", .t = NEU_JSON_INT };
    neu_json_elem_t conn_type = { .name = "connection_type", .t = NEU_JSON_INT };
    neu_json_elem_t rack      = { .name = "rack", .t = NEU_JSON_INT };
    neu_json_elem_t slot      = { .name = "slot", .t = NEU_JSON_INT };
    neu_json_elem_t local_tsap  = { .name = "local_tsap", .t = NEU_JSON_INT };
    neu_json_elem_t remote_tsap = { .name = "remote_tsap", .t = NEU_JSON_INT };
    neu_json_elem_t t1        = { .name = "t1", .t = NEU_JSON_INT };
    neu_json_elem_t t2        = { .name = "t2", .t = NEU_JSON_INT };
    neu_json_elem_t t3        = { .name = "t3", .t = NEU_JSON_INT };
    int             ret       = 0;

    ret = neu_parse_param((char *) config, &err_param, 3, &host, &port, &pdu_size);
    if (ret != 0) {
        free(err_param);
        free(host.v.val_str);
        return NEU_ERR_NODE_SETTING_INVALID;
    }

    neu_parse_param((char *) config, &err_param, 4, &plc_type, &conn_type, &rack,
                    &slot);
    free(err_param);
    neu_parse_param((char *) config, &err_param, 3, &local_tsap, &remote_tsap,
                    &t1);
    free(err_param);
    neu_parse_param((char *) config, &err_param, 2, &t2, &t3);
    free(err_param);

    free(plugin->host);
    plugin->host            = host.v.val_str;
    plugin->port            = (uint16_t) port.v.val_int;
    plugin->pdu_size        = pdu_size.v.val_int;
    plugin->plc_type        = plc_type.v.val_int;
    plugin->connection_type = conn_type.v.val_int;
    plugin->rack            = rack.v.val_int;
    plugin->slot            = slot.v.val_int;
    plugin->local_tsap      = (uint16_t) local_tsap.v.val_int;
    plugin->remote_tsap      = (uint16_t) remote_tsap.v.val_int;
    plugin->t1              = t1.v.val_int;
    plugin->t2              = t2.v.val_int;
    plugin->t3              = t3.v.val_int;

    if (plugin->slot <= 0) {
        plugin->slot = S7_DEFAULT_SLOT;
    }
    if (plugin->pdu_size <= 0) {
        plugin->pdu_size = 960;
    }
    if (plugin->port == 0) {
        plugin->port = 102;
    }

    return 0;
}

int s7_driver_request(neu_plugin_t *plugin, neu_reqresp_head_t *head, void *data)
{
    (void) plugin;
    (void) head;
    (void) data;
    return 0;
}

int s7_driver_try_connect(neu_plugin_t *plugin)
{
    if (!plugin->started) {
        return NEU_ERR_PLUGIN_NOT_RUNNING;
    }
    return s7_connect(plugin);
}

int s7_driver_validate_tag(neu_plugin_t *plugin, neu_datatag_t *tag)
{
    (void) plugin;
    if (s7_addr_validate(tag->address, tag->type) != 0) {
        return NEU_ERR_TAG_ADDRESS_FORMAT_INVALID;
    }
    return NEU_ERR_SUCCESS;
}

int s7_driver_group_timer(neu_plugin_t *plugin, neu_plugin_group_t *group)
{
    if (!plugin->connected) {
        s7_publish_err(plugin, group, NEU_ERR_S7COMM_DISCONNECTED);
        return 0;
    }
    return s7_group_read(plugin, group);
}

int s7_driver_write(neu_plugin_t *plugin, void *req, neu_datatag_t *tag,
                    neu_value_u value)
{
    int err = s7_write_tag(plugin, tag, value);
    plugin->common.adapter_callbacks->driver.write_response(
        plugin->common.adapter, req, err);
    return 0;
}

int s7_driver_write_tags(neu_plugin_t *plugin, void *req, UT_array *tags)
{
    int err = NEU_ERR_SUCCESS;

    utarray_foreach(tags, neu_plugin_tag_value_t *, tv)
    {
        int rc = s7_write_tag(plugin, tv->tag, tv->value);
        if (rc != NEU_ERR_SUCCESS) {
            err = rc;
        }
        if (plugin->t1 > 0 && plugin->t2 > 0) {
            usleep((useconds_t) plugin->t2 * 1000);
        }
    }

    plugin->common.adapter_callbacks->driver.write_response(
        plugin->common.adapter, req, err);
    return 0;
}

int s7_driver_test_read_tag(neu_plugin_t *plugin, void *req, neu_datatag_t tag)
{
    neu_dvalue_t dvalue = { 0 };
    int          err    = s7_read_tag(plugin, &tag, &dvalue);

    if (err != NEU_ERR_SUCCESS) {
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, NEU_TYPE_ERROR,
            (neu_json_value_u){}, err);
        return 0;
    }

    neu_json_value_u jv = { 0 };
    switch (dvalue.type) {
    case NEU_TYPE_BIT:
    case NEU_TYPE_BOOL:
        jv.val_int = dvalue.value.u8;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    case NEU_TYPE_INT8:
        jv.val_int = dvalue.value.i8;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    case NEU_TYPE_UINT8:
        jv.val_int = dvalue.value.u8;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    case NEU_TYPE_INT16:
        jv.val_int = dvalue.value.i16;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    case NEU_TYPE_UINT16:
        jv.val_int = dvalue.value.u16;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    case NEU_TYPE_INT32:
        jv.val_int = dvalue.value.i32;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    case NEU_TYPE_UINT32:
        jv.val_int = (int64_t) dvalue.value.u32;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    case NEU_TYPE_FLOAT:
        jv.val_int = (int64_t) dvalue.value.f32;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    case NEU_TYPE_STRING:
        jv.val_str = dvalue.value.str;
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_STR, dvalue.type, jv,
            NEU_ERR_SUCCESS);
        break;
    default:
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, NEU_TYPE_ERROR,
            (neu_json_value_u){}, NEU_ERR_S7COMM_TYPE_NOT_SUPPORTED);
        break;
    }
    return 0;
}
