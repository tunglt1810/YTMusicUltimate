#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FFMpegDownloader.h"
#import "Headers/YTUIResources.h"
#import "Headers/YTMActionSheetController.h"
#import "Headers/YTMActionRowView.h"
#import "Headers/YTIPlayerOverlayRenderer.h"
#import "Headers/YTIPlayerOverlayActionSupportedRenderers.h"
#import "Headers/YTMNowPlayingViewController.h"
#import "Headers/YTPlayerView.h"
#import "Headers/YTIThumbnailDetails_Thumbnail.h"
#import "Headers/YTIFormatStream.h"
#import "Headers/YTAlertView.h"
#import "Headers/ELMNodeController.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface UIView ()
- (UIViewController *)_viewControllerForAncestor;
@end

@interface ELMTouchCommandPropertiesHandler : NSObject
- (void)handleTap;
@end

@interface YTOfflineButtonPromoController : NSObject
- (void)showOfflinePromoWithRenderer:(id)arg1 endpoint:(id)arg2 parentResponder:(id)arg3;
- (void)showOfflinePromoWithEndpoint:(id)endpoint parentResponder:(id)responder;
@end

@interface YTMYPCGetOfflineUpsellEndpointCommandHandler : NSObject
- (void)executeWithCommand:(id)command entry:(id)entry fromView:(id)fromView;
- (void)executeWithCommand:(id)command entry:(id)entry;
@end

@interface YTMYPCGetOfflineUpsellEndpointCommandHandlerImpl : NSObject
- (void)executeWithCommand:(id)command entry:(id)entry fromView:(id)fromView;
- (void)executeWithCommand:(id)command entry:(id)entry;
@end

@interface YTOfflineEndpointCommandHandler : NSObject
- (void)executeWithCommand:(id)command entry:(id)entry fromView:(id)fromView;
- (void)executeWithCommand:(id)command entry:(id)entry;
@end

// Global weak references to track active playback view controllers
static __weak YTMWatchViewController *gActiveWatchViewController = nil;
static __weak YTPlayerViewController *gActivePlayerViewController = nil;

// Safe UI and window resolution helpers
static UIWindow *getKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) return window;
                }
                if (windowScene.windows.count > 0) {
                    return windowScene.windows.firstObject;
                }
            }
        }
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

static UIViewController *getTopViewController(void) {
    UIViewController *topVC = getKeyWindow().rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    if ([topVC isKindOfClass:[UINavigationController class]]) {
        topVC = [(UINavigationController *)topVC topViewController];
    } else if ([topVC isKindOfClass:[UITabBarController class]]) {
        topVC = [(UITabBarController *)topVC selectedViewController];
    }
    return topVC;
}

static UIImage *getAudioIcon(void) {
    if ([%c(YTUIResources) respondsToSelector:@selector(audioOutline)]) {
        return [%c(YTUIResources) audioOutline];
    }
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"music.note"];
    }
    return nil;
}

static UIImage *getCoverIcon(void) {
    if ([%c(YTUIResources) respondsToSelector:@selector(outlineImageWithColor:)]) {
        return [%c(YTUIResources) outlineImageWithColor:[UIColor whiteColor]];
    }
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"photo"];
    }
    return nil;
}

