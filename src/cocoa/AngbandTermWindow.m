/**
 * \file AngbandTermWindow.m
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

#import "AngbandTermWindow.h"

#import "AngbandCommon.h"
#import "AngbandTermConfiguration.h"
#import "AngbandTermViewDataSource.h"
#import "AngbandTermViewDrawing.h"
#import "AngbandTileset.h"

extern BOOL AngbandGraphicsEnabled(void);
extern BOOL AngbandDisplayingMainInterface(void);

/**
 * Define some preferred behaviors for when windows and terminals are resized.
 */
typedef NS_ENUM(NSUInteger, AngbandTermWindowResizePreserving) {
	AngbandTermWindowResizePreservingDefault = 0, /**< Do whatever makes the most sense. */
	AngbandTermWindowResizePreservingWindow, /**< Preserve the size of the window, if possible, by changing terminal dimensions. */
	AngbandTermWindowResizePreservingTerminal, /**< Preserve the size of the terminal, if possible, by changing window dimensions. */
};

@interface AngbandTermWindow () <NSWindowDelegate, AngbandTermViewDataSource>
@property (nonatomic, assign) AngbandTerminalEntity *terminalEntities;
@property (nonatomic, assign) BOOL automaticResizeInProgress;
@property (nonatomic, assign) CGRect cursorRect;
@property (nonatomic, assign) term *terminal;
@property (nonatomic, copy) AngbandTermConfiguration *configuration;
@property (nonatomic, retain) NSView <AngbandTermViewDrawing> *terminalView;
@end

@implementation AngbandTermWindow

@synthesize automaticResizeInProgress=_automaticResizeInProgress;
@synthesize configuration=_configuration;
@synthesize cursorRect=_cursorRect;
@synthesize hasSubwindowFlags=_hasSubwindowFlags;
@synthesize terminal=_terminal;
@synthesize terminalEntities=_terminalEntities;
@synthesize terminalView=_terminalView;
@synthesize windowVisibilityChecked=_windowVisibilityChecked;

#pragma mark -
#pragma mark Instance Setup and Teardown

- (instancetype __nullable)initWithConfiguration: (AngbandTermConfiguration * __nonnull)configuration termView: (NSView <AngbandTermViewDrawing> * __nonnull)termView
{
	if (configuration == nil) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"A valid configuration must be provided when creating a term window." userInfo: nil] raise];
		return nil;
	}

	if (configuration.termInitializer == NULL) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"The configuration's terminal initializer function was null." userInfo: nil] raise];
		return nil;
	}

	NSRect contentRect = NSRectFromCGRect([configuration preferredContentBounds]);
	NSUInteger styleMask = [configuration windowStyleMask];

	if ((self = [super initWithContentRect: contentRect styleMask: styleMask backing: NSBackingStoreBuffered defer: YES])) {
		self.configuration = configuration;
		_windowVisibilityChecked = NO;
		_cursorRect = CGRectZero;
		_terminalEntities = NULL;
		[self allocateEntityBuffer];

		self.terminalView = termView;
		[self.terminalView updateConfiguration: self.configuration];
		self.terminalView.dataSource = self;

		[self setContentView: self.terminalView];
		[self setReleasedWhenClosed: NO];
		[self setExcludedFromWindowsMenu: YES];
		[self setDelegate: self];
		[self setContentMinSize: [self.configuration windowMinimumSize]];
		[self setTitle: [self.configuration windowTitle]];

		/* default position */ {
			// !!!: set the default frame using the fancy way
			[self center];
		}

		/* Set the autosave name AFTER we set any default positions, since this
		 * method will immediately change the window frame if it is able to find
		 * an existing frame in user defaults. */
		[self setFrameAutosaveName: [NSString stringWithFormat: AngbandTermWindowNameDefaultsKeyFormat, (int)self.configuration.index]];

		/* Modify some window behaviors if we're on a system that supports full-
		 * screen windows (10.7 and later). See the comments in the method used
		 * below for more information. */
		if ([self respondsToSelector: @selector(toggleFullScreen:)]) {
			NSWindowCollectionBehavior behavior = [self.configuration windowCollectionBehaviorWithBehavior: [self collectionBehavior]];
			[self setCollectionBehavior: behavior];
		}

		/* No Resume support yet, though it would not be hard to add */
		if ([self respondsToSelector: @selector(setRestorable:)]) {
			[self setRestorable: NO];
		}

		/* Create the stuff that Angband needs to actually render the game. */
		term *newTerm = (self.configuration.termInitializer)((int)self.configuration.index, (int)self.configuration.rows, (int)self.configuration.columns);

		if (newTerm != NULL) {
			newTerm->data = (void *)self;
			self.terminal = newTerm;
		}
	}

	return self;
}

