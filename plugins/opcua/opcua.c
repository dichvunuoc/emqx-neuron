/**
 * NEURON IIoT System for Industry 4.0
 **/

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <neuron.h>

#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
#include <open62541/client.h>
#include <open62541/client_config_default.h>
#include <open62541/client_highlevel.h>
#include <open62541/client_subscriptions.h>
#endif

#define OPCUA_READ_MODE_POLL          0
#define OPCUA_READ_MODE_SUBSCRIPTION 1

typedef struct neu_plugin neu_plugin_t;
typedef struct opcua_mon_ctx opcua_mon_ctx_t;
typedef struct opcua_group_ctx opcua_group_ctx_t;

struct opcua_group_ctx {
    neu_plugin_t *     plugin;
    int                read_mode;
    bool               sub_inited;
    uint32_t           subscription_id;
    size_t             n_ctx;
    opcua_mon_ctx_t ** mon_ctxs;
};

struct neu_plugin {
    neu_plugin_common_t common;
    char *              endpoint;
    char *              username;
    char *              password;
    bool                use_auth;
    int64_t             timeout_ms;
    int64_t             publish_interval_ms;
    int                 read_mode;
    bool                started;
    bool                connected;
#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
    UA_Client *client;
#endif
};

static neu_plugin_t *driver_open(void);
static int           driver_close(neu_plugin_t *plugin);
static int           driver_init(neu_plugin_t *plugin, bool load);
static int           driver_uninit(neu_plugin_t *plugin);
static int           driver_start(neu_plugin_t *plugin);
static int           driver_stop(neu_plugin_t *plugin);
static int           driver_config(neu_plugin_t *plugin, const char *config);
static int           driver_request(neu_plugin_t *plugin, neu_reqresp_head_t *head,
                                    void *data);
static int           driver_connect(neu_plugin_t *plugin);
static int           driver_validate_tag(neu_plugin_t *plugin, neu_datatag_t *tag);
static int           driver_group_timer(neu_plugin_t *plugin, neu_plugin_group_t *group);
static int           driver_write(neu_plugin_t *plugin, void *req,
                                  neu_datatag_t *tag, neu_value_u value);
static int           driver_scan_tags(neu_plugin_t *plugin, void *req, char *id,
                                      char *ctx, int load_index);
static int           driver_test_read_tag(neu_plugin_t *plugin, void *req,
                                          neu_datatag_t tag);
#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
static void opcua_group_free(neu_plugin_group_t *pgp);
#endif

static const neu_plugin_intf_funs_t plugin_intf_funs = {
    .open        = (neu_plugin_t * (*)(void)) driver_open,
    .close       = (int (*)(neu_plugin_t *)) driver_close,
    .init        = (int (*)(neu_plugin_t *, bool)) driver_init,
    .uninit      = (int (*)(neu_plugin_t *)) driver_uninit,
    .start       = (int (*)(neu_plugin_t *)) driver_start,
    .stop        = (int (*)(neu_plugin_t *)) driver_stop,
    .setting     = (int (*)(neu_plugin_t *, const char *)) driver_config,
    .request     = (int (*)(neu_plugin_t *, neu_reqresp_head_t *, void *)) driver_request,
    .try_connect = (int (*)(neu_plugin_t *)) driver_connect,
    .driver.validate_tag = (int (*)(neu_plugin_t *, neu_datatag_t *)) driver_validate_tag,
    .driver.group_timer  = (int (*)(neu_plugin_t *, neu_plugin_group_t *)) driver_group_timer,
    .driver.group_sync   = (int (*)(neu_plugin_t *, neu_plugin_group_t *)) driver_group_timer,
    .driver.write_tag = (int (*)(neu_plugin_t *, void *, neu_datatag_t *, neu_value_u)) driver_write,
    .driver.tag_validator = NULL,
    .driver.write_tags    = NULL,
    .driver.test_read_tag = (int (*)(neu_plugin_t *, void *, neu_datatag_t)) driver_test_read_tag,
    .driver.add_tags      = NULL,
    .driver.load_tags     = NULL,
    .driver.del_tags      = NULL,
    .driver.scan_tags     = (int (*)(neu_plugin_t *, void *, char *, char *, int)) driver_scan_tags,
};

const neu_plugin_module_t neu_plugin_module = {
    .version         = NEURON_PLUGIN_VER_1_0,
    .schema          = "opcua",
    .module_name     = "OPC UA",
    .module_descr    = "Open source OPC UA southbound plugin",
    .module_descr_zh = "开源 OPC UA 南向驱动插件",
    .intf_funs       = &plugin_intf_funs,
    .kind            = NEU_PLUGIN_KIND_SYSTEM,
    .type            = NEU_NA_TYPE_DRIVER,
    .display         = true,
    .single          = false,
};

