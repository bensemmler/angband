/**
 * \file main-cocoa.m
 * \brief OS X front end
 *
 * Copyright (c) 2011 Peter Ammon
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

#if defined(MACH_O_CARBON)

#import "cocoa/AngbandCommon.h"
#import "cocoa/AngbandDefaultTermView.h"
#import "cocoa/AngbandSoundPlaying.h"
#import "cocoa/AngbandTermWindow.h"
#import "grafmode.h"
#import "init.h"
#import "ui-display.h" /* window flags */
#import "ui-game.h" /* savefile, save_game() */
#import "ui-init.h" /* textui_init() */
#import "ui-input.h" /* inkey_flag, get_file */
#import "ui-output.h" /* prt() */
#import "ui-prefs.h" /* use_graphics */
#import "ui-term.h"
#import "ui-command.h" /* do_cmd_redraw() */


extern NSModalResponse AngbandRunAlertPanel(NSString * __nullable title, NSString * __nullable message, NSString * __nullable defaultButtonTitle, BOOL showCancelButton);
extern void AngbandSetCurrentSaveFilePath(NSString * __nonnull path);

static BOOL AngbandApplicationShouldQuitNow = NO;

/**
 * Generate a mask for the available subwindow flags. Subwindow availability is
 * determined by the descriptions for the subwindows in \c window_flag_desc.
 *
 * \return A mask corresponding to what subwindow flags are actually available.
 */
u32b AngbandWindowSubwindowFlagsMask(void)
{
	int windowFlagBits = sizeof(*window_flag) * CHAR_BIT;
	int maxBits = MINN(PW_MAX_FLAGS, windowFlagBits);
	u32b mask = 0;

	for (int i = 0; i < maxBits; i++) {
		if (window_flag_desc[i] != NULL) {
			mask |= (1 << i);
		}
	}

	return mask;
}

/**
 * Update subwindow flags for all windows. Depending on the changes, windows may
 * automatically open and close, regardless of user preference. Avoid calling
 * this function frequently, if possible.
 *
 * \param forceVisibilityOnFlagsEnabled If YES, any subwindows that are enabled
 *        will be made visible, regardless of user preference.
 */
static void AngbandWindowUpdateVisibility(BOOL forceVisibilityOnFlagsEnabled)
{
	/* The subwindow flags is determined at build time, so we only need to set
	 * this mask once. This also assumes that there is at least one subwindow
	 * option available. */
	static u32b subwindowFlagsMask = 0;

	if (subwindowFlagsMask == 0) {
		subwindowFlagsMask = AngbandWindowSubwindowFlagsMask();
	}

	for (int i = 1; i < ANGBAND_TERM_MAX; i++) {
		if (angband_term[i] == NULL) {
			continue;
		}

		AngbandTermWindow *window = (AngbandTermWindow *)angband_term[i]->data;

		if (window == nil) {
			continue;
		}

		u32b newFlags = window_flag[i] & subwindowFlagsMask;

		if (window.subwindowFlags == newFlags) {
			/* Nothing to do, continuing for efficiency. */
			continue;
		}

		BOOL shouldShowWindowWithUpdatedFlags = NO;

		if (forceVisibilityOnFlagsEnabled && newFlags > 0 && window.subwindowFlags == 0) {
			/* In the case of a subwindow that was disabled and is now enabled,
			 * we want to make it visible, regardless of user preference, so
			 * that it's obvious that something changed. It's also likely that
			 * if the user enabled a subwindow, they actually do want it. */
			shouldShowWindowWithUpdatedFlags = YES;
		}

		window.subwindowFlags = newFlags;

		BOOL windowCanBeVisible = (window.subwindowFlags > 0);
		BOOL userWantsWindowVisible = [window windowVisibleUsingDefaults];

		if (windowCanBeVisible && userWantsWindowVisible) {
			[window orderFront: nil];
		}
		else if (windowCanBeVisible && !userWantsWindowVisible) {
			if (shouldShowWindowWithUpdatedFlags) {
				[window orderFront: nil];
				[window saveWindowVisibleToDefaults: YES];
			}
			else {
				[window orderOut: nil];
			}
		}
		else if (!windowCanBeVisible) {
			/* The subwindow is disabled and thus cannot be visible, regardless
			 * of the user's preference. */
			[window orderOut: nil];
		}
	}

	/* Ensure that the main window is visible and key to get events. */
	AngbandTermWindow *mainWindow = (AngbandTermWindow *)angband_term[0]->data;
	[mainWindow makeKeyAndOrderFront: nil];
}