static YTPlayerViewController *getActivePlayerViewController(UIView *fromView) {
    if (fromView) {
        UIResponder *responder = fromView;
        while (responder) {
            if ([responder isKindOfClass:%c(YTMNowPlayingViewController)]) {
                YTMNowPlayingViewController *playingVC = (YTMNowPlayingViewController *)responder;
                UIViewController *parent = playingVC.parentViewController;
                while (parent) {
                    if ([parent isKindOfClass:%c(YTMWatchViewController)]) {
                        YTMWatchViewController *watchVC = (YTMWatchViewController *)parent;
                        if ([watchVC respondsToSelector:@selector(playerViewController)] && watchVC.playerViewController) {
                            return watchVC.playerViewController;
                        }
                    }
                    if ([parent respondsToSelector:@selector(playerViewController)]) {
                        YTPlayerViewController *pVC = (YTPlayerViewController *)[parent performSelector:@selector(playerViewController)];
                        if (pVC) return pVC;
                    }
                    parent = parent.parentViewController;
                }
            }
            if ([responder isKindOfClass:%c(YTMWatchViewController)]) {
                YTMWatchViewController *watchVC = (YTMWatchViewController *)responder;
                if ([watchVC respondsToSelector:@selector(playerViewController)] && watchVC.playerViewController) {
                    return watchVC.playerViewController;
                }
            }
            if ([responder isKindOfClass:%c(YTPlayerViewController)]) {
                return (YTPlayerViewController *)responder;
            }
            if ([responder isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)responder;
                if (vc.presentingViewController) {
                    responder = vc.presentingViewController;
                    continue;
                }
            }
            responder = responder.nextResponder;
        }
    }

    if (gActiveWatchViewController && [gActiveWatchViewController respondsToSelector:@selector(playerViewController)] && gActiveWatchViewController.playerViewController) {
        return gActiveWatchViewController.playerViewController;
    }

    if (gActivePlayerViewController) {
        return gActivePlayerViewController;
    }

    UIViewController *topVC = getTopViewController();
    if (topVC) {
        if ([topVC isKindOfClass:%c(YTMWatchViewController)]) {
            YTMWatchViewController *watchVC = (YTMWatchViewController *)topVC;
            if ([watchVC respondsToSelector:@selector(playerViewController)] && watchVC.playerViewController) {
                return watchVC.playerViewController;
            }
        }
        for (UIViewController *child in topVC.childViewControllers) {
            if ([child isKindOfClass:%c(YTMWatchViewController)]) {
                YTMWatchViewController *watchVC = (YTMWatchViewController *)child;
                if ([watchVC respondsToSelector:@selector(playerViewController)] && watchVC.playerViewController) {
                    return watchVC.playerViewController;
                }
            }
            if ([child isKindOfClass:%c(YTPlayerViewController)]) {
                return (YTPlayerViewController *)child;
            }
        }
    }

    return nil;
}

static BOOL isDownloadNodeKey(NSString *key) {
    if (!key) return NO;
    NSString *lowerKey = key.lowercaseString;
    return [key isEqualToString:@"music_download_badge_1"] ||
           [key isEqualToString:@"music_download_badge"] ||
           [key isEqualToString:@"download_badge"] ||
           [key isEqualToString:@"download_action"] ||
           [key isEqualToString:@"offline_action"] ||
           [key isEqualToString:@"menu_item_download"] ||
           [lowerKey containsString:@"download"] ||
           [lowerKey containsString:@"offline"];
}

static NSString *extractURLFromManifest(NSURL *manifest) {
    if (!manifest) return nil;
    NSData *manifestData = [NSData dataWithContentsOfURL:manifest];
    if (!manifestData) return nil;
    NSString *manifestString = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
    if (!manifestString) return nil;
    NSArray *manifestLines = [manifestString componentsSeparatedByString:@"\n"];

    NSArray *groupIDS = @[@"234", @"233", @"140", @"251", @"250", @"139"];
    for (NSString *groupID in groupIDS) {
        for (NSString *line in manifestLines) {
            NSString *searchString = [NSString stringWithFormat:@"GROUP-ID=\"%@\"", groupID];
            if ([line containsString:searchString] || [line containsString:@"TYPE=AUDIO"]) {
                NSRange startRange = [line rangeOfString:@"https://"];
                NSRange endRange = [line rangeOfString:@"index.m3u8"];

                if (startRange.location != NSNotFound && endRange.location != NSNotFound) {
                    NSRange targetRange = NSMakeRange(startRange.location, NSMaxRange(endRange) - startRange.location);
                    return [line substringWithRange:targetRange];
                }
            }
        }
    }

    NSError *regexError = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"https://[^\"]+?index\\.m3u8" options:0 error:&regexError];
    if (!regexError) {
        NSTextCheckingResult *match = [regex firstMatchInString:manifestString options:0 range:NSMakeRange(0, [manifestString length])];
        if (match && match.range.location != NSNotFound) {
            return [manifestString substringWithRange:match.range];
        }
    }

    return nil;
}

