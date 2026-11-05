// OpenBFME. GPL-3.0.
//
// the Files app's document picker (IOSFilesBridge.h says what and why). Built for iOS only, with ARC.
// The picker's presentation, the in-place open and the bookmark follow daisyhasacat/openbfme-godot's GodotIOSAssets.mm (GPL-3.0, @daisyhasacat).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "GodotDevice/IOSFilesBridge.h"

#include <mutex>

#if !__has_feature(objc_arc)
#error "IOSFilesBridge.mm needs ARC (-fobjc-arc, engine/CMakeLists.txt)"
#endif

@interface OpenBFMEFilesPickerDelegate : NSObject <UIDocumentPickerDelegate>
@end

namespace
{

std::mutex gLock;                         // gStatus: the coordinated read's queue writes it too
IOSFilesBridge::Status gStatus;
std::string gBookmarkFile;                // where the open pick keeps its bookmark ("" none)
NSMutableDictionary<NSString *, NSURL *> *gScoped = nil; // path -> the URL whose security scope was started (stopped by release)
OpenBFMEFilesPickerDelegate *gDelegate = nil;         // the open picker's delegate (UIKit holds it weakly)

std::string Text(NSString *s)
{
	return s != nil ? std::string(s.UTF8String) : std::string();
}

NSString *NS(const std::string &s)
{
	return [NSString stringWithUTF8String:s.c_str()];
}

void SetError(const std::string &why)
{
	std::lock_guard<std::mutex> hold(gLock);
	gStatus.state = "error";
	gStatus.error = why;
	++gStatus.serial;
}

// Where a picked item is, in the Files app's own words, for the welcome screen's lines. Paths, not provider APIs: iCloud Drive's items are in
// Mobile Documents, Files' On My iPhone in a File Provider Storage folder, an external drive under LiveFiles (userfsd) or /Volumes
std::string Place(NSURL *url, bool ubiquitous)
{
	NSString *path = url.path.stringByStandardizingPath;
	NSString *home = NSHomeDirectory().stringByStandardizingPath;
	if (ubiquitous || [path containsString:@"/Mobile Documents/"])
		return "iCloud Drive";
	if ([path hasPrefix:home] || [path hasPrefix:[@"/private" stringByAppendingString:home]])
		return "OpenBFME's folder";
	if ([path containsString:@"/File Provider Storage/"])
		return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? "On My iPad" : "On My iPhone";
	if ([path containsString:@"/LiveFiles/"] || [path hasPrefix:@"/Volumes/"])
		return "a drive";
	return "Files";
}

UIViewController *TopViewController()
{
	UIViewController *root = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
	{
		if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class])
			continue;
		for (UIWindow *window in ((UIWindowScene *)scene).windows)
			if (window.isKeyWindow)
				root = window.rootViewController;
	}
	if (root == nil) // not active yet (the app is coming to the front): any visible window's
	{
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
		{
			if (![scene isKindOfClass:UIWindowScene.class])
				continue;
			for (UIWindow *window in ((UIWindowScene *)scene).windows)
				if (window.rootViewController != nil && !window.hidden)
					root = window.rootViewController;
		}
	}
	while (root.presentedViewController != nil)
		root = root.presentedViewController;
	return root;
}

// The picked (or restored) URL in use: its scope started, its bookmark kept, then a coordinated read on a background queue, which makes the file
// provider bring an item that is not on the device yet down (iCloud Drive's "download"); state picked once it is there. On the main thread
void Accept(NSURL *url, const std::string &kind, const std::string &bookmarkFile)
{
	if (gScoped == nil)
		gScoped = [NSMutableDictionary dictionary];
	NSString *key = url.path;
	if (gScoped[key] == nil && [url startAccessingSecurityScopedResource])
		gScoped[key] = url; // NO for an item in the app's own folder: it needs no scope (and gets no stop)
	if (!bookmarkFile.empty())
	{
		NSError *error = nil;
		NSData *data = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
		if (data == nil || ![data writeToFile:NS(bookmarkFile) options:NSDataWritingAtomic error:&error])
			NSLog(@"OpenBFME picker: the bookmark for %@ was not kept: %@", url.lastPathComponent, error.localizedDescription);
	}
	[url removeAllCachedResourceValues];
	NSNumber *ubiquitous = nil;
	NSString *downloading = nil;
	[url getResourceValue:&ubiquitous forKey:NSURLIsUbiquitousItemKey error:nil];
	if (ubiquitous.boolValue)
		[url getResourceValue:&downloading forKey:NSURLUbiquitousItemDownloadingStatusKey error:nil];
	const bool download = ubiquitous.boolValue && downloading != nil && ![downloading isEqualToString:NSURLUbiquitousItemDownloadingStatusCurrent];
	if (download)
	{
		NSError *error = nil;
		if (![[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:url error:&error])
			NSLog(@"OpenBFME picker: iCloud did not start downloading %@: %@", url.lastPathComponent, error.localizedDescription);
	}
	{
		std::lock_guard<std::mutex> hold(gLock);
		gStatus.state = download ? "downloading" : "opening";
		gStatus.kind = kind;
		gStatus.path = Text(url.path);
		gStatus.name = Text(url.lastPathComponent);
		gStatus.place = Place(url, ubiquitous.boolValue);
		gStatus.ubiquitous = ubiquitous.boolValue;
		gStatus.size = -1;
		gStatus.error.clear();
	}
	const std::string path = Text(url.path);
	const bool folder = kind == "folder";
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
		NSError *error = nil;
		__block int64_t size = -1;
		__block bool there = false;
		[coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL *at) {
			NSNumber *bytes = nil;
			BOOL isFolder = NO;
			there = [[NSFileManager defaultManager] fileExistsAtPath:at.path isDirectory:&isFolder] && (bool)isFolder == folder;
			if (!folder && [at getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil] && bytes != nil)
				size = bytes.longLongValue;
		}];
		std::lock_guard<std::mutex> hold(gLock);
		if (gStatus.path != path)
			return; // released, or another item picked meanwhile
		if (error != nil || !there)
		{
			gStatus.state = "error";
			gStatus.error = error != nil ? Text(error.localizedDescription) : (folder ? "That is not a folder." : "That file is not there any more.");
		}
		else
		{
			gStatus.state = "picked";
			gStatus.size = size;
		}
		++gStatus.serial;
	});
}

} // namespace

