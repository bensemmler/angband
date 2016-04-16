/**
 * \file AngbandDefaultTermView.m
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

#import "AngbandDefaultTermView.h"

#import "AngbandCommon.h"
#import "AngbandTermConfiguration.h"
#import "AngbandTermViewDataSource.h"
#import "AngbandTileset.h"
#import "NSColor+AngbandTermColor.h"

extern BOOL AngbandGraphicsEnabled(void);

@interface AngbandDefaultTermView ()
@property (nonatomic, assign) BOOL dataSourceValid;
@property (nonatomic, assign) BOOL tileSizeSeemsIntegral;
@property (nonatomic, assign) CGFloat preferredAdvance;
@property (nonatomic, assign) CGSize tileSize;
@property (nonatomic, assign) char *UTF8FontName;
@property (nonatomic, retain) NSFont * __nullable drawingFont;
@end

@implementation AngbandDefaultTermView

@synthesize UTF8FontName=_UTF8FontName;
@synthesize cursorColor=_cursorColor;
@synthesize dataSource=_dataSource;
@synthesize dataSourceValid=_dataSourceValid;
@synthesize drawingFont=_drawingFont;
@synthesize preferredAdvance=_preferredAdvance;
@synthesize tileSize=_tileSize;
@synthesize tileSizeSeemsIntegral=_tileSizeSeemsIntegral;
@synthesize tileset=_tileset;
@synthesize wipeColor=_wipeColor;

#pragma mark -
#pragma mark Instance Setup and Teardown

- (instancetype)initWithFrame: (NSRect)frame
{
	if ((self = [super initWithFrame: frame])) {
		_UTF8FontName = NULL;
		_cursorColor = [[NSColor yellowColor] retain];
		_dataSource = nil;
		_dataSourceValid = NO;
		_drawingFont = nil;
		_preferredAdvance = 0.0;
		_tileSize = CGSizeZero;
		_tileSizeSeemsIntegral = NO;
		_tileset = nil;
		_wipeColor = [[NSColor blackColor] retain];
	}

	return self;
}

- (void)dealloc
{
	if (_UTF8FontName != NULL) {
		free(_UTF8FontName);
		_UTF8FontName = NULL;
	}

	[_wipeColor release];
	[_cursorColor release];
	[_drawingFont release];
	[_tileset release];
	[super dealloc];
}

#pragma mark -
#pragma mark Superclass Overrides

- (BOOL)isOpaque
{
	return YES;
}

- (BOOL)isFlipped
{
	return YES;
}

#pragma mark -
#pragma mark Drawing



BOOL AngbandTerminalEntityIsGraphic( AngbandTerminalEntity entity )
{
	// we only need to check the feature char/attribute
	return ((entity.attributes & AngbandTerminalEntityGraphicMask) && (entity.character & AngbandTerminalEntityGraphicMask));
}

- (void)drawGridInContext: (CGContextRef)context
{
	if( self.tileSize.width < 1.0 || self.tileSize.height < 1.0 )
	{
		return;
	}

	CGContextSaveGState( context );
	CGContextSetStrokeColorWithColor( context, [[NSColor darkGrayColor] CGColor] );

	for( CGFloat currentX = self.tileSize.width; currentX <= NSMaxX( self.bounds ); currentX += self.tileSize.width )
	{
		CGPoint start = CGPointMake( ceil(currentX) + 0.5, 0.5 );
		CGPoint end = CGPointMake( ceil(currentX) + 0.5, ceil(NSMaxY( self.bounds )) + 0.5 );
		CGPoint points[2] = {start, end};
		CGContextStrokeLineSegments( context, points, 2 );
	}

	for( CGFloat currentY = self.tileSize.height; currentY <= NSMaxY( [self bounds] ); currentY += self.tileSize.height )
	{
		CGPoint start = CGPointMake( 0.5, ceil(currentY) + 0.5 );
		CGPoint end = CGPointMake( ceil(NSMaxX( [self bounds] )) + 0.5, ceil(currentY) + 0.5 );
		CGPoint points[2] = {start, end};
		CGContextStrokeLineSegments( context, points, 2 );
	}

	CGContextRestoreGState( context );
}

- (void)drawWChar: (wchar_t)wchar inRect: (CGRect)rect withPreferredAdvance: (CGFloat)preferredAdvance context: (CGContextRef)context
{
	/* Get the Unicode glyph from the current font. */
	NSFont *screenFont = self.drawingFont;
	UniChar unicharString[2] = {(UniChar)wchar, 0};
	CGGlyph thisGlyphArray[1] = {0};
	CTFontGetGlyphsForCharacters((CTFontRef)screenFont, unicharString, thisGlyphArray, 1);
	CGGlyph glyph = thisGlyphArray[0];

	/* If we're using a fractional-width font, adjust some metrics so that the
	 * characters stay in a grid. */

	double compressionRatio = 1.0;
	CGFloat tileOffsetX = (CGRectGetWidth(rect) - preferredAdvance) / 2.0;

	if (![screenFont isFixedPitch]) {
		/* Get the glyph's advance. */
		CGSize advances[1] = {CGSizeZero};
		CTFontGetAdvancesForGlyphs((CTFontRef)screenFont, kCTFontHorizontalOrientation, thisGlyphArray, advances, 1);
		CGSize advance = advances[0];

		/* If our font is not monospaced, our tile width is deliberately not big
		 * enough for every character. In that event, if our glyph is too wide,
		 * we need to compress it horizontally. Compute the compression ratio.
		 * 1.0 means no compression. */

		if (advance.width <= CGRectGetWidth(rect)) {
			/* Our glyph fits, so we can just draw it, possibly with an offset. */
			compressionRatio = 1.0;
			tileOffsetX = (CGRectGetWidth(rect) - advance.width) / 2.0;
		}
		else {
			/* Our glyph doesn't fit, so we'll have to compress it. */
			compressionRatio = CGRectGetWidth(rect) / advance.width;
			tileOffsetX = 0;
		}
	}

	//	/* Get the text matrix, scale horizontally by the compression ration and
	//	 * flip vertically, since we're in a flipped coordinate system. */
	//	CGAffineTransform originalTextMatrix = CGContextGetTextMatrix(context);
	//	CGAffineTransform scaledTextMatrix = CGAffineTransformScale(originalTextMatrix, compressionRatio, -1.0);
	//
	//	/* Create a translation and set that as the position of the text matrix. The
	//	 * tile origin is upper-left, so adjust to draw from the font baseline. */
	//	CGAffineTransform translate = CGAffineTransformMakeTranslation(CGRectGetMinX(rect) + tileOffsetX, CGRectGetMinY(rect) + _drawingFontAscent);
	//	CGAffineTransform drawingTextMatrix = CGAffineTransformConcat(scaledTextMatrix, translate);
	//
	//	/* Draw the glyph with the adjust text matrix, and then restore the old
	//	 * matrix so that we don't mess up other drawing. */
	//	CGContextSetTextMatrix(context, drawingTextMatrix);
	//	CGContextShowGlyphsWithAdvances(context, &glyph, &CGSizeZero, 1);
	//	CGContextSetTextMatrix(context, originalTextMatrix);

	CGAffineTransform original = CGContextGetTextMatrix( context );
	CGAffineTransform compressed = CGAffineTransformScale( original, compressionRatio, 1.0 );

	CGContextSetTextMatrix( context, compressed );

	CGContextSetTextPosition( context, CGRectGetMinX( rect ) + tileOffsetX, CGRectGetMinY( rect ) + [screenFont ascender] );
	CGContextShowGlyphsWithAdvances( context, &glyph, &CGSizeZero, 1 );

	CGContextSetTextMatrix( context, original );


}