static void plugin_disconnect(neu_plugin_t *plugin)
{
#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
    if (plugin->client != NULL && plugin->connected) {
        UA_Client_disconnect(plugin->client);
    }
#endif
    plugin->connected         = false;
    plugin->common.link_state = NEU_NODE_LINK_STATE_DISCONNECTED;
}

static int parse_node_id(const char *address, int *ns, char **nodeid)
{
    const char *sep = strchr(address, ';');
    if (sep != NULL && sscanf(address, "ns=%d;", ns) == 1) {
        *nodeid = strdup(sep + 1);
        return *nodeid ? 0 : -1;
    }
    sep = strchr(address, '!');
    if (sep == NULL) {
        return -1;
    }
    *ns = atoi(address);
    *nodeid = strdup(sep + 1);
    return *nodeid ? 0 : -1;
}

#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
static int nodeid_from_parts(int ns, const char *id_part, UA_NodeId *out)
{
    if (strncmp(id_part, "i=", 2) == 0) {
        *out = UA_NODEID_NUMERIC((UA_UInt16) ns, (UA_UInt32) atoi(id_part + 2));
        return 0;
    }
    if (strncmp(id_part, "s=", 2) == 0) {
        *out = UA_NODEID_STRING_ALLOC((UA_UInt16) ns, id_part + 2);
        return 0;
    }
    *out = UA_NODEID_STRING_ALLOC((UA_UInt16) ns, id_part);
    return 0;
}

static int address_to_nodeid(const char *address, UA_NodeId *out)
{
    int   ns = 0;
    char *id = NULL;
    if (parse_node_id(address, &ns, &id) != 0) {
        return -1;
    }
    int r = nodeid_from_parts(ns, id, out);
    free(id);
    return r;
}

static int variant_to_dvalue(const neu_datatag_t *tag, const UA_Variant *value,
                             neu_dvalue_t *dvalue)
{
    if (!UA_Variant_isScalar(value) || value->data == NULL) {
        return -1;
    }

    dvalue->type = tag->type;
    switch (tag->type) {
    case NEU_TYPE_BOOL:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_BOOLEAN])) {
            return -1;
        }
        dvalue->value.boolean = *(UA_Boolean *) value->data;
        return 0;
    case NEU_TYPE_INT8:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_SBYTE])) {
            return -1;
        }
        dvalue->value.i8 = *(UA_SByte *) value->data;
        return 0;
    case NEU_TYPE_UINT8:
    case NEU_TYPE_BIT:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_BYTE])) {
            return -1;
        }
        dvalue->value.u8 = *(UA_Byte *) value->data;
        return 0;
    case NEU_TYPE_INT16:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_INT16])) {
            return -1;
        }
        dvalue->value.i16 = *(UA_Int16 *) value->data;
        return 0;
    case NEU_TYPE_UINT16:
    case NEU_TYPE_WORD:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_UINT16])) {
            return -1;
        }
        dvalue->value.u16 = *(UA_UInt16 *) value->data;
        return 0;
    case NEU_TYPE_INT32:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_INT32])) {
            return -1;
        }
        dvalue->value.i32 = *(UA_Int32 *) value->data;
        return 0;
    case NEU_TYPE_UINT32:
    case NEU_TYPE_DWORD:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_UINT32])) {
            return -1;
        }
        dvalue->value.u32 = *(UA_UInt32 *) value->data;
        return 0;
    case NEU_TYPE_INT64:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_INT64])) {
            return -1;
        }
        dvalue->value.i64 = *(UA_Int64 *) value->data;
        return 0;
    case NEU_TYPE_UINT64:
    case NEU_TYPE_LWORD:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_UINT64])) {
            return -1;
        }
        dvalue->value.u64 = *(UA_UInt64 *) value->data;
        return 0;
    case NEU_TYPE_FLOAT:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_FLOAT])) {
            return -1;
        }
        dvalue->value.f32 = *(UA_Float *) value->data;
        return 0;
    case NEU_TYPE_DOUBLE:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_DOUBLE])) {
            return -1;
        }
        dvalue->value.d64 = *(UA_Double *) value->data;
        return 0;
    case NEU_TYPE_STRING:
        if (!UA_Variant_hasScalarType(value, &UA_TYPES[UA_TYPES_STRING])) {
            return -1;
        }
        {
            UA_String *str = (UA_String *) value->data;
            size_t     n =
                str->length < (NEU_VALUE_SIZE - 1) ? str->length : (NEU_VALUE_SIZE - 1);
            memcpy(dvalue->value.str, str->data, n);
            dvalue->value.str[n] = '\0';
        }
        return 0;
    default:
        return -1;
    }
}