static void executeDownloadAudio(YTPlayerViewController *playerVC) {
    if (!playerVC) return;

    id rawResponse = nil;
    if ([playerVC respondsToSelector:@selector(playerResponse)]) {
        rawResponse = playerVC.playerResponse;
    }
    if (!rawResponse) return;

    id playerData = rawResponse;
    if ([rawResponse respondsToSelector:@selector(playerData)]) {
        id pd = [rawResponse performSelector:@selector(playerData)];
        if (pd) playerData = pd;
    }

    id videoDetails = nil;
    if ([playerData respondsToSelector:@selector(videoDetails)]) {
        videoDetails = [playerData performSelector:@selector(videoDetails)];
    }

    NSString *rawTitle = @"Unknown Title";
    if (videoDetails && [videoDetails respondsToSelector:@selector(title)]) {
        rawTitle = [videoDetails performSelector:@selector(title)] ?: @"Unknown Title";
    }

    NSString *rawAuthor = @"Unknown Artist";
    if (videoDetails && [videoDetails respondsToSelector:@selector(author)]) {
        rawAuthor = [videoDetails performSelector:@selector(author)] ?: @"Unknown Artist";
    }

    NSString *title = [rawTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *author = [rawAuthor stringByReplacingOccurrencesOfString:@"/" withString:@"-"];

    id streamingData = nil;
    if ([playerData respondsToSelector:@selector(streamingData)]) {
        streamingData = [playerData performSelector:@selector(streamingData)];
    }

    NSString *hlsManifestURL = nil;
    if (streamingData && [streamingData respondsToSelector:@selector(hlsManifestURL)]) {
        hlsManifestURL = [streamingData performSelector:@selector(hlsManifestURL)];
    }

    NSMutableArray *adaptiveFormats = nil;
    if (streamingData && [streamingData respondsToSelector:@selector(adaptiveFormatsArray)]) {
        adaptiveFormats = [streamingData performSelector:@selector(adaptiveFormatsArray)];
    }

    NSMutableArray *formats = nil;
    if (streamingData && [streamingData respondsToSelector:@selector(formatsArray)]) {
        formats = [streamingData performSelector:@selector(formatsArray)];
    }

    UIWindow *window = getKeyWindow();
    MBProgressHUD *prepHUD = window ? [MBProgressHUD showHUDAddedTo:window animated:YES] : nil;
    if (prepHUD) {
        prepHUD.mode = MBProgressHUDModeIndeterminate;
        prepHUD.label.text = LOC(@"DOWNLOADING");
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *extractedURL = nil;

        // 1. Try extracting from HLS manifest
        if (hlsManifestURL && hlsManifestURL.length > 0) {
            extractedURL = extractURLFromManifest([NSURL URLWithString:hlsManifestURL]);
        }

        // 2. Fallback: Search adaptiveFormatsArray for audio stream URL
        if (!extractedURL || extractedURL.length == 0) {
            if (adaptiveFormats && [adaptiveFormats isKindOfClass:[NSArray class]]) {
                for (id stream in adaptiveFormats) {
                    if ([stream respondsToSelector:@selector(URL)] && [stream respondsToSelector:@selector(mimeType)]) {
                        NSString *mime = [stream performSelector:@selector(mimeType)];
                        NSString *streamURL = [stream performSelector:@selector(URL)];
                        if ([mime containsString:@"audio/"] && streamURL.length > 0) {
                            extractedURL = streamURL;
                            break;
                        }
                    }
                }
            }
        }

        // 3. Fallback: Search formatsArray
        if (!extractedURL || extractedURL.length == 0) {
            if (formats && [formats isKindOfClass:[NSArray class]]) {
                for (id stream in formats) {
                    if ([stream respondsToSelector:@selector(URL)]) {
                        NSString *streamURL = [stream performSelector:@selector(URL)];
                        if (streamURL.length > 0) {
                            extractedURL = streamURL;
                            break;
                        }
                    }
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (prepHUD) {
                [prepHUD hideAnimated:YES];
            }

            if (extractedURL.length > 0) {
                FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
                NSString *videoID = nil;
                if ([playerVC respondsToSelector:@selector(contentVideoID)]) {
                    videoID = playerVC.contentVideoID;
                }
                ffmpeg.tempName = videoID ?: [NSString stringWithFormat:@"%lu", (unsigned long)[[NSDate date] timeIntervalSince1970]];
                ffmpeg.mediaName = [NSString stringWithFormat:@"%@ - %@", author, title];
                double duration = 0;
                if ([playerVC respondsToSelector:@selector(currentVideoTotalMediaTime)]) {
                    duration = playerVC.currentVideoTotalMediaTime;
                }
                ffmpeg.duration = round(duration);
                [ffmpeg downloadAudio:extractedURL];

                // Download cover artwork to YTMusicUltimate directory
                if (videoDetails && [videoDetails respondsToSelector:@selector(thumbnail)]) {
                    id thumbnailDetails = [videoDetails performSelector:@selector(thumbnail)];
                    if (thumbnailDetails && [thumbnailDetails respondsToSelector:@selector(thumbnailsArray)]) {
                        NSMutableArray *thumbnailsArray = [thumbnailDetails performSelector:@selector(thumbnailsArray)];
                        id lastThumbnail = [thumbnailsArray lastObject];
                        if (lastThumbnail && [lastThumbnail respondsToSelector:@selector(URL)]) {
                            NSString *thumbURLStr = [lastThumbnail performSelector:@selector(URL)];
                            if (thumbURLStr) {
                                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                                    NSData *imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:thumbURLStr]];
                                    if (imageData) {
                                        NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
                                        NSURL *folderURL = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];
                                        [[NSFileManager defaultManager] createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
                                        NSURL *coverURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@ - %@.png", author, title]];
                                        [imageData writeToURL:coverURL atomically:YES];
                                    }
                                });
                            }
                        }
                    }
                }
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"OOPS") message:LOC(@"LINK_NOT_FOUND") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [getTopViewController() presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

static void executeDownloadCoverImage(YTPlayerViewController *playerVC) {
    if (!playerVC) return;

    id rawResponse = nil;
    if ([playerVC respondsToSelector:@selector(playerResponse)]) {
        rawResponse = playerVC.playerResponse;
    }
    if (!rawResponse) return;

    id playerData = rawResponse;
    if ([rawResponse respondsToSelector:@selector(playerData)]) {
        id pd = [rawResponse performSelector:@selector(playerData)];
        if (pd) playerData = pd;
    }

    id videoDetails = nil;
    if ([playerData respondsToSelector:@selector(videoDetails)]) {
        videoDetails = [playerData performSelector:@selector(videoDetails)];
    }

    NSString *thumbnailURL = nil;
    if (videoDetails && [videoDetails respondsToSelector:@selector(thumbnail)]) {
        id thumbnailDetails = [videoDetails performSelector:@selector(thumbnail)];
        if (thumbnailDetails && [thumbnailDetails respondsToSelector:@selector(thumbnailsArray)]) {
            NSMutableArray *thumbnailsArray = [thumbnailDetails performSelector:@selector(thumbnailsArray)];
            id lastThumbnail = [thumbnailsArray lastObject];
            if (lastThumbnail && [lastThumbnail respondsToSelector:@selector(URL)]) {
                thumbnailURL = [lastThumbnail performSelector:@selector(URL)];
                if (thumbnailURL && [lastThumbnail respondsToSelector:@selector(width)]) {
                    unsigned int width = (unsigned int)[[lastThumbnail valueForKey:@"width"] unsignedIntegerValue];
                    if (width > 0) {
                        thumbnailURL = [thumbnailURL stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"w%u-h%u-", width, width] withString:@"w2048-h2048-"];
                    }
                }
            }
        }
    }

    if (!thumbnailURL || thumbnailURL.length == 0) return;

    UIWindow *window = getKeyWindow();
    MBProgressHUD *hud = window ? [MBProgressHUD showHUDAddedTo:window animated:YES] : nil;
    if (hud) {
        dispatch_async(dispatch_get_main_queue(), ^{
            hud.mode = MBProgressHUDModeIndeterminate;
        });
    }

    FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
    [ffmpeg downloadImage:[NSURL URLWithString:thumbnailURL]];

    if (hud) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [hud hideAnimated:YES];
        });
    }
}