/**
 * Draw a graphic tile to the screen from the tileset image. This uses a fairly
 * fast (in the common case) method of manipulating the CTM to draw the desired
 * tile.
 *
 * Currently, this implementation has a few extra vertical flips that could
 * possibly be eliminated, but this seems to work well enough.
 *
 * \param tileset A tileset object.
 * \param sourceRect The rect in \c sourceImage containing the tile to be drawn.
 * \param destinationRect The location in \c context where the tile should be
 *        drawn.
 * \param blendMode The blend mode which will be used to draw the new tile. A
 *        tile can be drawn on top of another, so transparency should be taken
 *        into account.
 * \param context The graphics context to draw to.
 */
- (void)drawTileFromTileset: (AngbandTileset * __nonnull)tileset sourceRect: (CGRect)sourceRect toDestinationRect: (CGRect)destinationRect mode: (CGBlendMode)blendMode context: (CGContextRef)context
{
	if (tileset == nil) {
		return;
	}

	CGContextSaveGState(context);

	CGRect flippedRect = CGRectApplyAffineTransform(destinationRect, CGAffineTransformMakeScale(1.0, -1.0));
	CGContextScaleCTM(context, 1.0, -1.0);
	CGContextSetBlendMode(context, blendMode);

	/* Translate the context so that (0, 0) is where we want to draw the tile. */
	CGContextTranslateCTM(context, CGRectGetMinX(flippedRect), CGRectGetMinY(flippedRect));

	/* Change the scaling so that the tile fits into the space properly. */
	CGFloat horizontalRatio = CGRectGetWidth(flippedRect) / CGRectGetWidth(sourceRect);
	CGFloat verticalRatio = CGRectGetHeight(flippedRect) / CGRectGetHeight(sourceRect);
	CGContextScaleCTM(context, horizontalRatio, verticalRatio);

	/* Set the context to clip to the size of just one tile, since we're drawing
	 * the entire image. The actual clipping rect will be adjusted appropriately
	 * for the given CTM scale. */
	CGContextClipToRect(context, CGRectMake(0.0, 0.0, CGRectGetWidth(sourceRect), CGRectGetHeight(sourceRect)));

	/* Draw the tileset image such that the tile we actually want is in the clip
	 * region of the context. Even though we're using the whole image, the
	 * system is smart enough to only draw the part of the image that will not
	 * be clipped. */
	CGFloat imageWidth = tileset.imageSize.width;
	CGFloat imageHeight = tileset.imageSize.height;
	CGRect imageRect = CGRectMake(-CGRectGetMinX(sourceRect), -(imageHeight - CGRectGetMaxY(sourceRect)), imageWidth, imageHeight);
	CGContextDrawImage(context, imageRect, tileset.image);

	CGContextRestoreGState(context);
}