static int neu_value_to_write_variant(neu_type_e t, neu_value_u v, UA_Variant *out)
{
    UA_StatusCode sc = UA_STATUSCODE_GOOD;
    UA_Variant_init(out);
    switch (t) {
    case NEU_TYPE_BOOL:
        sc = UA_Variant_setScalarCopy(out, &v.boolean, &UA_TYPES[UA_TYPES_BOOLEAN]);
        break;
    case NEU_TYPE_INT8: {
        UA_SByte x = v.i8;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_SBYTE]);
        break;
    }
    case NEU_TYPE_UINT8:
    case NEU_TYPE_BIT: {
        UA_Byte x = v.u8;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_BYTE]);
        break;
    }
    case NEU_TYPE_INT16: {
        UA_Int16 x = v.i16;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_INT16]);
        break;
    }
    case NEU_TYPE_UINT16:
    case NEU_TYPE_WORD: {
        UA_UInt16 x = v.u16;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_UINT16]);
        break;
    }
    case NEU_TYPE_INT32: {
        UA_Int32 x = v.i32;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_INT32]);
        break;
    }
    case NEU_TYPE_UINT32:
    case NEU_TYPE_DWORD: {
        UA_UInt32 x = v.u32;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_UINT32]);
        break;
    }
    case NEU_TYPE_INT64: {
        UA_Int64 x = v.i64;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_INT64]);
        break;
    }
    case NEU_TYPE_UINT64:
    case NEU_TYPE_LWORD: {
        UA_UInt64 x = v.u64;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_UINT64]);
        break;
    }
    case NEU_TYPE_FLOAT: {
        UA_Float x = v.f32;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_FLOAT]);
        break;
    }
    case NEU_TYPE_DOUBLE: {
        UA_Double x = v.d64;
        sc = UA_Variant_setScalarCopy(out, &x, &UA_TYPES[UA_TYPES_DOUBLE]);
        break;
    }
    case NEU_TYPE_STRING: {
        UA_String s = UA_STRING(v.str);
        sc = UA_Variant_setScalarCopy(out, &s, &UA_TYPES[UA_TYPES_STRING]);
        break;
    }
    default:
        return -1;
    }
    return (sc == UA_STATUSCODE_GOOD) ? 0 : -1;
}

typedef struct opcua_mon_ctx {
    neu_plugin_t *plugin;
    char          group_name[NEU_GROUP_NAME_LEN];
    char          tag_name[NEU_TAG_NAME_LEN];
    neu_type_e    type;
} opcua_mon_ctx_t;

static void opcua_data_change(UA_Client *client, UA_UInt32 subId, void *subContext,
                              UA_UInt32 monId, void *monContext, UA_DataValue *value)
{
    (void) client;
    (void) subId;
    (void) subContext;
    (void) monId;
    opcua_mon_ctx_t *ctx = (opcua_mon_ctx_t *) monContext;
    if (ctx == NULL || value == NULL || !value->hasValue) {
        return;
    }
    neu_plugin_t *plugin = ctx->plugin;
    neu_dvalue_t  dvalue = { 0 };
    neu_datatag_t tmp    = { 0 };
    tmp.type             = ctx->type;
    if (variant_to_dvalue(&tmp, &value->value, &dvalue) != 0) {
        dvalue.type      = NEU_TYPE_ERROR;
        dvalue.value.i32 = NEU_ERR_PLUGIN_TAG_TYPE_MISMATCH;
    }
    plugin->common.adapter_callbacks->driver.update(
        plugin->common.adapter, ctx->group_name, ctx->tag_name, dvalue);
}

static void opcua_group_free(neu_plugin_group_t *pgp)
{
    opcua_group_ctx_t *g = (opcua_group_ctx_t *) pgp->user_data;
    if (g == NULL) {
        return;
    }
    if (g->plugin != NULL && g->plugin->client != NULL && g->sub_inited &&
        g->subscription_id != 0) {
        (void) UA_Client_Subscriptions_deleteSingle(g->plugin->client,
                                                   g->subscription_id);
    }
    if (g->mon_ctxs != NULL) {
        for (size_t i = 0; i < g->n_ctx; i++) {
            free(g->mon_ctxs[i]);
        }
        free(g->mon_ctxs);
    }
    free(g);
    pgp->user_data  = NULL;
    pgp->group_free = NULL;
}