/**
 * Log messages to the system log.
 *
 * \param message If null, nothing is logged. Otherwise, the message will be
 *        logged using \c NSLog().
 */
static void cocoa_plog(const char *message)
{
	if (message != NULL && strlen(message) > 0) {
		NSLog(@"%s", message);
	}
}

/**
 * Handle \c quit() in a way that is safer for OS X. Alert the user if a message
 * is available.
 *
 * \param message If null, no alert will be shown. Otherwise, \c message will be
 *        shown as the informative text of an alert.
 */
static void cocoa_quit(const char *message)
{
	/* Most of the time, when Angband's quit() is called, it's because of an
	 * unrecoverable error. These usually have a message passed in. Calls to
	 * quit() without a message generally indicate a more normal quit, but just
	 * in a place that doesn't follow other event handling (such as birth). As
	 * such, we try to inform the user and quit safely. */

	if (message != NULL && strlen(message) > 0) {
		AngbandRunAlertPanel(NSLocalizedStringWithDefaultValue(@"Alert(QuitError).Title", nil, [NSBundle mainBundle], @"Unexpected Angband Error", @"Alert title for when Angband quits unexpectedly, but with a message."),
							 [NSString stringWithFormat: @"%s", message],
							 NSLocalizedStringWithDefaultValue(@"Alert(QuitError).Button(Default).Title", nil, [NSBundle mainBundle], @"Quit", @"Button to dismiss unexpected error alert and quit Angband."),
							 NO);
	}

	/* When this callback is called, we have no choice but to terminate. There's
	 * no way to prevent this, since once it returns, it'll do a hard exit. So,
	 * we'll set our flag and then try to terminate nicely. */
	AngbandApplicationShouldQuitNow = YES;
	[[NSApplication sharedApplication] terminate: nil];
}

/**
 * Do anything that needs to be done to a file that was opened by Angband. For
 * OS X, we use it to set metadata.
 *
 * \param path The path of the opened or created file.
 * \param ftype The type of file Angband opened or created.
 */
static void cocoa_file_open_hook(const char *path, file_type ftype)
{
	NSString *pathString = [NSString stringWithUTF8String: path];

	if ([pathString length] == 0	) {
		return;
	}

	/* Pick a UTI based on the type Angband gives us. This is one step to help
	 * the system figure out the file's type; Angband isn't as picky about file
	 * types and the final UTI may not match exactly. */
	NSString *proposedUTI = nil;

	switch (ftype) {
		case FTYPE_HTML:
			proposedUTI = (NSString *)kUTTypeHTML;
			break;
		case FTYPE_SAVE:
			proposedUTI = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"AngbandFileUTISave"];
			break;
		case FTYPE_TEXT:
			proposedUTI = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"AngbandFileUTIEdit"];
			break;
		case FTYPE_RAW:
		default:
			proposedUTI = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"AngbandFileUTIData"];
			break;
	}

	if (proposedUTI == nil) {
		[[NSException exceptionWithName: NSInternalInconsistencyException reason: @"Proposed UTI was nil. Check Info.plist to make sure required UTI key/value pairs exist." userInfo: nil] raise];
		return;
	}

	/* Get the creator code from the bundle and the type code from a known UTI.
	 * This ensures that the file is linked back to this particular app. */
	NSString *HFSCreator = [[[NSBundle mainBundle] infoDictionary] valueForKey: @"CFBundleSignature"];
	OSType creatorCode = UTGetOSTypeFromString((CFStringRef)HFSCreator);
	CFStringRef HFSType = UTTypeCopyPreferredTagWithClass((CFStringRef)proposedUTI, kUTTagClassOSType);
	OSType typeCode = UTGetOSTypeFromString(HFSType);
	CFRelease(HFSType);

	NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
	[attributes setValue: [NSNumber numberWithUnsignedLong: creatorCode] forKey: NSFileHFSCreatorCode];
	[attributes setValue: [NSNumber numberWithUnsignedLong: typeCode] forKey: NSFileHFSTypeCode];
	[[NSFileManager defaultManager] setAttributes: attributes ofItemAtPath: pathString error: NULL];
	[attributes release];

	if (ftype == FTYPE_SAVE) {
		/* If we're writing to a save file, remember the path. However, the path
		 * that is passed into this function will likely be a temp file, which
		 * will make the path invalid in the future. Using the path in savefile,
		 * however, should give us what we want. We do this here because Angband
		 * automatically saves games and the user isn't prompted for a path. */
		NSString *actualPath = [NSString stringWithUTF8String: savefile];
		AngbandSetCurrentSaveFilePath(actualPath);
	}
}