- (void)dealloc
{
	[self deallocateEntityBuffer];
	[_configuration release];
	[_terminalView release];
	[super dealloc];
}

#pragma mark -
#pragma mark Other Methods

/**
 * Allocate the terminal entity storage and fill with null entities. The size of
 * the storage is based on the number of rows and columns in the term.
 */
- (void)allocateEntityBuffer
{
	if (_terminalEntities != NULL) {
		return;
	}

	_terminalEntities = calloc(self.configuration.columns * self.configuration.rows, sizeof(*_terminalEntities));
}

/**
 * Deallocate the terminal entity storage.
 */
- (void)deallocateEntityBuffer
{
	if (_terminalEntities == NULL) {
		return;
	}

	free(_terminalEntities);
	_terminalEntities = NULL;
}

/**
 * Set every entity in the entity storage to the null entity.
 */
- (void)resetEntityBuffer
{
	if (_terminalEntities == NULL) {
		return;
	}

	memset(_terminalEntities, 0, self.configuration.columns * self.configuration.rows * sizeof(*_terminalEntities));
}

/**
 * Resize the entity storage. This is a convenience method for deallocating and
 * allocating.
 */
- (void)resizeEntityBuffer
{
	[self deallocateEntityBuffer];
	[self allocateEntityBuffer];
}

/**
 * Return the rect that a given set of entities occupy.
 *
 * \param x The horizontal/column index of the first entity.
 * \param y The vertical/row index of the first entity.
 * \param count The number of entities, inclusive of the one at \c x and \c y,
 *        to include in the rect.
 * \return The rect containing \c count entities starting at \c x, \c y.
 */
- (CGRect)rectForEntitiesAtX: (int)x y: (int)y count: (int)count
{
	return CGRectMake(x * self.configuration.tileSize.width, y * self.configuration.tileSize.height, count * self.configuration.tileSize.width, self.configuration.tileSize.height);
}

/**
 * Hide the cursor. This does not cause any redrawing.
 */
- (void)resetCursorPosition
{
	self.cursorRect = CGRectZero;
}

/**
 * Process a new configuration and update the window as needed.
 *
 * \param newConfiguration The desired changes to be made to the window. The
 *        configuration passed in may not be the final configuration, as the
 *        receiver may make modifications to handle additional constraints.
 * \param preserving The preferred behavior for handling any necessary resizing.
 *        This mode will be honored as much as possible, but may not always be
 *        the final result.
 * \param saveToDefaults If YES, the final configuration used will be saved to
 *        user defaults for this terminal.
 */