static void presentDownloadSheet(UIViewController *presentingVC, UIView *sourceView, YTPlayerViewController *playerVC) {
    if (!playerVC) return;

    BOOL audioEnabled = YTMU(@"downloadAudio");
    BOOL coverEnabled = YTMU(@"downloadCoverImage");

    if (audioEnabled && !coverEnabled) {
        executeDownloadAudio(playerVC);
        return;
    }

    if (!audioEnabled && coverEnabled) {
        executeDownloadCoverImage(playerVC);
        return;
    }

    // Default or both enabled -> Show Action Sheet
    UIViewController *targetVC = presentingVC ?: getTopViewController();
    UIView *targetSourceView = sourceView ?: targetVC.view;

    if (%c(YTMActionSheetController) && %c(YTActionSheetAction)) {
        @try {
            YTMActionSheetController *sheetController = [%c(YTMActionSheetController) musicActionSheetController];
            sheetController.sourceView = targetSourceView;
            if ([sheetController respondsToSelector:@selector(addHeaderWithTitle:subtitle:)]) {
                [sheetController addHeaderWithTitle:LOC(@"SELECT_ACTION") subtitle:nil];
            }

            [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_AUDIO") iconImage:getAudioIcon() style:0 handler:^{
                executeDownloadAudio(playerVC);
            }]];

            [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_COVER") iconImage:getCoverIcon() style:0 handler:^{
                executeDownloadCoverImage(playerVC);
            }]];

            if ([sheetController respondsToSelector:@selector(presentFromViewController:animated:completion:)]) {
                [sheetController presentFromViewController:targetVC animated:YES completion:nil];
                return;
            }
        } @catch (NSException *exception) {
            NSLog(@"[YTMusicUltimate] YTMActionSheetController presentation failed: %@", exception);
        }
    }

    // Fallback: Standard UIAlertController
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"SELECT_ACTION") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"DOWNLOAD_AUDIO") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        executeDownloadAudio(playerVC);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"DOWNLOAD_COVER") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        executeDownloadCoverImage(playerVC);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = targetSourceView;
        alert.popoverPresentationController.sourceRect = targetSourceView.bounds;
    }

    [targetVC presentViewController:alert animated:YES completion:nil];
}

