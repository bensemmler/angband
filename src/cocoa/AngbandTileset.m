/**
 * \file AngbandTileset.m
 * \brief Class to manage graphic tileset resources.
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

#import "AngbandTileset.h"

#import "AngbandCommon.h"

@interface AngbandTileset ()
@property (nonatomic, assign, readwrite) CGImageRef __nullable image;
@property (nonatomic, assign, readwrite) CGSize imageSize;
@property (nonatomic, assign, readwrite) CGSize tileSize;
@property (nonatomic, assign, readwrite) NSInteger columns;
@property (nonatomic, assign, readwrite) NSInteger rows;
@property (nonatomic, copy) NSURL *fileURL;
@end

@implementation AngbandTileset

@synthesize columns=_columns;
@synthesize fileURL=_fileURL;
@synthesize image=_image;
@synthesize imageSize=_imageSize;
@synthesize rows=_rows;
@synthesize tileSize=_tileSize;

#pragma mark -
#pragma mark Instance Setup and Teardown

- (instancetype __nullable)initWithFileURL: (NSURL * __nullable)fileURL tileSize: (CGSize)tileSize
{
	if ((self = [super init])) {
		_image = NULL;
		_imageSize = CGSizeZero;
		_tileSize = tileSize;
		_columns = 0;
		_rows = 0;
		_fileURL = [fileURL copy];
	}

	return self;
}

- (instancetype __nullable)init
{
	return [self initWithFileURL: nil tileSize: CGSizeZero];
}

- (void)dealloc
{
	if (_image != NULL) {
		CGImageRelease(_image);
		_image = NULL;
	}

	[_fileURL release];
	[super dealloc];
}

#pragma mark -
#pragma mark Other Methods

/**
 * Actually load the image that is provided in the \c fileURL property.
 *
 * \return YES if the image was loaded successfully, NO if there was an error.
 */
- (BOOL)loadImage
{
	if (self.image != NULL) {
		/* The image is already loaded, so we don't want to load again. */
		return YES;
	}

	if (self.fileURL == nil) {
		return NO;
	}

	NSDictionary *options = [[NSDictionary alloc] initWithObjectsAndKeys: (id)kCFBooleanTrue, kCGImageSourceShouldCache, nil];
	CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)self.fileURL, (CFDictionaryRef)options);

	if (source == NULL) {
		[options release];
		return NO;
	}

	CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, (CFDictionaryRef)options);
	[options release];
	CFRelease(source);

	if (image == NULL) {
		return NO;
	}

	self.imageSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
	self.columns = floor(CGImageGetWidth(image) / self.tileSize.width);
	self.rows = floor(CGImageGetHeight(image) / self.tileSize.height);

	if (self.columns == 0 || self.rows == 0) {
		return NO;
	}

	self.image = CGImageRetain(image);
	return YES;
}

/**
 * Find the origin in the tileset image of the tile for the given values.
 *
 * \param attributes The attributes value which defines a row in the tileset
 *        image.
 * \param character The character value which defines a column in the tileset
 *        image.
 * \return The origin point of the tile in the image.
 */
- (CGPoint)originForEntityAttributes: (int)attributes character: (wchar_t)character
{
	NSUInteger row = ((byte)attributes & AngbandTerminalEntityValueMask) % self.rows;
	NSUInteger column = ((byte)character & AngbandTerminalEntityValueMask) % self.columns;
	return CGPointMake(column * self.tileSize.width, row * self.tileSize.height);
}

/**
 * Determine the bounds of the feature tile in the tileset image for an entity.
 *
 * \param entity The entity that should be used to find the corresponding tile.
 * \return The bounds of the tile in the tileset image or \c CGRectZero if it
 *         could not be found.
 */
- (CGRect)boundsForFeatureTileWithEntity: (AngbandTerminalEntity * __nonnull)entity
{
	if (entity == NULL) {
		return CGRectZero;
	}

	CGPoint origin = [self originForEntityAttributes: entity->attributes character: entity->character];
	return CGRectMake(origin.x, origin.y, self.tileSize.width, self.tileSize.height);
}

/**
 * Determine the bounds of the terrain tile in the tileset image for an entity.
 *
 * \param entity The entity that should be used to find the corresponding tile.
 * \return The bounds of the tile in the tileset image or \c CGRectZero if it
 *         could not be found.
 */
- (CGRect)boundsForTerrainTileWithEntity: (AngbandTerminalEntity * __nonnull)entity
{
	if (entity == NULL) {
		return CGRectZero;
	}

	CGPoint origin = [self originForEntityAttributes: entity->terrainAttributes character: entity->terrainCharacter];
	return CGRectMake(origin.x, origin.y, self.tileSize.width, self.tileSize.height);
}

/**
 * Creates a new tileset instance, with the image loaded as needed.
 *
 * \param path The path to the image file.
 * \param tileWidth The width of a tile in the image.
 * \param tileHeight The height of a tile in the image.
 * \return A tileset that is ready for use, or nil if the tileset could not be
 *         created.
 */
+ (instancetype __nullable)imageTilesetAtPath: (NSString * __nonnull)path tileWidth: (CGFloat)tileWidth tileHeight: (CGFloat)tileHeight
{
	if ([path length] == 0 || tileWidth < 1.0 || tileHeight < 1.0) {
		return nil;
	}

	NSURL *fileURL = [[NSURL alloc] initFileURLWithPath: path];
	AngbandTileset *tileset = [[[self class] alloc] initWithFileURL: fileURL tileSize: CGSizeMake(tileWidth, tileHeight)];
	[fileURL release];

	if ([tileset loadImage]) {
		/* The image was loaded and we have a valid tileset. */
		return [tileset autorelease];
	}
	else {
		return nil;
	}
}

@end