- (void)updateConfiguration: (AngbandTermConfiguration * __nonnull)newConfiguration preserving: (AngbandTermWindowResizePreserving)preserving saveToDefaults: (BOOL)saveToDefaults
{
	if (newConfiguration == nil) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"A non-nil configuration must be provided to updateConfiguration." userInfo: nil] raise];
		return;
	}

	/* Figure out if this new configuration changes our content size in a way
	 * that would cause window or terminal size changes. The zero rect shouldn't
	 * happen, but we catch it to make sure it doesn't mess up resizing. Some
	 * additional checks could be done for efficiency, but otherwise forcing the
	 * term resize simplifies all of the different cases that can happen. */
	NSRect newContentRect = NSRectFromCGRect([newConfiguration preferredContentBounds]);
	BOOL terminalResizeNeeded = !NSEqualRects(newContentRect, NSZeroRect);
	BOOL expandWindowToFit = NO;

	if (terminalResizeNeeded) {
		if (preserving == AngbandTermWindowResizePreservingWindow || preserving == AngbandTermWindowResizePreservingDefault) {
			/* We want to preserve the window frame and the new content exceeds
			 * that frame, so we need to reduce the number of rows and columns
			 * in the terminal to make it fit. We treat this as the default
			 * behavior, since having to constantly reposition and resize
			 * windows is likely to annoy the user. */

			/* Avoid divide-by-zero, just in case. */
			CGFloat safeHeight = (newConfiguration.tileSize.height > 0.0) ? newConfiguration.tileSize.height : AngbandFallbackTileHeight;
			CGFloat safeWidth = (newConfiguration.tileSize.width > 0.0) ? newConfiguration.tileSize.width : AngbandFallbackTileWidth;
			NSInteger newRows = floor(self.terminalView.bounds.size.height / safeHeight);
			NSInteger newColumns = ceil(self.terminalView.bounds.size.width / safeWidth);
			newConfiguration = [newConfiguration configurationByChangingRows: newRows columns: newColumns];

			/* Check the adjusted content rect, since it could still be a size
			 * that is too big (since the configuration may have hit minimum
			 * sizes that it needs to respect). If so, we have no choice but to
			 * resize the window. */
			newContentRect = NSRectFromCGRect([newConfiguration preferredContentBounds]);
			expandWindowToFit = (!NSEqualRects(newContentRect, NSZeroRect) && !NSContainsRect(self.terminalView.bounds, newContentRect));
		}
		else if (preserving == AngbandTermWindowResizePreservingTerminal) {
			/* Something cause the new content size to grow (eg font size), and
			 * we want to maintain the terminal dimensions provided in the new
			 * configuration. Thus, the window should grow to fit. */
			expandWindowToFit = YES;
		}
	}
	else {
		/* The new content size is equal to or smaller than the window, so we
		 * really don't need to do anything. This would be the place to add any
		 * content-hugging behavior. */
	}

	if (expandWindowToFit) {
		/* Get the current screen content rect, offset it down by the height
		 * difference (to make it look like the window is growing down and
		 * to the right), and then set the new frame. */
		NSRect windowContentRect = [self contentRectForFrameRect: [self frame]];
		windowContentRect.origin.y -= NSHeight(newContentRect) - NSHeight(windowContentRect);
		windowContentRect.size = newContentRect.size;
		NSRect newFrame = [self frameRectForContentRect: newContentRect];
		newFrame.origin = windowContentRect.origin; /* Not sure why the origin is being reset. */

		/* This animation blocks, so we can simply wrap it in some flags. */
		self.automaticResizeInProgress = YES;
		[self setFrame: newFrame display: NO animate: YES];
		self.automaticResizeInProgress = NO;
	}

	self.configuration = newConfiguration;
	[self setContentMinSize: [self.configuration windowMinimumSize]];
	[self.terminalView updateConfiguration: self.configuration];

	if (saveToDefaults) {
		/* Save only the final configuration that is actually being used. */
		[self.configuration saveToDefaults];
	}

	if (terminalResizeNeeded) {
		/* The window and view are updated and ready for drawing, so now we can
		 * resize our storage and tell Angband to redraw the updated term. */
		[self resizeEntityBuffer];

		term *old = Term;
		Term_activate(self.terminal);
		Term_resize((int)self.configuration.columns, (int)self.configuration.rows);
		Term_redraw();
		Term_activate(old);
	}
	else {
		[self.terminalView setNeedsDisplay: YES];
	}
}

/**
 * Resize Angband's display to fit the window size as much as possible.
 *
 * \param contentRect The preferred content rect. This may not be the final rect
 *        used.
 * \param saveToDefaults If YES, the final configuration used will be saved to
 *        user defaults for this terminal.
 */
- (void)resizeTerminalWithContentRect: (NSRect)contentRect saveToDefaults: (BOOL)saveToDefaults
{
	/* Avoid divide-by-zero, just in case. */
	CGFloat safeHeight = (self.configuration.tileSize.height > 0.0) ? self.configuration.tileSize.height : AngbandFallbackTileHeight;
	CGFloat safeWidth = (self.configuration.tileSize.width > 0.0) ? self.configuration.tileSize.width : AngbandFallbackTileWidth;
	NSInteger newRows = floor(contentRect.size.height / safeHeight);
	NSInteger newColumns = ceil(contentRect.size.width / safeWidth);

	AngbandTermConfiguration *newConfiguration = [self.configuration configurationByChangingRows: newRows columns: newColumns];
	[self updateConfiguration: newConfiguration preserving: AngbandTermWindowResizePreservingWindow saveToDefaults: saveToDefaults];
}