static int opcua_subscription_setup(neu_plugin_t *plugin, neu_plugin_group_t *group)
{
    opcua_group_ctx_t *g = (opcua_group_ctx_t *) group->user_data;
    if (g != NULL && g->sub_inited) {
        return 0;
    }
    if (g == NULL) {
        g = calloc(1, sizeof(opcua_group_ctx_t));
        if (g == NULL) {
            return -1;
        }
        g->plugin    = plugin;
        g->read_mode = plugin->read_mode;
        group->user_data  = g;
        group->group_free = opcua_group_free;
    }

    UA_CreateSubscriptionRequest sub_req = UA_CreateSubscriptionRequest_default();
    sub_req.requestedPublishingInterval = (UA_Double) plugin->publish_interval_ms;
    UA_CreateSubscriptionResponse sub_resp =
        UA_Client_Subscriptions_create(plugin->client, sub_req, NULL, NULL, NULL);
    if (sub_resp.responseHeader.serviceResult != UA_STATUSCODE_GOOD) {
        plog_error(plugin, "OPC UA create subscription failed: 0x%x",
                   (unsigned) sub_resp.responseHeader.serviceResult);
        return -1;
    }
    g->subscription_id = sub_resp.subscriptionId;

    size_t n = utarray_len(group->tags);
    g->mon_ctxs = calloc(n, sizeof(opcua_mon_ctx_t *));
    if (g->mon_ctxs == NULL) {
        (void) UA_Client_Subscriptions_deleteSingle(plugin->client, sub_resp.subscriptionId);
        g->subscription_id = 0;
        return -1;
    }

    size_t idx = 0;
    utarray_foreach(group->tags, neu_datatag_t *, tag)
    {
        UA_NodeId nodeid = UA_NODEID_NULL;
        if (address_to_nodeid(tag->address, &nodeid) != 0) {
            idx++;
            continue;
        }
        opcua_mon_ctx_t *mctx = calloc(1, sizeof(opcua_mon_ctx_t));
        if (mctx == NULL) {
            UA_NodeId_clear(&nodeid);
            idx++;
            continue;
        }
        mctx->plugin = plugin;
        mctx->type   = tag->type;
        snprintf(mctx->group_name, sizeof(mctx->group_name), "%s", group->group_name);
        snprintf(mctx->tag_name, sizeof(mctx->tag_name), "%s", tag->name);

        UA_MonitoredItemCreateRequest mon_req =
            UA_MonitoredItemCreateRequest_default(nodeid);
        mon_req.requestedParameters.samplingInterval =
            (UA_Double) plugin->publish_interval_ms;

        UA_MonitoredItemCreateResult mon_res = UA_Client_MonitoredItems_createDataChange(
            plugin->client, g->subscription_id, UA_TIMESTAMPSTORETURN_BOTH, mon_req, mctx,
            opcua_data_change, NULL);
        UA_NodeId_clear(&nodeid);
        if (mon_res.statusCode == UA_STATUSCODE_GOOD) {
            g->mon_ctxs[g->n_ctx++] = mctx;
        } else {
            free(mctx);
        }
        idx++;
    }
    g->sub_inited = true;
    return 0;
}
#endif

static neu_plugin_t *driver_open(void)
{
    neu_plugin_t *plugin = calloc(1, sizeof(neu_plugin_t));
    neu_plugin_common_init(&plugin->common);
    plugin->endpoint              = strdup("opc.tcp://127.0.0.1:4840/");
    plugin->timeout_ms            = 5000;
    plugin->publish_interval_ms   = 500;
    plugin->read_mode             = OPCUA_READ_MODE_POLL;
    return plugin;
}

static int driver_close(neu_plugin_t *plugin)
{
    free(plugin);
    return 0;
}

static int driver_init(neu_plugin_t *plugin, bool load)
{
    (void) load;
#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
    plugin->client = UA_Client_new();
    UA_ClientConfig_setDefault(UA_Client_getConfig(plugin->client));
#else
    (void) plugin;
#endif
    return 0;
}

static int driver_uninit(neu_plugin_t *plugin)
{
    plugin_disconnect(plugin);
#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
    if (plugin->client != NULL) {
        UA_Client_delete(plugin->client);
        plugin->client = NULL;
    }
#endif
    free(plugin->endpoint);
    free(plugin->username);
    free(plugin->password);
    return 0;
}

static int driver_start(neu_plugin_t *plugin)
{
    plugin->started = true;
    return driver_connect(plugin);
}

static int driver_stop(neu_plugin_t *plugin)
{
    plugin->started = false;
    plugin_disconnect(plugin);
    return 0;
}

