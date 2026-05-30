#include <gtest/gtest.h>
#include <neuron.h>

extern "C" {
#include "s7_addr.h"
}

zlog_category_t *neuron           = NULL;
int64_t          global_timestamp = 0;

TEST(s7_addr_parse, bit_and_db)
{
    s7_parsed_addr_t addr = { 0 };

    EXPECT_EQ(0, s7_addr_parse("I0.0", NEU_TYPE_BIT, &addr));
    EXPECT_EQ(S7_AREA_I, addr.area);
    EXPECT_TRUE(addr.has_bit);

    EXPECT_EQ(0, s7_addr_parse("DB1.DBW10", NEU_TYPE_INT16, &addr));
    EXPECT_EQ(S7_AREA_DB, addr.area);
    EXPECT_EQ(1, addr.db_number);
    EXPECT_EQ(10, addr.start);

    EXPECT_EQ(0, s7_addr_parse("DB1.DBW12.20", NEU_TYPE_STRING, &addr));
    EXPECT_EQ(22, addr.amount);

    EXPECT_EQ(0, s7_addr_parse("DB6.DBD0", NEU_TYPE_FLOAT, &addr));
    EXPECT_EQ(S7_AREA_DB, addr.area);
    EXPECT_EQ(6, addr.db_number);
    EXPECT_EQ(0, addr.start);

    EXPECT_NE(0, s7_addr_parse("INVALID", NEU_TYPE_INT16, &addr));
}