/**
 * Return a path where a file might be written to. Despite the name, this does
 * not open a file, but allows the user to place a file where they want.
 *
 * \param suggested_name The default name of the file. This can be changed by
 *        the user.
 * \param path On return, contains the path where the file should be written.
 * \param length The size of the buffer for \c path. This function tends to be
 *        called with buffer sizes that aren't big, so be aware if doing stuff
 *        like making a pretty file name.
 */
static bool cocoa_get_file(const char *suggested_name, char *path, size_t length)
{
	NSString *fileName = [NSString stringWithUTF8String: suggested_name];
	NSMutableArray *allowedTypes = [NSMutableArray array];

	if ([[fileName pathExtension] localizedCaseInsensitiveCompare: @"html"] == NSOrderedSame) {
		[allowedTypes addObject: (NSString *)kUTTypeHTML];
	}
	else if ([[fileName pathExtension] localizedCaseInsensitiveCompare: @"txt"] == NSOrderedSame) {
		[allowedTypes addObject: (NSString *)kUTTypePlainText];
	}
	else {
		/* Just add all of the UTIs we know about and let the user pick. */
		[allowedTypes addObject: (NSString *)kUTTypePlainText];
		[allowedTypes addObject: (NSString *)kUTTypeHTML];
		[allowedTypes addObject: [[[NSBundle mainBundle] infoDictionary] valueForKey: @"AngbandFileUTISave"]];
		[allowedTypes addObject: [[[NSBundle mainBundle] infoDictionary] valueForKey: @"AngbandFileUTIEdit"]];
		[allowedTypes addObject: [[[NSBundle mainBundle] infoDictionary] valueForKey: @"AngbandFileUTIData"]];
	}

	NSSavePanel *panel = [NSSavePanel savePanel];
	[panel setNameFieldStringValue: fileName];
	[panel setAllowedFileTypes: allowedTypes];
	[panel setCanCreateDirectories: YES];
	[panel setAllowsOtherFileTypes: YES]; /* Because Angband is weird and inconsistent sometimes. */
// !!!: set default url

	NSInteger result = [panel runModal];

	if (result != NSFileHandlingPanelOKButton) {
		return false;
	}

	if ([[[panel URL] path] getFileSystemRepresentation: path maxLength: length]) {
		return true;
	}
	else {
		// !!!: alert?
		return false;
	}
}

/* From the Linux mbstowcs(3) man page:
 *   If dest is NULL, n is ignored, and the conversion  proceeds  as  above,
 *   except  that  the converted wide characters are not written out to mem‐
 *   ory, and that no length limit exists.
 */