static int driver_config(neu_plugin_t *plugin, const char *config)
{
    int             ret       = 0;
    char *          err_param = NULL;
    neu_json_elem_t endpoint =
        { .name = "endpoint", .t = NEU_JSON_STR, .v.val_str = NULL };
    neu_json_elem_t timeout = { .name = "timeout", .t = NEU_JSON_INT };
    neu_json_elem_t enable_auth = { .name = "enable_auth", .t = NEU_JSON_INT };
    neu_json_elem_t username =
        { .name = "username", .t = NEU_JSON_STR, .v.val_str = NULL };
    neu_json_elem_t password =
        { .name = "password", .t = NEU_JSON_STR, .v.val_str = NULL };
    neu_json_elem_t read_mode = { .name = "read_mode", .t = NEU_JSON_INT };
    neu_json_elem_t publish_interval = { .name = "publish_interval",
                                         .t    = NEU_JSON_INT };

    ret = neu_parse_param((char *) config, &err_param, 2, &endpoint, &timeout);
    if (ret != 0) {
        free(err_param);
        free(endpoint.v.val_str);
        return NEU_ERR_PARAM_IS_WRONG;
    }
    ret = neu_parse_param((char *) config, &err_param, 3, &enable_auth, &username,
                          &password);
    if (ret != 0) {
        free(err_param);
        enable_auth.v.val_int = 0;
    }
    ret = neu_parse_param((char *) config, &err_param, 2, &read_mode, &publish_interval);
    if (ret != 0) {
        free(err_param);
        read_mode.v.val_int           = OPCUA_READ_MODE_POLL;
        publish_interval.v.val_int    = 500;
    }

    free(plugin->endpoint);
    plugin->endpoint = endpoint.v.val_str;
    plugin->timeout_ms = timeout.v.val_int;
    plugin->use_auth   = (enable_auth.v.val_int != 0);
    free(plugin->username);
    free(plugin->password);
    plugin->username = plugin->use_auth ? username.v.val_str : NULL;
    plugin->password = plugin->use_auth ? password.v.val_str : NULL;
    if (!plugin->use_auth) {
        free(username.v.val_str);
        free(password.v.val_str);
    }
    plugin->read_mode =
        (read_mode.v.val_int == OPCUA_READ_MODE_SUBSCRIPTION) ? OPCUA_READ_MODE_SUBSCRIPTION
                                                                : OPCUA_READ_MODE_POLL;
    plugin->publish_interval_ms = publish_interval.v.val_int;
    if (plugin->publish_interval_ms < 100) {
        plugin->publish_interval_ms = 100;
    }
    return 0;
}

static int driver_request(neu_plugin_t *plugin, neu_reqresp_head_t *head, void *data)
{
    (void) plugin;
    (void) head;
    (void) data;
    return 0;
}

static int driver_connect(neu_plugin_t *plugin)
{
#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
    UA_StatusCode rc = UA_STATUSCODE_GOOD;
    if (plugin->use_auth && plugin->username != NULL && plugin->password != NULL) {
        rc = UA_Client_connectUsername(plugin->client, plugin->endpoint,
                                       plugin->username, plugin->password);
    } else {
        rc = UA_Client_connect(plugin->client, plugin->endpoint);
    }
    if (rc != UA_STATUSCODE_GOOD) {
        return NEU_ERR_PLUGIN_DISCONNECTED;
    }
    plugin->connected         = true;
    plugin->common.link_state = NEU_NODE_LINK_STATE_CONNECTED;
    return 0;
#else
    (void) plugin;
    return NEU_ERR_LIBRARY_NOT_FOUND;
#endif
}

static int driver_validate_tag(neu_plugin_t *plugin, neu_datatag_t *tag)
{
    int   ns = 0;
    char *id = NULL;
    (void) plugin;
    if (parse_node_id(tag->address, &ns, &id) != 0) {
        return NEU_ERR_TAG_ADDRESS_FORMAT_INVALID;
    }
    free(id);
    return 0;
}

static void publish_err(neu_plugin_t *plugin, neu_plugin_group_t *group, int err)
{
    utarray_foreach(group->tags, neu_datatag_t *, tag)
    {
        neu_dvalue_t dvalue = { .type = NEU_TYPE_ERROR };
        dvalue.value.i32    = err;
        plugin->common.adapter_callbacks->driver.update(
            plugin->common.adapter, group->group_name, tag->name, dvalue);
    }
}

