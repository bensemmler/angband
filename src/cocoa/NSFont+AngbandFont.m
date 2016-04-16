/**
 * \file NSFont+AngbandFont.m
 * \brief NSFont category for font utilities.
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

#import "NSFont+AngbandFont.h"

#import "AngbandCommon.h"

@implementation NSFont (AngbandFont)

+ (instancetype)angband_defaultFont
{
	return [NSFont fontWithName: @"Menlo" size: 13.0];
}

@end