static size_t Term_mbcs_cocoa(wchar_t *dest, const char *src, int n)
{
	int i;
	int count = 0;

	/* Unicode code point to UTF-8
	 *  0x0000-0x007f:   0xxxxxxx
	 *  0x0080-0x07ff:   110xxxxx 10xxxxxx
	 *  0x0800-0xffff:   1110xxxx 10xxxxxx 10xxxxxx
	 * 0x10000-0x1fffff: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
	 * Note that UTF-16 limits Unicode to 0x10ffff. This code is not
	 * endian-agnostic.
	 */
	for (i = 0; i < n || dest == NULL; i++) {
		if ((src[i] & 0x80) == 0) {
			if (dest != NULL) dest[count] = src[i];
			if (src[i] == 0) break;
		} else if ((src[i] & 0xe0) == 0xc0) {
			if (dest != NULL) dest[count] =
				(((unsigned char)src[i] & 0x1f) << 6)|
				((unsigned char)src[i+1] & 0x3f);
			i++;
		} else if ((src[i] & 0xf0) == 0xe0) {
			if (dest != NULL) dest[count] =
				(((unsigned char)src[i] & 0x0f) << 12) |
				(((unsigned char)src[i+1] & 0x3f) << 6) |
				((unsigned char)src[i+2] & 0x3f);
			i += 2;
		} else if ((src[i] & 0xf8) == 0xf0) {
			if (dest != NULL) dest[count] =
				(((unsigned char)src[i] & 0x0f) << 18) |
				(((unsigned char)src[i+1] & 0x3f) << 12) |
				(((unsigned char)src[i+2] & 0x3f) << 6) |
				((unsigned char)src[i+3] & 0x3f);
			i += 3;
		} else {
			/* Found an invalid multibyte sequence */
			return (size_t)-1;
		}
		count++;
	}
	return count;
}

/**
 * Callback from Angband when the game wants to play a sound for an event.
 *
 * \param gameEvent This is a higher level event and doesn't have anything to do
 *        with the sound we want to play.
 * \param eventData Data that contains the actual message type we want to play.
 * \param context The pointer to a Cocoa object that can actually play a sound.
 */
static void AngbandPlaySoundCallback(game_event_type gameEvent, game_event_data *eventData, void *context)
{
	if (eventData == NULL || context == NULL) {
		return;
	}

	int messageType = eventData->message.type;

	if (messageType < 0 || messageType >= MSG_MAX) {
		return;
	}

	id <AngbandSoundPlaying> delegate = (id)context;

	if (delegate != nil && [delegate respondsToSelector: @selector(playRandomSoundForMessageType:)]) {
		[delegate playRandomSoundForMessageType: messageType];
	}
}

void AngbandInitialize(void)
{
	/* Note the "system" */
	ANGBAND_SYS = "mac";

	/* Initialize some save file stuff */
	player_egid = getegid();

	/* Set the command hook */
	cmd_get_hook = textui_get_cmd;

	/* Hooks in some "z-util.c" hooks */
	plog_aux = cocoa_plog;
	quit_aux = cocoa_quit;

	/* Hook in to the file_open routine */
	file_open_hook = cocoa_file_open_hook;

	/* Hook into file saving dialogue routine */
	get_file = cocoa_get_file;

	/* Custom Unicode handler */
	text_mbcs_hook = Term_mbcs_cocoa;

	/* We have to activate the main term here so that it is completely ready for
	 * init_angband(). If we don't, the app will crash since Term will be bad. */
	Term_activate(angband_term[0]);

	/* Add basic event handlers to allow Angband to show the splash screen. */
	init_display();

	/* Initialise game */
	init_angband();

	/* Set up stuff like commands, visuals, subwindows; activate the main term. */
	textui_init();

	/* Register sound callback, using the app delegate as the context info. It
	 * owns all of the actual sounds and is easy to reference, so we use it. */
	event_add_handler(EVENT_SOUND, AngbandPlaySoundCallback, (void *)[[NSApplication sharedApplication] delegate]);

	/* Prompt the user */
	prt("[Choose 'New' or 'Open' from the 'File' menu]",
		(Term->hgt - 23) / 5 + 23, (Term->wid - 45) / 2);
	Term_fresh();
}