/**
 * Draw the cursor in the given rect. The appearance of the cursor is completely
 * based on implementation.
 *
 * \param rect The rect that the cursor should highlight. Normally, this is just
 *        one tile. Drawing may occur outside of this rect.
 * \param context The graphics context to draw to.
 */
- (void)drawCursorInRect: (CGRect)rect context: (CGContextRef)context
{
	if (CGRectEqualToRect(rect, CGRectZero)) {
		return;
	}

	CGContextSaveGState(context);

	/* Offset the rect so that we're drawing full pixels instead of between. */
	static CGFloat const borderWidth = 1.0;
	CGRect pixelRect = CGRectInset(rect, borderWidth / 2.0, borderWidth / 2.0);
	CGContextSetStrokeColorWithColor(context, [self.cursorColor CGColor]);
	CGContextStrokeRectWithWidth(context, pixelRect, borderWidth);

	CGContextRestoreGState(context);
}

/**
 * "Erase" the specified rect using the wipe color.
 *
 * \param rect The rect to wipe.
 * \param context The graphics context to draw to.
 */
- (void)wipeRect: (CGRect)rect context: (CGContextRef)context
{
	CGContextSaveGState(context);
	CGContextSetFillColorWithColor(context, [self.wipeColor CGColor]);
	CGContextFillRect(context, rect);
	CGContextRestoreGState(context);
}

- (void)printEntityInfoAtX: (int)x y: (int)y
{
	AngbandTerminalEntity entity = AngbandTerminalEntityNull;

	if (self.dataSource != nil && [self.dataSource respondsToSelector: @selector(termView:terminalEntityAtX:y:)]) {
		entity = [self.dataSource termView: self terminalEntityAtX: x y: y];
	}

	printf("(%03d, %03d): '%lc' % 3d '%lc' % 3d", x, y, entity.character, entity.attributes, entity.terrainCharacter, entity.terrainAttributes);

	if (AngbandGraphicsEnabled() && self.tileset != nil && AngbandTerminalEntityIsGraphic(entity)) {
		CGRect featureRect = [self.tileset boundsForFeatureTileWithEntity: &entity];
		CGRect terrainRect = [self.tileset boundsForTerrainTileWithEntity: &entity];
		printf(" c: {%0.1f %0.1f %0.1f %0.1f}", featureRect.origin.x, featureRect.origin.y, featureRect.size.width, featureRect.size.height);
		printf(" t: {%0.1f %0.1f %0.1f %0.1f}", terrainRect.origin.x, terrainRect.origin.y, terrainRect.size.width, terrainRect.size.height);
	}

	printf("\n");
}

