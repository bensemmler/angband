/**
 * \file NSColor+AngbandTermColor.m
 * \brief NSColor category for color utilities.
 *
 * Copyright (c) 2013, 2016 Ben Semmler
 *
 * This work is free software; you can redistribute it and/or modify it
 * under the terms of either:
 *
 * a) the GNU General Public License as published by the Free Software
 *    Foundation, version 2, or
 *
 * b) the "Angband licence":
 *    This software may be copied and distributed for educational, research,
 *    and not for profit purposes provided that this copyright and statement
 *    are included in all such copies.  Other copyrights may also apply.
 */

#import "NSColor+AngbandTermColor.h"

#import "AngbandCommon.h"

@implementation NSColor (AngbandTermColor)

/**
 * Return a color that represents some kind of drawing error. Currently a barely
 * visible red.
 */
+ (instancetype)angband_badColor
{
	return [[self class] colorWithDeviceRed: 0x20/255.0 green: 0.0 blue: 0.0 alpha: 1.0];
}

/**
 * Return the color for the cursor (usually a stroked rect).
 */
+ (instancetype)angband_cursorColor
{
	return [[self class] yellowColor];
}

/**
 * Return the color that should be drawn as the wiped background color. This
 * isn't necessarily the same as the background color for a tile.
 */
+ (instancetype)angband_wipeColor
{
	return [[self class] blackColor];
}

/**
 * Return an NSColor in the device color space using the Angband color table
 * values.
 */
+ (instancetype)angband_colorForTermColorIndex: (int)index
{
	if (index < 0) {
		return [[self class] angband_badColor];
	}

	int safeIndex = index % MAX_COLORS;
	byte red = angband_color_table[safeIndex][COLOR_TABLE_RED];
	byte green = angband_color_table[safeIndex][COLOR_TABLE_GREEN];
	byte blue = angband_color_table[safeIndex][COLOR_TABLE_BLUE];
	return [[self class] colorWithDeviceRed: red/255.0 green: green/255.0 blue: blue/255.0 alpha: 1.0];
}

/**
 * Return the background color for a particular tile. This value is stored in
 * the high byte of attributes.
 */
+ (instancetype)angband_backgroundColorForAttribute: (int)attribute
{
	// default to a color that doesn't exist in the color table
	NSColor *backgroundColor = [[self class] angband_badColor];

	switch (attribute / MAX_COLORS) {
		case BG_BLACK:
//			backgroundColor = [[self class] blackColor];
			backgroundColor = [[self class] clearColor];
			break;
		case BG_SAME:
			backgroundColor = [[self class] angband_colorForTermColorIndex: attribute];
			break;
		case BG_DARK:
			backgroundColor = [[self class] angband_colorForTermColorIndex: COLOUR_SHADE];
			break;
		default:
			break;
	}

	return backgroundColor;
}

@end