void AngbandFinalize(void)
{
	textui_cleanup();
	cleanup_angband();
}



void AngbandRedrawAllTerminals(void)
{
	do_cmd_redraw();
}

void AngbandSaveGame(void)
{
	/* Hack -- Forget messages */
	msg_flag = FALSE;

	/* Save the game */
	save_game();

	NSString *path = [NSString stringWithUTF8String: savefile];
	AngbandSetCurrentSaveFilePath(path);
}

BOOL AngbandGraphicsEnabled(void)
{
	return !!use_graphics;
}

BOOL AngbandDisplayingMainInterface(void)
{
	return ((int)inkey_flag != 0);
}


/**
 * Get an event from the run loop and process it. For most events, this will
 * just dispatch them to the responder chain, but this is the place to do any
 * preprocessing or interception.
 *
 * \param untilDate The date at which the run loop should return control to
 *        Angband.
 */
static void AngbandProcessNextEventUntilDate(NSDate * __nullable untilDate)
{
	/* Check for changes to the flicker animation preference. This is the most
	 * convenient place to do this, since Angband doesn't notify on changes to
	 * these settings. Also, note that we have to keep track of whether or not
	 * the periodic events are running. This is because trying to start periodic
	 * events when they're already running will result in an exception. */
	static BOOL periodicStarted = NO;

	if (OPT(animate_flicker) && !periodicStarted) {
		[NSEvent startPeriodicEventsAfterDelay: 0.0 withPeriod: 0.2];
		periodicStarted = YES;
	}
	else if (!OPT(animate_flicker) && periodicStarted) {
		[NSEvent stopPeriodicEvents];
		periodicStarted = NO;
	}

	NSEvent *event = [[NSApplication sharedApplication] nextEventMatchingMask: NSAnyEventMask untilDate: untilDate inMode: NSDefaultRunLoopMode dequeue: YES];

	if (OPT(animate_flicker) && periodicStarted && [event type] == NSPeriodic) {
		/* Consume the event and tell Angband to do something. */
		idle_update();
	}
	else if ([event type] == NSApplicationDefined && [event subtype] == AngbandApplicationEventSubtypeQuitRequested) {
		/* The user wants to quit the app, so we check if the game is displaying
		 * the main interface. If so, we terminate safely; otherwise, we ignore
		 * the quit requeset (since this is what the other ports do). */
		BOOL displayingMainInterface = ((int)inkey_flag != 0);

		if (displayingMainInterface) {
			/* Set a flag so AngbandApplicationShouldQuitImmediately() returns
			 * true when the app delegate calls it. Also, do any important stuff
			 * here that may be too risky to do in applicationWillTerminate:. */
			AngbandApplicationShouldQuitNow = YES;
			AngbandSaveGame();
			[[NSApplication sharedApplication] terminate: nil];
		}
	}
	else {
		/* Pass the event to the responder chain. */
		[[NSApplication sharedApplication] sendEvent: event];
	}
}

BOOL AngbandApplicationShouldQuitImmediately(void)
{
	return (AngbandApplicationShouldQuitNow || player == NULL || player->upkeep == NULL || !player->upkeep->playing);
}

/**
 * Wait for an event to arrive from the user.
 *
 * \param wait If YES, the run loop will block Angband until it receives an
 *        event. If NO, the latest event in the event queue will be processed.
 *        Most of the time, this should be YES, but we accept the flag from
 *        \c Term_xtra_cocoa() during \c TERM_XTRA_EVENT. It's likely that this
 *        behavior doesn't really have much affect for the OS X port.
 */
static void AngbandWaitForEvent(BOOL wait)
{
	NSDate *endDate = (wait) ? [NSDate distantFuture] : nil;
	AngbandProcessNextEventUntilDate(endDate);
}