- (void)drawRect: (NSRect)unionedRect
{
	CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
	CGContextSaveGState(context);

	BOOL graphicsEnabled = NO;

	if (self.dataSourceValid) {
		graphicsEnabled = [self.dataSource graphicsEnabledForTermView: self];
	}

	/* We have to use CGContextSelectFont because CGContextSetFont and bridging
	 * weren't working. Also, we can't use -[NSFont setInContext:], since that
	 * limits us to Cocoa string drawing (it clobbers CGContext settings). */
	CGContextSelectFont(context, self.UTF8FontName, [self.drawingFont pointSize], kCGEncodingFontSpecific);

	/* Next, we need to reset the text matrix. We use the transform identity (to
	 * make sure that we use the selected font size), and then flip it to match
	 * our flipped coordinate system. The positioning of the text will be done
	 * later. The original matrix is saved, since it's not part of the graphics
	 * state. We restore it when we're done drawing everything. */
	CGAffineTransform originalTextMatrix = CGContextGetTextMatrix(context);
	CGAffineTransform flippedMatrix = CGAffineTransformScale(CGAffineTransformIdentity, 1.0, -1.0);
	CGContextSetTextMatrix(context, flippedMatrix);

	/* There is always at least one rect needing update (the unioned rect passed
	 * in to drawRect:. We set rectCount to 1 so that the loop below runs. */
	NSInteger rectCount = 1;
	NSRect const *updatedRects = NULL;

	if (self.tileSizeSeemsIntegral) {
		/* If the tile values are fractional, we're just going to use the entire
		 * unioned rect that is passed in. This eliminates problems with the
		 * point-to-term coordinate conversion (which then causes weird redraw
		 * problems). For integral tile sizes, we are able to draw just the
		 * tiles that have been updated. The root cause for doing this is how
		 * NSView handles fractional rects in setNeedsDisplayInRect:. It will
		 * round the rect and then create another one with a 1 point height or
		 * width. */
		[self getRectsBeingDrawn: &updatedRects count: &rectCount];
	}

//	if (self.overlayView != nil) {
//		[self.overlayView updateDisplayRects: updatedRects count: rectCount];
//		[self.overlayView updateUnionedRect: unionedRect];
//	}

	/* Get the individual areas in our view that actually need redrawing. */
	for (NSInteger rectIndex = 0; rectIndex < rectCount; rectIndex++) {
		NSRect rect = (updatedRects != NULL) ? updatedRects[rectIndex] : unionedRect;
		NSInteger termMinX = floor(NSMinX(rect) / self.tileSize.width);
		NSInteger termMinY = floor(NSMinY(rect) / self.tileSize.height);
		NSInteger termWidth = ceil(NSWidth(rect) / self.tileSize.width);
		NSInteger termHeight = ceil(NSHeight(rect) / self.tileSize.height);

		/* Clear the space we are drawing into. For tiles with integral sizes,
		 * this isn't necessary, as the character rect is filled anyway. If we
		 * don't do this for fractional tile sizes, we'll get a bunch of faint
		 * grid lines. */
		[self wipeRect: NSRectToCGRect(rect) context: context];

		/* Draw each tile in the redraw area. */
		for (int y = termMinY; y < termMinY + termHeight; y++) {
			for (int x = termMinX; x < termMinX + termWidth; x++) {
				AngbandTerminalEntity entity = AngbandTerminalEntityNull;

				if (self.dataSourceValid	) {
					entity = [self.dataSource termView: self terminalEntityAtX: x y: y];
				}

				CGRect charRect = CGRectMake(x * self.tileSize.width, y * self.tileSize.height, self.tileSize.width, self.tileSize.height);

				if (graphicsEnabled && self.tileset != nil && AngbandTerminalEntityIsGraphic(entity)) {
					CGRect featureRect = [self.tileset boundsForFeatureTileWithEntity: &entity];
					CGRect terrainRect = [self.tileset boundsForTerrainTileWithEntity: &entity];
					[self drawTileFromTileset: self.tileset sourceRect: terrainRect toDestinationRect: charRect mode: kCGBlendModeCopy context: context];
					[self drawTileFromTileset: self.tileset sourceRect: featureRect toDestinationRect: charRect mode: kCGBlendModeNormal context: context];
				}
				else {
					CGContextSetFillColorWithColor(context, [[NSColor angband_backgroundColorForAttribute: entity.attributes] CGColor]);
					CGContextFillRect(context, charRect);

					/* Check for a few cases where the character will be pretty
					 * much invisible and prevent drawing (for performance). */
					BOOL characterWillBeInvisible = (entity.character == L' ' || entity.character == L'\0' || (entity.attributes / MAX_COLORS == BG_SAME));

					if (!characterWillBeInvisible) {
						CGContextSetFillColorWithColor(context, [[NSColor angband_colorForTermColorIndex: entity.attributes] CGColor]);
						[self drawWChar: entity.character inRect: charRect withPreferredAdvance: self.preferredAdvance context: context];
					}
				}
			}
		}
	}

	/* Draw the cursor on top of everything. */
	if (self.dataSourceValid)
	{
		CGRect cursorRect = [self.dataSource cursorRectForTermView: self];
		[self drawCursorInRect: cursorRect context: context];
	}

	/* Reset the context to prevent messed up drawing elsewhere. */
	CGContextSetTextMatrix(context, originalTextMatrix);
	CGContextRestoreGState(context);


//	[self drawGridInContext: context];
}




