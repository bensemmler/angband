/**
 * \file AngbandTermViewDataSource.h
 * \brief Protocol for an object that can provide stuff to draw.
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

@protocol AngbandTermViewDrawing;

@protocol AngbandTermViewDataSource <NSObject>
@required
- (AngbandTerminalEntity)termView: (NSView <AngbandTermViewDrawing> * __nonnull)termView terminalEntityAtX: (NSInteger)x y: (NSInteger)y;
- (BOOL)graphicsEnabledForTermView: (NSView <AngbandTermViewDrawing> * __nonnull)termView;
- (CGRect)cursorRectForTermView: (NSView <AngbandTermViewDrawing> * __nonnull)termView;
@end