- (void)saveWindowVisibleToDefaults: (BOOL)windowVisible
{
	/* Ensure main term is always visible. */
	BOOL safeVisibility = (self.configuration.index == 0) ? YES : windowVisible;
	self.configuration.visible = safeVisibility;
	[self.configuration saveToDefaults];
}

- (BOOL)windowVisibleUsingDefaults
{
	/* Ensure main term is always visible. */
	return (self.configuration.index == 0) ? YES : self.configuration.visible;
}

- (BOOL)useImageTilesetAtPath: (NSString * __nonnull)path tileWidth: (CGFloat)tileWidth tileHeight: (CGFloat)tileHeight
{
	self.terminalView.tileset = [AngbandTileset imageTilesetAtPath: path tileWidth: tileWidth tileHeight: tileHeight];
	return (self.terminalView.tileset != nil);
}

- (void)useTextCharacterTileset
{
	self.terminalView.tileset = nil;
}

#pragma mark -
#pragma mark Action Methods

/**
 * Handle requests to select a font for this window. This simply exposes the
 * necessary UI. Sent by the "Select Font" menu item.
 */
- (IBAction)editFont: (id)sender
{
	[[NSFontManager sharedFontManager] setSelectedFont: self.configuration.font isMultiple: NO];
	[[[NSFontManager sharedFontManager] fontPanel: YES] orderFront: self];
}

/**
 * Actually handle the change in selected font. Sent by some part of the font
 * system (we don't care too much which part).
 */
- (void)changeFont: (id)sender
{
	/* Call convertFont: as required by the font system to let it know that we
	 * accept the new font. */
	NSFont *newFont = [sender convertFont: self.configuration.font];
	AngbandTermConfiguration *newConfiguration = [self.configuration configurationByChangingFont: newFont];
	[self updateConfiguration: newConfiguration preserving: AngbandTermWindowResizePreservingWindow saveToDefaults: YES];
}

#pragma mark -
#pragma mark Event Handling

