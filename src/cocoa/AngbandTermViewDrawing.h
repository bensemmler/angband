/**
 * \file AngbandTermViewDrawing.h
 * \brief Protocol for objects that can draw Angband things.
 *
 * Copyright (c) 2016 Ben Semmler
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
#import	"AngbandCommon.h"

@class AngbandTermConfiguration;
@class AngbandTileset;
@protocol AngbandTermViewDataSource;

@protocol AngbandTermViewDrawing <NSObject>
@property (nonatomic, assign) id <AngbandTermViewDataSource> __nullable dataSource;
@property (nonatomic, retain) AngbandTileset * __nullable tileset;
- (void)updateConfiguration: (AngbandTermConfiguration * __nonnull)configuration;
@end
