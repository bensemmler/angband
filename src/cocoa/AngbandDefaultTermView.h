/**
 * \file AngbandDefaultTermView.h
 * \brief View subclass for drawing Angband content.
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
#import "AngbandTermViewDrawing.h"

@class AngbandTileset;
@protocol AngbandTermViewDataSource;

@class AngbandOverlayView;

@interface AngbandDefaultTermView : NSView <AngbandTermViewDrawing>
{
@private
	AngbandTileset *_tileset;
	BOOL _dataSourceValid;
	BOOL _tileSizeSeemsIntegral;
	CGFloat _preferredAdvance;
	CGSize _tileSize;
	NSColor *_cursorColor;
	NSColor *_wipeColor;
	NSFont *_drawingFont;
	char *_UTF8FontName;
	id <AngbandTermViewDataSource> _dataSource;
}

@property (nonatomic, retain) NSColor * __nullable cursorColor;
@property (nonatomic, retain) NSColor * __nullable wipeColor;

@end