%hook YTMWatchViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    gActiveWatchViewController = self;
    if ([self respondsToSelector:@selector(playerViewController)] && self.playerViewController) {
        gActivePlayerViewController = self.playerViewController;
    }
}

- (void)loadWithPlayerResponse:(id)response {
    %orig;
    gActiveWatchViewController = self;
    if ([self respondsToSelector:@selector(playerViewController)] && self.playerViewController) {
        gActivePlayerViewController = self.playerViewController;
    }
}
%end

%hook YTPlayerViewController
- (void)setPlayerResponse:(YTPlayerResponse *)response {
    %orig;
    gActivePlayerViewController = self;
}
%end

%hook ELMTouchCommandPropertiesHandler
- (void)handleTap {
    ELMNodeController *node = nil;
    @try {
        node = [self valueForKey:@"_controller"];
    } @catch (NSException *e) {
        @try {
            node = [self valueForKey:@"controller"];
        } @catch (NSException *e2) {}
    }

    UIGestureRecognizer *tapRecognizer = nil;
    @try {
        tapRecognizer = [self valueForKey:@"_tapRecognizer"];
    } @catch (NSException *e) {
        @try {
            tapRecognizer = [self valueForKey:@"tapRecognizer"];
        } @catch (NSException *e2) {}
    }

    NSString *key = node ? node.key : nil;
    BOOL isDownload = isDownloadNodeKey(key);

    if (!isDownload) {
        id command = nil;
        @try {
            command = [self valueForKey:@"_command"] ?: [self valueForKey:@"command"];
        } @catch (NSException *e) {}
        if (command) {
            NSString *desc = [command description].lowercaseString;
            if ([desc containsString:@"offline"] || [desc containsString:@"download"]) {
                isDownload = YES;
            }
        }
    }

    if (!isDownload) {
        return %orig;
    }

    UIView *sourceView = tapRecognizer ? tapRecognizer.view : nil;
    YTPlayerViewController *playerVC = getActivePlayerViewController(sourceView);

    if (playerVC) {
        UIViewController *presentingVC = [sourceView _viewControllerForAncestor] ?: getTopViewController();
        presentDownloadSheet(presentingVC, sourceView, playerVC);
    } else {
        %orig;
    }
}
%end

%hook YTOfflineButtonPromoController
- (void)showOfflinePromoWithRenderer:(id)arg1 endpoint:(id)arg2 parentResponder:(id)arg3 {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(nil);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), nil, playerVC);
            return;
        }
    }
    %orig;
}

- (void)showOfflinePromoWithEndpoint:(id)endpoint parentResponder:(id)responder {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(nil);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), nil, playerVC);
            return;
        }
    }
    %orig;
}
%end

%hook YTMYPCGetOfflineUpsellEndpointCommandHandler
- (void)executeWithCommand:(id)command entry:(id)entry fromView:(id)fromView {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(fromView);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), fromView, playerVC);
            return;
        }
    }
    %orig;
}

- (void)executeWithCommand:(id)command entry:(id)entry {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(nil);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), nil, playerVC);
            return;
        }
    }
    %orig;
}
%end

%hook YTMYPCGetOfflineUpsellEndpointCommandHandlerImpl
- (void)executeWithCommand:(id)command entry:(id)entry fromView:(id)fromView {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(fromView);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), fromView, playerVC);
            return;
        }
    }
    %orig;
}

- (void)executeWithCommand:(id)command entry:(id)entry {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(nil);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), nil, playerVC);
            return;
        }
    }
    %orig;
}
%end

%hook YTOfflineEndpointCommandHandler
- (void)executeWithCommand:(id)command entry:(id)entry fromView:(id)fromView {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(fromView);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), fromView, playerVC);
            return;
        }
    }
    %orig;
}

- (void)executeWithCommand:(id)command entry:(id)entry {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(nil);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), nil, playerVC);
            return;
        }
    }
    %orig;
}
%end

%hook YTMActionRowView
- (void)didTapDownloadButton:(id)sender {
    if (YTMU(@"YTMUltimateIsEnabled")) {
        YTPlayerViewController *playerVC = getActivePlayerViewController(self);
        if (playerVC) {
            presentDownloadSheet(getTopViewController(), self, playerVC);
            return;
        }
    }
    %orig;
}
%end