- (void)keyDown: (NSEvent *)event
{
	NSEventModifierFlags modifiers = [event modifierFlags];

	if ([[event characters] length] == 0) {
		return;
	}

	/* Extract some modifiers */
	int mc = !! (modifiers & NSControlKeyMask);
	int ms = !! (modifiers & NSShiftKeyMask);
	int mo = !! (modifiers & NSAlternateKeyMask);
	int mx = !! (modifiers & NSCommandKeyMask);
	int kp = !! (modifiers & NSNumericPadKeyMask);

	/* Get the Angband char corresponding to this unichar */
	unichar c = [[event characters] characterAtIndex:0];
	keycode_t ch;
	switch (c) {
			/* Note that NSNumericPadKeyMask is set if any of the arrow
			 * keys are pressed. We don't want KC_MOD_KEYPAD set for
			 * those. See #1662 for more details. */
		case NSUpArrowFunctionKey: ch = ARROW_UP; kp = 0; break;
		case NSDownArrowFunctionKey: ch = ARROW_DOWN; kp = 0; break;
		case NSLeftArrowFunctionKey: ch = ARROW_LEFT; kp = 0; break;
		case NSRightArrowFunctionKey: ch = ARROW_RIGHT; kp = 0; break;
		case NSF1FunctionKey: ch = KC_F1; break;
		case NSF2FunctionKey: ch = KC_F2; break;
		case NSF3FunctionKey: ch = KC_F3; break;
		case NSF4FunctionKey: ch = KC_F4; break;
		case NSF5FunctionKey: ch = KC_F5; break;
		case NSF6FunctionKey: ch = KC_F6; break;
		case NSF7FunctionKey: ch = KC_F7; break;
		case NSF8FunctionKey: ch = KC_F8; break;
		case NSF9FunctionKey: ch = KC_F9; break;
		case NSF10FunctionKey: ch = KC_F10; break;
		case NSF11FunctionKey: ch = KC_F11; break;
		case NSF12FunctionKey: ch = KC_F12; break;
		case NSF13FunctionKey: ch = KC_F13; break;
		case NSF14FunctionKey: ch = KC_F14; break;
		case NSF15FunctionKey: ch = KC_F15; break;
		case NSHelpFunctionKey: ch = KC_HELP; break;
		case NSHomeFunctionKey: ch = KC_HOME; break;
		case NSPageUpFunctionKey: ch = KC_PGUP; break;
		case NSPageDownFunctionKey: ch = KC_PGDOWN; break;
		case NSBeginFunctionKey: ch = KC_BEGIN; break;
		case NSEndFunctionKey: ch = KC_END; break;
		case NSInsertFunctionKey: ch = KC_INSERT; break;
		case NSDeleteFunctionKey: ch = KC_DELETE; break;
		case NSPauseFunctionKey: ch = KC_PAUSE; break;
		case NSBreakFunctionKey: ch = KC_BREAK; break;

		default:
			if (c <= 0x7F)
				ch = (char)c;
			else
				ch = '\0';
			break;
	}

	/* override special keys */
	switch([event keyCode]) {
		case kVK_Return: ch = KC_ENTER; break;
		case kVK_Escape: ch = ESCAPE; break;
		case kVK_Tab: ch = KC_TAB; break;
		case kVK_Delete: ch = KC_BACKSPACE; break;
		case kVK_ANSI_KeypadEnter: ch = KC_ENTER; kp = TRUE; break;
	}

	/* Hide the mouse pointer */
	[NSCursor setHiddenUntilMouseMoves: YES];

	/* Enqueue it */
	if (ch != '\0') {
		/* Enqueue the keypress */
#ifdef KC_MOD_ALT
		byte mods = 0;
		if (mo) mods |= KC_MOD_ALT;
		if (mx) mods |= KC_MOD_META;
		if (mc && MODS_INCLUDE_CONTROL(ch)) mods |= KC_MOD_CONTROL;
		if (ms && MODS_INCLUDE_SHIFT(ch)) mods |= KC_MOD_SHIFT;
		if (kp) mods |= KC_MOD_KEYPAD;
		Term_keypress(ch, mods);
#else
		Term_keypress(ch);
#endif
	}
}

/**
 * Process mouse clicks in the window. For the most Mac-like behavior, this 
 * method should be called from a mouse up event; this will allow cancellation
 * of the click, eg, moving the pointer out of the window while the button is
 * still pressed. Any modifier keys that are held during the click will also be
 * passed.
 *
 * \param event The mouse button event.
 * \param angbandMouseButton The index of the pressed mouse button, using an
 *        index that \c Term_mousepress() can understand.
 */
- (void)handleMouseButton: (NSEvent *)event angbandButtonIndex: (int)angbandMouseButton
{
	NSSize tileSize = NSSizeFromCGSize(self.configuration.tileSize);
	NSSize border = NSZeroSize;
	NSPoint windowPoint = [event locationInWindow];

	/* Adjust for border; add border height because window origin is at
	 * bottom */
	windowPoint = NSMakePoint(windowPoint.x - border.width, windowPoint.y + border.height);

	NSPoint termPoint = [[[event window] contentView] convertPoint: windowPoint fromView: nil];
	int x = floor(termPoint.x / tileSize.width);
	int y = floor(termPoint.y / tileSize.height);

	BOOL displayingMainInterface = AngbandDisplayingMainInterface();
	BOOL clickIsValid = NO;

	if (displayingMainInterface) {
		/* If the main interface is visible, limit clicks to the allowed area. */
		int cols, rows;
		Term_get_size(&cols, &rows);
		int const maxColumnIndex = cols - 1;
		int const maxRowIndex = rows - 1;
		clickIsValid = YES; /* Assume valid until a condition fails. */
		clickIsValid = clickIsValid && (x >= AngbandMainTermClickableLeftOffset);
		clickIsValid = clickIsValid && (x <= maxColumnIndex - AngbandMainTermClickableRightOffset);
		clickIsValid = clickIsValid && (y >= AngbandMainTermClickableTopOffset);
		clickIsValid = clickIsValid && (y <= maxRowIndex - AngbandMainTermClickableBottomOffset);
	}
	else {
		/* Allow clicks anywhere. */
		clickIsValid = YES;
	}

	if (clickIsValid) {
		/* Encode the mouse button used, along with any modifiers, and pass that
		 * to the terminal. See Term_mousepress() for how to encode the click. */
		byte angbandModifiers = 0;
#ifdef KC_MOD_ALT
		NSEventModifierFlags eventModifiers = [event modifierFlags];
		angbandModifiers |= (eventModifiers & NSShiftKeyMask) ? KC_MOD_SHIFT : 0;
		angbandModifiers |= (eventModifiers & NSControlKeyMask) ? KC_MOD_CONTROL : 0;
		angbandModifiers |= (eventModifiers & NSAlternateKeyMask) ? KC_MOD_ALT : 0;
		angbandModifiers = (angbandModifiers & 0x0F) << 4;
#endif
		Term_mousepress(x, y, angbandMouseButton | angbandModifiers);
	}
}