static int driver_group_poll(neu_plugin_t *plugin, neu_plugin_group_t *group)
{
#if !defined(NEU_OPCUA_HAS_OPEN62541) || !NEU_OPCUA_HAS_OPEN62541
    publish_err(plugin, group, NEU_ERR_LIBRARY_NOT_FOUND);
    return 0;
#else
    utarray_foreach(group->tags, neu_datatag_t *, tag)
    {
        UA_NodeId    nodeid = UA_NODEID_NULL;
        UA_Variant   value;
        neu_dvalue_t dvalue = { 0 };
        UA_Variant_init(&value);

        if (address_to_nodeid(tag->address, &nodeid) != 0) {
            dvalue.type         = NEU_TYPE_ERROR;
            dvalue.value.i32    = NEU_ERR_TAG_ADDRESS_FORMAT_INVALID;
            plugin->common.adapter_callbacks->driver.update(
                plugin->common.adapter, group->group_name, tag->name, dvalue);
            continue;
        }

        UA_StatusCode rc = UA_Client_readValueAttribute(plugin->client, nodeid, &value);
        if (rc != UA_STATUSCODE_GOOD) {
            dvalue.type      = NEU_TYPE_ERROR;
            dvalue.value.i32 = NEU_ERR_PLUGIN_READ_FAILURE;
        } else if (variant_to_dvalue(tag, &value, &dvalue) != 0) {
            dvalue.type      = NEU_TYPE_ERROR;
            dvalue.value.i32 = NEU_ERR_PLUGIN_TAG_TYPE_MISMATCH;
        }

        plugin->common.adapter_callbacks->driver.update(
            plugin->common.adapter, group->group_name, tag->name, dvalue);
        UA_Variant_clear(&value);
        UA_NodeId_clear(&nodeid);
    }
    return 0;
#endif
}

static int driver_group_timer(neu_plugin_t *plugin, neu_plugin_group_t *group)
{
    if (!plugin->connected) {
        publish_err(plugin, group, NEU_ERR_PLUGIN_DISCONNECTED);
        return 0;
    }
#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
    if (plugin->read_mode == OPCUA_READ_MODE_SUBSCRIPTION) {
        if (opcua_subscription_setup(plugin, group) != 0) {
            publish_err(plugin, group, NEU_ERR_PLUGIN_READ_FAILURE);
            return 0;
        }
        UA_StatusCode rc = UA_Client_run_iterate(plugin->client,
                                                 (UA_UInt32) plugin->publish_interval_ms);
        if (rc != UA_STATUSCODE_GOOD) {
            plog_warn(plugin, "UA_Client_run_iterate: 0x%x", (unsigned) rc);
        }
        return 0;
    }
#endif
    return driver_group_poll(plugin, group);
}

static int driver_write(neu_plugin_t *plugin, void *req, neu_datatag_t *tag, neu_value_u value)
{
#if !defined(NEU_OPCUA_HAS_OPEN62541) || !NEU_OPCUA_HAS_OPEN62541
    (void) tag;
    (void) value;
    plugin->common.adapter_callbacks->driver.write_response(
        plugin->common.adapter, req, NEU_ERR_LIBRARY_NOT_FOUND);
    return 0;
#else
    if (!plugin->connected) {
        plugin->common.adapter_callbacks->driver.write_response(
            plugin->common.adapter, req, NEU_ERR_PLUGIN_DISCONNECTED);
        return 0;
    }
    UA_NodeId  nodeid = UA_NODEID_NULL;
    UA_Variant val;
    UA_Variant_init(&val);
    if (address_to_nodeid(tag->address, &nodeid) != 0) {
        plugin->common.adapter_callbacks->driver.write_response(
            plugin->common.adapter, req, NEU_ERR_TAG_ADDRESS_FORMAT_INVALID);
        return 0;
    }
    if (neu_value_to_write_variant(tag->type, value, &val) != 0) {
        UA_NodeId_clear(&nodeid);
        plugin->common.adapter_callbacks->driver.write_response(
            plugin->common.adapter, req, NEU_ERR_TAG_TYPE_NOT_SUPPORT);
        return 0;
    }
    UA_StatusCode rc = UA_Client_writeValueAttribute(plugin->client, nodeid, &val);
    UA_Variant_clear(&val);
    UA_NodeId_clear(&nodeid);
    plugin->common.adapter_callbacks->driver.write_response(
        plugin->common.adapter, req,
        rc == UA_STATUSCODE_GOOD ? NEU_ERR_SUCCESS : NEU_ERR_PLUGIN_WRITE_FAILURE);
    return 0;
#endif
}

#if defined(NEU_OPCUA_HAS_OPEN62541) && NEU_OPCUA_HAS_OPEN62541
static neu_type_e opcua_browse_guess_type(UA_Byte node_class)
{
    if (node_class == UA_NODECLASS_VARIABLE) {
        return NEU_TYPE_INT32;
    }
    return NEU_TYPE_INT32;
}
#endif

