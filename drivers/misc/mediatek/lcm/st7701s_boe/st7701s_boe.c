// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (c) 2019 MediaTek Inc.
 *
 * ST7701S 480x800 (WVGA) DSI video-mode panel, 2 lanes.
 *
 * Ported for the U1Pro (MT6765) tree: the vendor kernel names this panel
 * "st7701s_boe" and builds with CONFIG_LCM_WIDTH/HEIGHT = 480/800.  The init
 * sequence is the standard ST7701S 2-lane 480x800 sequence; the video timing
 * follows the same panel class (VSA/VBP/VFP 8/18/16, HSA/HBP/HFP 5/65/67,
 * PLL 206 MHz).
 */

#define LOG_TAG "LCM"

#ifndef BUILD_LK
#include <linux/string.h>
#include <linux/kernel.h>
#endif

#include "lcm_drv.h"

#define FRAME_WIDTH		(480)
#define FRAME_HEIGHT		(800)

#define LCM_PHYSICAL_WIDTH	(53000)	/* um */
#define LCM_PHYSICAL_HEIGHT	(88000)	/* um */
#define LCM_DENSITY		(240)

#define REGFLAG_DELAY		0xFFFC
#define REGFLAG_UDELAY		0xFFFB
#define REGFLAG_END_OF_TABLE	0xFFFD

/* ST7701S RDDID1 (DCS 0x04) */
#define ST7701S_ID1		0x77

static struct LCM_UTIL_FUNCS lcm_util;

#define SET_RESET_PIN(v)	(lcm_util.set_reset_pin((v)))
#define MDELAY(n)		(lcm_util.mdelay(n))
#define UDELAY(n)		(lcm_util.udelay(n))
#define dsi_set_cmdq_V22(cmdq, cmd, count, ppara, force_update) \
	lcm_util.dsi_set_cmdq_V22(cmdq, cmd, count, ppara, force_update)
#define read_reg_v2(cmd, buffer, buffer_size) \
	lcm_util.dsi_dcs_read_lcm_reg_v2(cmd, buffer, buffer_size)

struct LCM_setting_table {
	unsigned int cmd;
	unsigned char count;
	unsigned char para_list[64];
};

static struct LCM_setting_table lcm_init_setting[] = {
	{0xFF, 5, {0x77, 0x01, 0x00, 0x00, 0x11} },
	{0xD1, 2, {0x11, 0x11} },
	{0xFF, 5, {0x77, 0x01, 0x00, 0x00, 0x10} },
	{0xC0, 2, {0x63, 0x00} },
	{0xC1, 2, {0x0D, 0x02} },
	{0xC2, 2, {0x31, 0x06} },
	{0xB0, 16, {0x00, 0x03, 0x89, 0x0F, 0x16, 0x0A, 0x06, 0x0B,
		    0x0A, 0x1B, 0x09, 0x13, 0x12, 0x0C, 0x10, 0x15} },
	{0xB1, 16, {0x00, 0x03, 0x87, 0x0E, 0x14, 0x09, 0x04, 0x09,
		    0x09, 0x1D, 0x09, 0x18, 0x14, 0x14, 0x1A, 0x15} },
	{0xFF, 5, {0x77, 0x01, 0x00, 0x00, 0x11} },
	{0xB0, 1, {0x4D} },
	{0xB1, 1, {0x64} },
	{0xB2, 1, {0x07} },
	{0xB3, 1, {0x80} },
	{0xB5, 1, {0x47} },
	{0xB7, 1, {0x8A} },
	{0xB8, 1, {0x21} },
	{0xC1, 1, {0x78} },
	{0xC2, 1, {0x78} },
	{0xD0, 1, {0x88} },

	{REGFLAG_DELAY, 100, {} },

	{0xE0, 3, {0x00, 0x00, 0x02} },
	{0xE1, 11, {0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
		    0x00, 0x40, 0x40} },
	{0xE2, 13, {0x33, 0x33, 0x34, 0x34, 0x2C, 0x00, 0x2D, 0x00,
		    0x2B, 0x00, 0x2E, 0x00, 0x00} },
	{0xE3, 4, {0x00, 0x00, 0x33, 0x33} },
	{0xE4, 2, {0x44, 0x44} },
	{0xE5, 16, {0x04, 0x40, 0xA0, 0xA0, 0x06, 0x40, 0xA0, 0xA0,
		    0x08, 0x40, 0xA0, 0xA0, 0x0A, 0x40, 0xA0, 0xA0} },
	{0xE6, 4, {0x00, 0x00, 0x33, 0x33} },
	{0xE7, 2, {0x44, 0x44} },
	{0xE8, 16, {0x03, 0x40, 0xA0, 0xA0, 0x05, 0x40, 0xA0, 0xA0,
		    0x07, 0x40, 0xA0, 0xA0, 0x09, 0x40, 0xA0, 0xA0} },
	{0xEB, 7, {0x02, 0x00, 0x39, 0x39, 0x88, 0x33, 0x10} },
	{0xEC, 2, {0x02, 0x00} },
	{0xED, 16, {0xFF, 0x04, 0x56, 0x7F, 0x89, 0xF2, 0xFF, 0x3F,
		    0xF3, 0xFF, 0x2F, 0x98, 0xF7, 0x65, 0x40, 0xFF} },
	{0xFF, 5, {0x77, 0x01, 0x00, 0x00, 0x00} },

	{REGFLAG_DELAY, 20, {} },

	{0x35, 1, {0x00} },
	{0x11, 1, {0x00} },

	{REGFLAG_DELAY, 120, {} },

	{0x29, 1, {0x00} },