/**
 * Use the run loop to block for a period of time, then return control to
 * Angband to do something (most likely an animation).
 *
 * \param milliseconds The delay duration, in milliseconds.
 */
static void AngbandDelayForNextEvent(int milliseconds)
{
	/* By using a shared event handler, we can do things like shimmer monsters
	 * while a game animation is running. This is likely the desired behavior
	 * in most cases. */
	NSTimeInterval delay = (NSTimeInterval)milliseconds / 1000.0;
	NSDate *delayDate = [NSDate dateWithTimeIntervalSinceNow: delay];
	AngbandProcessNextEventUntilDate(delayDate);
}

/**
 * Handle any pending events. Because of the way we're handling events, this may
 * not really be needed.
 */
static void AngbandFlushEvents(void)
{
	NSEvent *event = nil;

	do {
		event = [[NSApplication sharedApplication] nextEventMatchingMask: NSAnyEventMask untilDate: nil inMode: NSDefaultRunLoopMode dequeue: YES];
		[[NSApplication sharedApplication] sendEvent: event];
	} while (event != nil);
}


/**
 * ------------------------------------------------------------------------
 * Support for the "ui-term.c" package
 * ------------------------------------------------------------------------ */


/**
 * Initialize a new Term
 */
static void Term_init_cocoa(term *t)
{
	/* Handle graphics */
	t->higher_pict = !! use_graphics;
	t->always_pict = FALSE;

	/* Set "mapped" flag */
	t->mapped_flag = true;

	if (t == angband_term[0]) {
		AngbandTermWindow *window = (AngbandTermWindow *)t->data;
		[window makeKeyAndOrderFront: nil];
	}
}



/**
 * Nuke an old Term
 */
static void Term_nuke_cocoa(term *t)
{
	id data = t->data;

	if ([data isKindOfClass: [AngbandTermWindow class]]) {
		AngbandTermWindow *window = (AngbandTermWindow *)t->data;
		[window close];
		t->data = NULL;
	}
}

static errr Term_xtra_cocoa_react(void)
{
	int requestedGraphicsMode = (int)[[NSUserDefaults standardUserDefaults] integerForKey: AngbandGraphicsIDDefaultsKey];
	int expectedGraphicsMode = (current_graphics_mode) ? current_graphics_mode->grafID : GRAPHICS_NONE;

	if (requestedGraphicsMode == expectedGraphicsMode) {
		/* Graphics mode is what the user wants. */
		return ERRR_NONE;
	}

	graphics_mode *newMode = NULL;

	if (requestedGraphicsMode != GRAPHICS_NONE) {
		newMode = get_graphics_mode(requestedGraphicsMode);
	}

	id context = Term->data;

	if ([context isKindOfClass: [AngbandTermWindow class]]) {
		if (newMode != NULL) {
			/* A different mode is available, so try to use that. */
			NSString *basePath = [NSString stringWithUTF8String: newMode->path];
			NSString *fileName = [NSString stringWithUTF8String: newMode->file];
			NSString *fullPath = [basePath stringByAppendingPathComponent: fileName];

			BOOL success = YES;

			for (int i = 0; i < ANGBAND_TERM_MAX; i++) {
				if (angband_term[i] == NULL) {
					continue;
				}

				if (angband_term[i]->data == NULL) {
					continue;
				}

				success = success && [(AngbandTermWindow *)angband_term[i]->data useImageTilesetAtPath: fullPath tileWidth: newMode->cell_width tileHeight: newMode->cell_height];
			}

			if (!success) {
				newMode = NULL;
			}
		}
		else {
			/* The lack of a graphics mode implies ASCII tiles. */
			[(AngbandTermWindow *)context useTextCharacterTileset];
		}
	}

	/* Record what we did */
	use_graphics = (newMode != NULL) ? newMode->grafID : 0;
	current_graphics_mode = newMode;

	/* Enable or disable higher picts. Note: this should be done for all
	 * terms. */
	for (int i = 0; i < ANGBAND_TERM_MAX; i++) {
		if (angband_term[i] == NULL) {
			continue;
		}

		angband_term[i]->higher_pict = !!use_graphics;
	}

	/* Reset visuals */
	reset_visuals(TRUE);

	return ERRR_NONE;
}