#pragma mark -
#pragma mark AngbandTermViewDrawing Methods

- (void)updateConfiguration: (AngbandTermConfiguration * __nonnull)configuration
{
	if (configuration == nil) {
		[[NSException exceptionWithName: NSInvalidArgumentException reason: @"A non-nil configuration must be provided to updateConfiguration." userInfo: nil] raise];
		return;
	}

	if (!NSEqualRects([self frame], NSRectFromCGRect([configuration preferredContentBounds]))) {
		[self setFrame: NSRectFromCGRect([configuration preferredContentBounds])];
	}

	self.drawingFont = configuration.font;
	self.tileSize = configuration.tileSize;
	self.preferredAdvance = configuration.preferredAdvance;

	/* Preflight some things so that we don't need to constantly do them in
	 * drawRect:. */
	self.tileSizeSeemsIntegral = (self.tileSize.width - floor(self.tileSize.width) < 0.001 && self.tileSize.height - floor(self.tileSize.height) < 0.001);

	if (self.UTF8FontName != NULL) {
		free(self.UTF8FontName);
		self.UTF8FontName = NULL;
	}

	const char *UTF8FontName = [[self.drawingFont fontName] UTF8String];
	self.UTF8FontName = calloc(strlen(UTF8FontName) + 1, sizeof(char));
	strncpy(self.UTF8FontName, UTF8FontName, strlen(UTF8FontName));
}

#pragma mark -
#pragma mark Accessors

- (void)setDataSource: (id <AngbandTermViewDataSource>)dataSource
{
	/* Preflight some checks so that we don't need to constantly do them in 
	 * drawRect:. */
	BOOL dataSourceValid = YES;
	dataSourceValid = dataSourceValid && (dataSource != nil);
	dataSourceValid = dataSourceValid && [dataSource respondsToSelector: @selector(cursorRectForTermView:)];
	dataSourceValid = dataSourceValid && [dataSource respondsToSelector: @selector(termView:terminalEntityAtX:y:)];
	dataSourceValid = dataSourceValid && [dataSource respondsToSelector: @selector(graphicsEnabledForTermView:)];
	self.dataSourceValid = dataSourceValid;
	_dataSource = dataSource;
}

- (void)setWipeColor: (NSColor * __nullable)wipeColor
{
	if (wipeColor != _wipeColor) {
		[_wipeColor release];
		_wipeColor = [wipeColor retain];
	}

	if (_wipeColor == nil) {
		_wipeColor = [[NSColor blackColor] retain];
	}
}

- (void)setCursorColor: (NSColor * __nullable)cursorColor
{
	if (cursorColor != _cursorColor) {
		[_cursorColor release];
		_cursorColor = [cursorColor retain];
	}

	if (_cursorColor == nil) {
		_cursorColor = [[NSColor yellowColor] retain];
	}
}

@end
