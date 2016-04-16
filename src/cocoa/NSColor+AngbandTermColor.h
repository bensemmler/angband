/**
 * \file NSColor+AngbandTermColor.h
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

#import <Cocoa/Cocoa.h>
#import "AngbandCommon.h"

@interface NSColor (AngbandTermColor)
+ (instancetype)angband_badColor;
+ (instancetype)angband_cursorColor;
+ (instancetype)angband_wipeColor;
+ (instancetype)angband_colorForTermColorIndex: (int)index;
+ (instancetype)angband_backgroundColorForAttribute: (int)attribute;
@end