/**
 * Do a "special thing"
 */
static errr Term_xtra_cocoa(int n, int v)
{
    id angbandContext = Term->data;

    errr result = ERRR_NONE;

    /* Analyze */
    switch (n)
    {
		/* Make a noise */
        case TERM_XTRA_NOISE:
        {
            /* Make a noise */
            NSBeep();

            /* Success */
            break;
        }

		/* Process random events */
        case TERM_XTRA_BORED:
        {
			/* This is a hack to allow us to update window visibility as soon as
			 * possible after the flags change; it's a bit better than waiting
			 * to get back to the game to see changes. Once we're in the game,
			 * the flags shouldn't change, so we don't need to constantly check
			 * and update window visibility, improving performance. */
			if (!AngbandDisplayingMainInterface()) {
				AngbandWindowUpdateVisibility(YES);
			}

			break;
        }
            
		/* Process pending events */
        case TERM_XTRA_EVENT:
        {
            /* Process an event */
			if ([angbandContext isKindOfClass: [AngbandTermWindow class]]) {
				AngbandWaitForEvent(v);
			}

			/* Success */
            break;
        }
            
		/* Flush all pending events (if any) */
        case TERM_XTRA_FLUSH:
        {
            /* Hack -- flush all events */
			if ([angbandContext isKindOfClass: [AngbandTermWindow class]]) {
				AngbandFlushEvents();
			}

			/* Success */
            break;
        }
            
		/* Hack -- Change the "soft level" */
        case TERM_XTRA_LEVEL:
        {
            /* Here we could activate (if requested), but I don't think Angband
			 * should be telling us our window order (the user should decide
			 * that), so do nothing. */            
            break;
        }
            
		/* Clear the screen */
        case TERM_XTRA_CLEAR:
        {
			if ([angbandContext isKindOfClass: [AngbandTermWindow class]]) {
				[(AngbandTermWindow *)angbandContext handleClearTerm];
			}

			/* Success */
            break;
        }
            
		/* React to changes */
        case TERM_XTRA_REACT:
        {
			/* XTRA_REACT is the preferred time to update window visibility. It
			 * is sent whenever we enter the game (from start, menus, etc) along
			 * with a few other occasions. We do not want to force visibility on
			 * flags enabled, since the subwindow flags are first set when the
			 * game has started. Each of our window objects will have its flags
			 * set to zero, and thus forcing visibility will make every enabled
			 * subwindow visible regardless of user preference.
			 */
			AngbandWindowUpdateVisibility(NO);

            return (Term_xtra_cocoa_react());
        }
            
		/* Delay (milliseconds) */
        case TERM_XTRA_DELAY:
        {
			if ([angbandContext isKindOfClass: [AngbandTermWindow class]]) {
				AngbandDelayForNextEvent(v);
			}

			/* Success */
            break;
        }
            
        case TERM_XTRA_FRESH:
        {
            /* No-op -- see #1669 
             * [angbandContext displayIfNeeded]; */
            break;
        }
            
        default:
            /* Oops */
            result = 1;
            break;
    }

	/* Oops */
    return result;
}

static errr Term_curs_cocoa(int x, int y)
{
	errr result = ERRR_NONE;
	id context = Term->data;

	if ([context respondsToSelector: @selector(handleCursorUpdateWithInfo:)]) {
		static AngbandTerminalUpdateInfo cursorUpdate = {0};
		cursorUpdate.x = x;
		cursorUpdate.y = y;
		[(AngbandTermWindow *)context handleCursorUpdateWithInfo: &cursorUpdate];
	}

	/* Success */
	return result;
}