- (void)mouseUp: (NSEvent *)event
{
	[self handleMouseButton: event angbandButtonIndex: AngbandButtonIndexLeftMouse];
	[[self nextResponder] mouseUp: event];
}

- (void)rightMouseUp: (NSEvent *)event
{
	[self handleMouseButton: event angbandButtonIndex: AngbandButtonIndexRightMouse];
	[[self nextResponder] rightMouseUp: event];
}

#pragma mark -
#pragma mark AngbandTermViewDataSource Methods

- (AngbandTerminalEntity)termView: (NSView <AngbandTermViewDrawing> * __nonnull)termView terminalEntityAtX: (NSInteger)x y: (NSInteger)y
{
	if (_terminalEntities == NULL || x >= self.configuration.columns || y >= self.configuration.rows) {
		return AngbandTerminalEntityNull;
	}

	return _terminalEntities[y * self.configuration.columns + x];
}

- (CGRect)cursorRectForTermView: (NSView <AngbandTermViewDrawing> * __nonnull)termView
{
	return self.cursorRect;
}

- (BOOL)graphicsEnabledForTermView: (NSView <AngbandTermViewDrawing> * __nonnull)termView
{
	return AngbandGraphicsEnabled();
}

#pragma mark -
#pragma mark Terminal Callback Methods

- (NSInteger)handleCursorUpdateWithInfo: (AngbandTerminalUpdateInfo * __nonnull)update
{
	if (update == NULL) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"Info struct was null for cursor update." userInfo: nil] raise];
		return -1;
	}

	self.cursorRect = [self rectForEntitiesAtX: update->x y: update->y count: 1];
	[self.terminalView setNeedsDisplayInRect: NSRectFromCGRect(self.cursorRect)];
	return ERRR_NONE;
}

- (NSInteger)handleWipeWithInfo: (AngbandTerminalUpdateInfo * __nonnull)update
{
	if (update == NULL) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"Info struct was null for wipe." userInfo: nil] raise];
		return -1;
	}

	if (_terminalEntities == NULL) {
		[[NSException exceptionWithName: NSInternalInconsistencyException reason: @"Entity buffer was null." userInfo: nil] raise];
		return -1;
	}

	int base = update->y * (int)self.configuration.columns + update->x;

	for (int i = 0; i < update->count; i++) {
		_terminalEntities[base + i] = AngbandTerminalEntityNull;
	}

	[self resetCursorPosition];
	[self.terminalView setNeedsDisplayInRect: NSRectFromCGRect([self rectForEntitiesAtX: update->x y: update->y count: update->count])];

	return ERRR_NONE;
}