	{REGFLAG_DELAY, 50, {} },

	{REGFLAG_END_OF_TABLE, 0, {} },
};

static struct LCM_setting_table lcm_suspend_setting[] = {
	{0x28, 1, {0x00} },
	{REGFLAG_DELAY, 20, {} },
	{0x10, 1, {0x00} },
	{REGFLAG_DELAY, 120, {} },
	{REGFLAG_END_OF_TABLE, 0, {} },
};

static struct LCM_setting_table bl_level[] = {
	{0x51, 1, {0x00} },
};

static void push_table(void *cmdq, struct LCM_setting_table *table,
	unsigned int count, unsigned char force_update)
{
	unsigned int i;
	unsigned int cmd;

	for (i = 0; i < count; i++) {
		cmd = table[i].cmd;

		switch (cmd) {
		case REGFLAG_DELAY:
			MDELAY(table[i].count);
			break;
		case REGFLAG_UDELAY:
			UDELAY(table[i].count);
			break;
		case REGFLAG_END_OF_TABLE:
			break;
		default:
			dsi_set_cmdq_V22(cmdq, cmd, table[i].count,
				table[i].para_list, force_update);
			break;
		}
	}
}

static void lcm_set_util_funcs(const struct LCM_UTIL_FUNCS *util)
{
	memcpy(&lcm_util, util, sizeof(struct LCM_UTIL_FUNCS));
}

static void lcm_get_params(struct LCM_PARAMS *params)
{
	memset(params, 0, sizeof(struct LCM_PARAMS));

	params->type = LCM_TYPE_DSI;
	params->width = FRAME_WIDTH;
	params->height = FRAME_HEIGHT;
	params->physical_width = LCM_PHYSICAL_WIDTH / 1000;
	params->physical_height = LCM_PHYSICAL_HEIGHT / 1000;
	params->physical_width_um = LCM_PHYSICAL_WIDTH;
	params->physical_height_um = LCM_PHYSICAL_HEIGHT;
	params->density = LCM_DENSITY;

	params->dsi.mode = SYNC_PULSE_VDO_MODE;
	params->dsi.switch_mode = SYNC_PULSE_VDO_MODE;
	params->dsi.switch_mode_enable = 0;

	/* DSI */
	params->dsi.LANE_NUM = LCM_TWO_LANE;
	params->dsi.data_format.color_order = LCM_COLOR_ORDER_RGB;
	params->dsi.data_format.trans_seq = LCM_DSI_TRANS_SEQ_MSB_FIRST;
	params->dsi.data_format.padding = LCM_DSI_PADDING_ON_LSB;
	params->dsi.data_format.format = LCM_DSI_FORMAT_RGB888;
	params->dsi.packet_size = 256;
	params->dsi.PS = LCM_PACKED_PS_24BIT_RGB888;

	/* video mode timing */
	params->dsi.vertical_sync_active = 8;
	params->dsi.vertical_backporch = 18;
	params->dsi.vertical_frontporch = 16;
	params->dsi.vertical_active_line = FRAME_HEIGHT;

	params->dsi.horizontal_sync_active = 5;
	params->dsi.horizontal_backporch = 65;
	params->dsi.horizontal_frontporch = 67;
	params->dsi.horizontal_active_pixel = FRAME_WIDTH;

	params->dsi.PLL_CLOCK = 206;
	params->dsi.ssc_disable = 0;
	params->dsi.CLK_HS_POST = 36;
	params->dsi.clk_lp_per_line_enable = 0;
	params->dsi.esd_check_enable = 0;
}

static void lcm_init(void)
{
	unsigned int size;

	SET_RESET_PIN(1);
	MDELAY(10);
	SET_RESET_PIN(0);
	MDELAY(10);
	SET_RESET_PIN(1);
	MDELAY(120);

	size = sizeof(lcm_init_setting) / sizeof(struct LCM_setting_table);
	push_table(NULL, lcm_init_setting, size, 1);
}

static void lcm_suspend(void)
{
	push_table(NULL, lcm_suspend_setting,
		sizeof(lcm_suspend_setting) / sizeof(struct LCM_setting_table), 1);
}

static void lcm_resume(void)
{
	lcm_init();
}

static unsigned int lcm_compare_id(void)
{
	unsigned char buffer[3] = {0x00, 0x00, 0x00};
	unsigned int id;

	SET_RESET_PIN(1);
	MDELAY(1);
	SET_RESET_PIN(0);
	MDELAY(10);
	SET_RESET_PIN(1);
	MDELAY(120);

	read_reg_v2(0x04, buffer, 3);
	id = (buffer[0] << 16) | (buffer[1] << 8) | buffer[2];

	pr_debug("[LCM]%s st7701s_boe id=0x%06x\n", __func__, id);

	return (buffer[0] == ST7701S_ID1) ? 1 : 0;
}

static void lcm_setbacklight_cmdq(void *handle, unsigned int level)
{
	bl_level[0].para_list[0] = (unsigned char)level;
	push_table(handle, bl_level, 1, 1);
}

static void lcm_update(unsigned int x, unsigned int y, unsigned int width,
	unsigned int height)
{
	/* video mode panel: no partial update */
}

struct LCM_DRIVER st7701s_boe_lcm_drv = {
	.name = "st7701s_boe",
	.set_util_funcs = lcm_set_util_funcs,
	.get_params = lcm_get_params,
	.init = lcm_init,
	.suspend = lcm_suspend,
	.resume = lcm_resume,
	.compare_id = lcm_compare_id,
	.set_backlight_cmdq = lcm_setbacklight_cmdq,
	.update = lcm_update,
};