/**
 * Low level graphics (Assumes valid input)
 *
 * Erase "n" characters starting at (x,y)
 */
static errr Term_wipe_cocoa(int x, int y, int n)
{
	errr result = ERRR_NONE;
	id context = Term->data;

	if ([context respondsToSelector: @selector(handleWipeWithInfo:)]) {
		static AngbandTerminalUpdateInfo wipeUpdate = {0};
		wipeUpdate.x = x;
		wipeUpdate.y = y;
		wipeUpdate.count = n;
		[(AngbandTermWindow *)context handleWipeWithInfo: &wipeUpdate];
	}

	/* Success */
	return result;
}

static errr Term_pict_cocoa(int x, int y, int n, const int *ap,
							const wchar_t *cp, const int *tap,
							const wchar_t *tcp)
{
	/* Paranoia: Bail if we don't have a current graphics mode */
	if (! current_graphics_mode) return -1;

	errr result = ERRR_NONE;
	id context = Term->data;

	if ([context respondsToSelector: @selector(handlePictUpdateWithInfo:)]) {

		static AngbandTerminalUpdateInfo pictUpdate = {0};
		pictUpdate.x = x;
		pictUpdate.y = y;
		pictUpdate.count = n;
		pictUpdate.featureChars = cp;
		pictUpdate.featureAttrs = ap;
		pictUpdate.terrainChars = tcp;
		pictUpdate.terrainAttrs = tap;
		[(AngbandTermWindow *)context handlePictUpdateWithInfo: &pictUpdate];
	}

	/* Success */
	return result;
}

/**
 * Low level graphics.  Assumes valid input.
 *
 * Draw several ("n") chars, with an attr, at a given location.
 */
static errr Term_text_cocoa(int x, int y, int n, int a, const wchar_t *cp)
{
	errr result = ERRR_NONE;
	id context = Term->data;

	if ([context respondsToSelector: @selector(handleTextUpdateWithInfo:)]) {

		static AngbandTerminalUpdateInfo textUpdate = {0};
		textUpdate.x = x;
		textUpdate.y = y;
		textUpdate.count = n;
		textUpdate.featureChars = cp;

		/* This field can take an array, but this callback applies one attribute
		 * to all characters. Make sure to pass an address! */
		textUpdate.featureAttrs = &a;

		[(AngbandTermWindow *)context handleTextUpdateWithInfo: &textUpdate];
	}

	/* Success */
	return result;
}


/**
 * Create and initialize window number "i"
 */
term *term_data_link(int i, int rows, int columns)
{
    /* Allocate */
    term *newterm = mem_zalloc(sizeof(term));

    /* Initialize the term */
    term_init(newterm, columns, rows, 256 /* keypresses, for some reason? */);
    
    /* Differentiate between BS/^h, Tab/^i, etc. */
    newterm->complex_input = TRUE;

    /* Use a "software" cursor */
    newterm->soft_cursor = TRUE;
    
    /* Erase with "white space" */
    newterm->attr_blank = COLOUR_WHITE;
    newterm->char_blank = ' ';
    
    /* Prepare the init/nuke hooks */
    newterm->init_hook = Term_init_cocoa;
    newterm->nuke_hook = Term_nuke_cocoa;
    
    /* Prepare the function hooks */
    newterm->xtra_hook = Term_xtra_cocoa;
    newterm->wipe_hook = Term_wipe_cocoa;
    newterm->curs_hook = Term_curs_cocoa;
    newterm->text_hook = Term_text_cocoa;
    newterm->pict_hook = Term_pict_cocoa;

    /* Global pointer */
    angband_term[i] = newterm;
    
    return newterm;
}

#if !XCODE
/* Xcode looks for main() in main.m, so we have to put it there to make things
 * work right. Make doesn't care where this is, so here is fine. */
int main(int argc, const char *argv[])
{
	return NSApplicationMain(argc, argv);
}
#endif

#endif /* MACINTOSH || MACH_O_CARBON */