- (NSInteger)handleTextUpdateWithInfo: (AngbandTerminalUpdateInfo * __nonnull)update
{
	if (update == NULL) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"Info struct was null for text update." userInfo: nil] raise];
		return -1;
	}

	if (update->featureChars == NULL || update->featureAttrs == NULL) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"Character or attribute buffer was null for text update." userInfo: nil] raise];
		return -1;
	}

	if (_terminalEntities == NULL) {
		[[NSException exceptionWithName: NSInternalInconsistencyException reason: @"Entity buffer was null during text update." userInfo: nil] raise];
		return -1;
	}

	int base = update->y * (int)self.configuration.columns + update->x;

	for (int i = 0; i < update->count; i++) {
		_terminalEntities[base + i].character = update->featureChars[i];
		_terminalEntities[base + i].attributes = update->featureAttrs[0];
	}

	[self resetCursorPosition];
	[self.terminalView setNeedsDisplayInRect: NSRectFromCGRect([self rectForEntitiesAtX: update->x y: update->y count: update->count])];

	return ERRR_NONE;
}

- (NSInteger)handlePictUpdateWithInfo: (AngbandTerminalUpdateInfo * __nonnull)update
{
	if (update == NULL) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"Info struct was null for pict update." userInfo: nil] raise];
		return -1;
	}

	if (update->featureChars == NULL || update->featureAttrs == NULL || update->terrainChars == NULL || update->terrainAttrs == NULL) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"Character or attribute buffer was null for pict update." userInfo: nil] raise];
		return -1;
	}

	if (_terminalEntities == NULL) {
		[[NSException exceptionWithName: NSInternalInconsistencyException reason: @"Entity buffer was null during pict update." userInfo: nil] raise];
		return -1;
	}

	int base = update->y * (int)self.configuration.columns + update->x;

	for (int i = 0; i < update->count; i++) {
		_terminalEntities[base + i].character = update->featureChars[i];
		_terminalEntities[base + i].attributes = update->featureAttrs[i];
		_terminalEntities[base + i].terrainCharacter = update->terrainChars[i];
		_terminalEntities[base + i].terrainAttributes = update->terrainAttrs[i];
	}

	[self resetCursorPosition];
	[self.terminalView setNeedsDisplayInRect: NSRectFromCGRect([self rectForEntitiesAtX: update->x y: update->y count: update->count])];

	return ERRR_NONE;
}

- (NSInteger)handleClearTerm
{
	[self resetCursorPosition];
	[self resetEntityBuffer];
	[self.terminalView setNeedsDisplay: YES];
	return ERRR_NONE;
}

#pragma mark -
#pragma mark NSWindowDelegate Methods

- (void)windowDidEndLiveResize: (NSNotification *)notification
{
	if (self.automaticResizeInProgress) {
		/* A resize has been triggered programmatically, and we don't want any
		 * configuration updates. */
		return;
	}

	NSWindow *window = [notification object];
	NSRect contentRect = [window contentRectForFrameRect: [window frame]];
	[self resizeTerminalWithContentRect: contentRect saveToDefaults: YES];
}

- (void)windowDidEnterFullScreen: (NSNotification *)notification
{
	NSWindow *window = [notification object];
	NSRect contentRect = [window contentRectForFrameRect: [window frame]];
	[self resizeTerminalWithContentRect: contentRect saveToDefaults: NO];
}

- (void)windowDidExitFullScreen: (NSNotification *)notification
{
	NSWindow *window = [notification object];
	NSRect contentRect = [window contentRectForFrameRect: [window frame]];
	[self resizeTerminalWithContentRect: contentRect saveToDefaults: NO];
}

- (void)windowDidBecomeMain: (NSNotification *)notification
{
	NSWindow *window = [notification object];

	if (window != self) {
		return;
	}

	NSMenuItem *item = [[[NSApplication sharedApplication] windowsMenu] itemWithTag: AngbandWindowMenuItemTagBase + self.configuration.index];
	[item setState: NSOnState];

	/* Update the font in case the font panel is visible. */
	[[NSFontManager sharedFontManager] setSelectedFont: self.configuration.font isMultiple: NO];
}

- (void)windowDidResignMain: (NSNotification *)notification
{
	NSWindow *window = [notification object];

	if (window != self) {
		return;
	}

	NSMenuItem *item = [[[NSApplication sharedApplication] windowsMenu] itemWithTag: AngbandWindowMenuItemTagBase + self.configuration.index];
	[item setState: NSOffState];
}

- (void)windowWillClose: (NSNotification *)notification
{
	[self saveWindowVisibleToDefaults: NO];
}

@end