static int driver_scan_tags(neu_plugin_t *plugin, void *req, char *id, char *ctx,
                            int load_index)
{
    (void) ctx;
    neu_resp_scan_tags_t resp = { 0 };
    resp.error                = NEU_ERR_SUCCESS;
    resp.type                 = NEU_TYPE_CUSTOM;
    resp.is_array             = true;
    resp.c_flag               = 1;
    resp.load_index           = load_index;
    snprintf(resp.ctx, sizeof(resp.ctx), "%s", ctx == NULL ? "" : ctx);

#if !defined(NEU_OPCUA_HAS_OPEN62541) || !NEU_OPCUA_HAS_OPEN62541
    (void) plugin;
    (void) id;
    resp.error = NEU_ERR_LIBRARY_NOT_FOUND;
    plugin->common.adapter_callbacks->driver.scan_tags_response(
        plugin->common.adapter, req, &resp);
    return 0;
#else
    if (!plugin->connected && driver_connect(plugin) != 0) {
        resp.error = NEU_ERR_PLUGIN_DISCONNECTED;
        plugin->common.adapter_callbacks->driver.scan_tags_response(
            plugin->common.adapter, req, &resp);
        return 0;
    }

    UA_NodeId browse_node = UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER);
    if (id != NULL && strlen(id) > 0) {
        UA_NodeId_clear(&browse_node);
        if (address_to_nodeid(id, &browse_node) != 0) {
            resp.error = NEU_ERR_TAG_ADDRESS_FORMAT_INVALID;
            plugin->common.adapter_callbacks->driver.scan_tags_response(
                plugin->common.adapter, req, &resp);
            return 0;
        }
    }

    UA_BrowseRequest breq;
    UA_BrowseRequest_init(&breq);
    breq.requestedMaxReferencesPerNode = 100;
    breq.nodesToBrowseSize             = 1;
    breq.nodesToBrowse =
        (UA_BrowseDescription *) UA_Array_new(1, &UA_TYPES[UA_TYPES_BROWSEDESCRIPTION]);
    if (breq.nodesToBrowse == NULL) {
        UA_NodeId_clear(&browse_node);
        resp.error = NEU_ERR_EINTERNAL;
        plugin->common.adapter_callbacks->driver.scan_tags_response(
            plugin->common.adapter, req, &resp);
        return 0;
    }
    UA_BrowseDescription_init(&breq.nodesToBrowse[0]);
    UA_StatusCode cp = UA_NodeId_copy(&browse_node, &breq.nodesToBrowse[0].nodeId);
    UA_NodeId_clear(&browse_node);
    if (cp != UA_STATUSCODE_GOOD) {
        UA_BrowseRequest_clear(&breq);
        resp.error = NEU_ERR_EINTERNAL;
        plugin->common.adapter_callbacks->driver.scan_tags_response(
            plugin->common.adapter, req, &resp);
        return 0;
    }
    breq.nodesToBrowse[0].browseDirection = UA_BROWSEDIRECTION_FORWARD;
    breq.nodesToBrowse[0].includeSubtypes = true;
    breq.nodesToBrowse[0].resultMask       = UA_BROWSERESULTMASK_ALL;
    breq.nodesToBrowse[0].referenceTypeId =
        UA_NODEID_NUMERIC(0, UA_NS0ID_HIERARCHICALREFERENCES);

    UA_BrowseResponse bresp = UA_Client_Service_browse(plugin->client, breq);
    UA_BrowseRequest_clear(&breq);

    utarray_new(resp.scan_tags, &ut_ptr_icd);
    if (bresp.responseHeader.serviceResult != UA_STATUSCODE_GOOD ||
        bresp.resultsSize == 0) {
        resp.error = NEU_ERR_PLUGIN_READ_FAILURE;
        UA_BrowseResponse_clear(&bresp);
        plugin->common.adapter_callbacks->driver.scan_tags_response(
            plugin->common.adapter, req, &resp);
        return 0;
    }

    UA_BrowseResult *br = &bresp.results[0];
    for (size_t i = 0; i < br->referencesSize; i++) {
        UA_ReferenceDescription *rd = &br->references[i];
        neu_scan_tag_t *           st = calloc(1, sizeof(neu_scan_tag_t));
        if (st == NULL) {
            continue;
        }
        UA_String dn = rd->displayName.text;
        size_t    nl = dn.length < NEU_TAG_NAME_LEN - 1 ? dn.length : NEU_TAG_NAME_LEN - 1;
        memcpy(st->name, dn.data, nl);
        st->name[nl] = '\0';
        if (st->name[0] == '\0' && rd->browseName.name.length > 0) {
            nl = rd->browseName.name.length < NEU_TAG_NAME_LEN - 1
                     ? rd->browseName.name.length
                     : NEU_TAG_NAME_LEN - 1;
            memcpy(st->name, rd->browseName.name.data, nl);
            st->name[nl] = '\0';
        }

        UA_NodeId *nid = &rd->nodeId.nodeId;
        if (nid->namespaceIndex == 0 && nid->identifierType == UA_NODEIDTYPE_NUMERIC) {
            snprintf(st->id, sizeof(st->id), "%u!i=%u", (unsigned) nid->namespaceIndex,
                     (unsigned) nid->identifier.numeric);
        } else if (nid->identifierType == UA_NODEIDTYPE_STRING) {
            snprintf(st->id, sizeof(st->id), "%u!s=%.*s", (unsigned) nid->namespaceIndex,
                     (int) nid->identifier.string.length, nid->identifier.string.data);
        } else {
            free(st);
            continue;
        }

        st->tag = 0;
        if (rd->nodeClass == UA_NODECLASS_VARIABLE) {
            st->is_last_layer = true;
            st->type          = opcua_browse_guess_type((UA_Byte) rd->nodeClass);
        } else {
            st->is_last_layer = false;
        }

        utarray_push_back(resp.scan_tags, &st);
    }
    UA_BrowseResponse_clear(&bresp);

    plugin->common.adapter_callbacks->driver.scan_tags_response(
        plugin->common.adapter, req, &resp);
    return 0;
