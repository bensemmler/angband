/**
 * \file AngbandTermWindow.h
 * \brief Window subclass to handle drawing and events.
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
#import "AngbandCommon.h"
#import "ui-term.h"

@class AngbandTermConfiguration;
@protocol AngbandTermViewDrawing;

@interface AngbandTermWindow : NSWindow
{
@private
	AngbandTermConfiguration *_configuration;
	AngbandTerminalEntity *_terminalEntities;
	BOOL _automaticResizeInProgress;
	CGRect _cursorRect;
	NSView <AngbandTermViewDrawing> *_terminalView;
	term *_terminal;
	u32b _subwindowFlags;
}

@property (nonatomic, assign) u32b subwindowFlags;

- (BOOL)useImageTilesetAtPath: (NSString * __nonnull)path tileWidth: (CGFloat)tileWidth tileHeight: (CGFloat)tileHeight;
- (BOOL)windowVisibleUsingDefaults;
- (NSInteger)handleClearTerm;
- (NSInteger)handleCursorUpdateWithInfo: (AngbandTerminalUpdateInfo * __nonnull)update;
- (NSInteger)handlePictUpdateWithInfo: (AngbandTerminalUpdateInfo * __nonnull)update;
- (NSInteger)handleTextUpdateWithInfo: (AngbandTerminalUpdateInfo * __nonnull)info;
- (NSInteger)handleWipeWithInfo: (AngbandTerminalUpdateInfo * __nonnull)update;
- (instancetype __nullable)initWithConfiguration: (AngbandTermConfiguration * __nonnull)configuration termView: (NSView <AngbandTermViewDrawing> * __nonnull)termView NS_DESIGNATED_INITIALIZER;
- (void)saveWindowVisibleToDefaults: (BOOL)windowVisible;
- (void)useTextCharacterTileset;
@end