@implementation OpenBFMEFilesPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
	gDelegate = nil;
	std::string kind;
	{
		std::lock_guard<std::mutex> hold(gLock);
		kind = gStatus.kind;
	}
	if (urls.count == 0)
	{
		std::lock_guard<std::mutex> hold(gLock);
		gStatus.state = "cancelled";
		++gStatus.serial;
		return;
	}
	Accept(urls.firstObject, kind, gBookmarkFile);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
	gDelegate = nil;
	std::lock_guard<std::mutex> hold(gLock);
	gStatus.state = "cancelled";
	++gStatus.serial;
}
@end

namespace IOSFilesBridge
{

bool pick(const std::string &kind, const std::string &extension, const std::string &bookmarkFile)
{
	{
		std::lock_guard<std::mutex> hold(gLock);
		if (gStatus.state == "waiting")
			return false;
		gStatus.state = "waiting";
		gStatus.kind = kind;
		gStatus.error.clear();
	}
	gBookmarkFile = bookmarkFile;
	void (^present)(void) = ^{
		UIViewController *top = TopViewController();
		if (top == nil)
		{
			SetError("OpenBFME has no window to show Files in. Try again.");
			return;
		}
		UTType *type = UTTypeFolder;
		if (kind != "folder")
		{
			// .obfme is declared by no app: the system gives files of that extension a dynamic type, which this matches (any data as a fallback)
			type = [UTType typeWithFilenameExtension:NS(extension) conformingToType:UTTypeData];
			if (type == nil)
				type = UTTypeData;
		}
		UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ type ] asCopy:NO];
		gDelegate = [OpenBFMEFilesPickerDelegate new];
		picker.delegate = gDelegate;
		picker.allowsMultipleSelection = NO;
		picker.shouldShowFileExtensions = YES;
		picker.modalPresentationStyle = UIModalPresentationFormSheet;
		[top presentViewController:picker animated:YES completion:nil];
	};
	if ([NSThread isMainThread])
		present();
	else
		dispatch_async(dispatch_get_main_queue(), present); // UIKit presents on the main thread only
	return true;
}

Status status()
{
	std::lock_guard<std::mutex> hold(gLock);
	return gStatus;
}

bool restore(const std::string &bookmarkFile, Status &out)
{
	NSData *data = [NSData dataWithContentsOfFile:NS(bookmarkFile)];
	if (data == nil)
	{
		out = Status();
		out.state = "error";
		out.error = "No item was chosen before.";
		return false;
	}
	BOOL stale = NO;
	NSError *error = nil;
	NSURL *url = [NSURL URLByResolvingBookmarkData:data options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
	if (url == nil)
	{
		out = Status();
		out.state = "error";
		out.error = error != nil ? Text(error.localizedDescription) : "The item chosen before cannot be found.";
		return false;
	}
	NSNumber *folder = nil;
	[url getResourceValue:&folder forKey:NSURLIsDirectoryKey error:nil];
	// a stale bookmark still resolves (the item moved or was renamed): Accept writes it again
	Accept(url, folder.boolValue ? "folder" : "file", stale ? bookmarkFile : std::string());
	out = status();
	return true;
}

void release(const std::string &path, const std::string &bookmarkFile)
{
	NSURL *url = gScoped[NS(path)];
	if (url != nil)
	{
		[url stopAccessingSecurityScopedResource];
		[gScoped removeObjectForKey:NS(path)];
	}
	if (!bookmarkFile.empty())
		[[NSFileManager defaultManager] removeItemAtPath:NS(bookmarkFile) error:nil];
	std::lock_guard<std::mutex> hold(gLock);
	if (gStatus.path == path)
	{
		const int serial = gStatus.serial;
		gStatus = Status();
		gStatus.serial = serial;
	}
}

bool excludeFromBackup(const std::string &path, std::string &error)
{
	NSURL *url = [NSURL fileURLWithPath:NS(path) isDirectory:YES];
	NSError *err = nil;
	if (![url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&err])
	{
		error = err != nil ? Text(err.localizedDescription) : "the folder could not be marked";
		return false;
	}
	return true;
}

} // namespace IOSFilesBridge