#endif
}

static int driver_test_read_tag(neu_plugin_t *plugin, void *req, neu_datatag_t tag)
{
    neu_json_value_u error_value = { .val_int = 0 };
#if !defined(NEU_OPCUA_HAS_OPEN62541) || !NEU_OPCUA_HAS_OPEN62541
    (void) tag;
    plugin->common.adapter_callbacks->driver.test_read_tag_response(
        plugin->common.adapter, req, NEU_JSON_INT, NEU_TYPE_ERROR, error_value,
        NEU_ERR_LIBRARY_NOT_FOUND);
    return 0;
#else
    if (driver_validate_tag(plugin, &tag) != 0) {
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, NEU_TYPE_ERROR, error_value,
            NEU_ERR_TAG_ADDRESS_FORMAT_INVALID);
        return 0;
    }
    if (!plugin->connected && driver_connect(plugin) != 0) {
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, NEU_TYPE_ERROR, error_value,
            NEU_ERR_PLUGIN_DISCONNECTED);
        return 0;
    }
    UA_NodeId    nodeid = UA_NODEID_NULL;
    UA_Variant   value;
    neu_dvalue_t dvalue = { 0 };
    UA_Variant_init(&value);
    if (address_to_nodeid(tag.address, &nodeid) != 0) {
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, NEU_TYPE_ERROR, error_value,
            NEU_ERR_TAG_ADDRESS_FORMAT_INVALID);
        return 0;
    }
    UA_StatusCode rc = UA_Client_readValueAttribute(plugin->client, nodeid, &value);
    UA_NodeId_clear(&nodeid);
    if (rc != UA_STATUSCODE_GOOD || variant_to_dvalue(&tag, &value, &dvalue) != 0) {
        UA_Variant_clear(&value);
        plugin->common.adapter_callbacks->driver.test_read_tag_response(
            plugin->common.adapter, req, NEU_JSON_INT, NEU_TYPE_ERROR, error_value,
            NEU_ERR_PLUGIN_READ_FAILURE);
        return 0;
    }
    UA_Variant_clear(&value);

    neu_json_value_u jv  = { 0 };
    neu_json_type_e  jt = NEU_JSON_INT;
    switch (dvalue.type) {
    case NEU_TYPE_BOOL:
        jt = NEU_JSON_BIT;
        jv.val_bit = dvalue.value.boolean;
        break;
    case NEU_TYPE_INT32:
        jt = NEU_JSON_INT;
        jv.val_int = dvalue.value.i32;
        break;
    case NEU_TYPE_UINT32:
        jt = NEU_JSON_INT;
        jv.val_int = (int64_t) dvalue.value.u32;
        break;
    case NEU_TYPE_FLOAT:
        jt = NEU_JSON_FLOAT;
        jv.val_float = dvalue.value.f32;
        break;
    case NEU_TYPE_DOUBLE:
        jt = NEU_JSON_DOUBLE;
        jv.val_double = dvalue.value.d64;
        break;
    case NEU_TYPE_STRING:
        jt = NEU_JSON_STR;
        jv.val_str = strdup(dvalue.value.str);
        break;
    default:
        jt = NEU_JSON_INT;
        jv.val_int = 0;
        break;
    }
    plugin->common.adapter_callbacks->driver.test_read_tag_response(
        plugin->common.adapter, req, jt, dvalue.type, jv, NEU_ERR_SUCCESS);
    if (jt == NEU_JSON_STR && jv.val_str != NULL) {
        free(jv.val_str);
    }
    return 0;
#endif
}
