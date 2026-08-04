#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FFMpegDownloader.h"
#import "Headers/YTUIResources.h"
#import "Headers/YTMActionSheetController.h"
#import "Headers/YTMActionRowView.h"
#import "Headers/YTIPlayerOverlayRenderer.h"
#import "Headers/YTIPlayerOverlayActionSupportedRenderers.h"
#import "Headers/YTMNowPlayingViewController.h"
#import "Headers/YTMWatchViewController.h"
#import "Headers/YTPlayerView.h"
#import "Headers/YTIThumbnailDetails_Thumbnail.h"
#import "Headers/YTIFormatStream.h"
#import "Headers/YTAlertView.h"
#import "Headers/ELMNodeController.h"
#import "Headers/YTAssetLoader.h"
#import "Headers/Localization.h"
#import "Utils/MBProgressHUD/MBProgressHUD.h"

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface UIView ()
- (UIViewController *)_viewControllerForAncestor;
@end

@interface ELMTouchCommandPropertiesHandler : NSObject
- (void)downloadAudio:(YTPlayerViewController *)playerVC;
- (void)downloadCoverImage:(YTPlayerViewController *)playerVC;
- (NSString *)getURLFromManifest:(NSURL *)manifest;
@end

// Track active view controllers globally to reliably retrieve the current player
static __weak YTPlayerViewController *gActivePlayerViewController = nil;
static __weak YTMWatchViewController *gActiveWatchViewController = nil;
static __weak YTMNowPlayingViewController *gActiveNowPlayingViewController = nil;

%hook YTPlayerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gActivePlayerViewController = self;
}
- (void)loadWithPlayerResponse:(id)response {
    %orig;
    gActivePlayerViewController = self;
}
%end

%hook YTMWatchViewController
- (id)init {
    self = %orig;
    if (self) {
        gActiveWatchViewController = self;
    }
    return self;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gActiveWatchViewController = self;
}
%end

%hook YTMNowPlayingViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gActiveNowPlayingViewController = self;
}
%end

static YTPlayerViewController *getPlayerViewControllerFromParent(UIViewController *parent) {
    while (parent) {
        if ([parent isKindOfClass:%c(YTMWatchViewController)]) {
            YTMWatchViewController *watchVC = (YTMWatchViewController *)parent;
            if ([watchVC respondsToSelector:@selector(playerViewController)] && watchVC.playerViewController) {
                return watchVC.playerViewController;
            }
        }
        if ([parent respondsToSelector:@selector(playerViewController)]) {
            id pVC = [parent performSelector:@selector(playerViewController)];
            if (pVC && [pVC isKindOfClass:%c(YTPlayerViewController)]) {
                return (YTPlayerViewController *)pVC;
            }
        }
        parent = parent.parentViewController;
    }
    return nil;
}

static YTPlayerViewController *getActivePlayerViewController(UIView *fromView) {
    // 1. Search up the responder chain of fromView
    if (fromView) {
        UIResponder *responder = fromView;
        while (responder) {
            if ([responder isKindOfClass:%c(YTPlayerViewController)]) {
                return (YTPlayerViewController *)responder;
            }
            if ([responder isKindOfClass:%c(YTMWatchViewController)]) {
                YTMWatchViewController *watchVC = (YTMWatchViewController *)responder;
                if ([watchVC respondsToSelector:@selector(playerViewController)] && watchVC.playerViewController) {
                    return watchVC.playerViewController;
                }
            }
            if ([responder isKindOfClass:%c(YTMNowPlayingViewController)]) {
                YTMNowPlayingViewController *playingVC = (YTMNowPlayingViewController *)responder;
                YTPlayerViewController *pVC = getPlayerViewControllerFromParent(playingVC.parentViewController);
                if (pVC) return pVC;
            }
            if ([responder isKindOfClass:[UIViewController class]]) {
                UIViewController *vc = (UIViewController *)responder;
                // Check presentingViewController in case fromView is inside a presented sheet/modal (e.g. "..." menu)
                UIViewController *pres = vc.presentingViewController;
                while (pres) {
                    if ([pres isKindOfClass:%c(YTMNowPlayingViewController)]) {
                        YTPlayerViewController *pVC = getPlayerViewControllerFromParent(((YTMNowPlayingViewController *)pres).parentViewController);
                        if (pVC) return pVC;
                    }
                    if ([pres isKindOfClass:%c(YTMWatchViewController)]) {
                        YTMWatchViewController *wVC = (YTMWatchViewController *)pres;
                        if ([wVC respondsToSelector:@selector(playerViewController)] && wVC.playerViewController) {
                            return wVC.playerViewController;
                        }
                    }
                    pres = pres.presentingViewController;
                }
                YTPlayerViewController *pVC = getPlayerViewControllerFromParent(vc);
                if (pVC) return pVC;
            }
            responder = [responder nextResponder];
        }
    }

    // 2. Try global active watch controller
    if (gActiveWatchViewController && [gActiveWatchViewController respondsToSelector:@selector(playerViewController)] && gActiveWatchViewController.playerViewController) {
        return gActiveWatchViewController.playerViewController;
    }

    // 3. Try global active now playing controller
    if (gActiveNowPlayingViewController) {
        YTPlayerViewController *pVC = getPlayerViewControllerFromParent(gActiveNowPlayingViewController.parentViewController);
        if (pVC) return pVC;
    }

    // 4. Try global active player controller
    if (gActivePlayerViewController) {
        return gActivePlayerViewController;
    }

    return nil;
}

static UIViewController *getTopViewController(void) {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    return top;
}

static BOOL isDownloadNodeKey(NSString *key) {
    if (!key) return NO;
    NSString *lower = key.lowercaseString;
    return [lower isEqualToString:@"music_download_badge_1"] ||
           [lower isEqualToString:@"music_download_badge"] ||
           [lower isEqualToString:@"download_badge"] ||
           [lower containsString:@"download"] ||
           [lower containsString:@"offline"];
}

static UIImage *getAudioIcon(void) {
    if ([%c(YTUIResources) respondsToSelector:@selector(audioOutline)]) {
        @try {
            UIImage *img = [%c(YTUIResources) audioOutline];
            if (img) return img;
        } @catch (NSException *e) {}
    }
    if (%c(YTAssetLoader)) {
        @try {
            YTAssetLoader *al = [[%c(YTAssetLoader) alloc] initWithBundle:[NSBundle mainBundle]];
            if ([al respondsToSelector:@selector(imageNamed:)]) {
                UIImage *img = [al imageNamed:@"yt_outline_audio_24pt"];
                if (img) return img;
            }
        } @catch (NSException *e) {}
    }
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"music.note"];
    }
    return nil;
}

static UIImage *getCoverIcon(void) {
    if (%c(YTAssetLoader)) {
        @try {
            YTAssetLoader *al = [[%c(YTAssetLoader) alloc] initWithBundle:[NSBundle mainBundle]];
            if ([al respondsToSelector:@selector(imageNamed:)]) {
                UIImage *img = [al imageNamed:@"youtube_outline/image_24pt"];
                if (img) return img;
            }
        } @catch (NSException *e) {}
    }
    if ([%c(YTUIResources) respondsToSelector:@selector(outlineImageWithColor:)]) {
        @try {
            UIImage *img = [%c(YTUIResources) outlineImageWithColor:[UIColor whiteColor]];
            if (img) return img;
        } @catch (NSException *e) {}
    }
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"photo"];
    }
    return nil;
}

static void presentDownloadSheet(UIViewController *presentingVC, UIView *sourceView, void (^onAudio)(void), void (^onCover)(void)) {
    if (!presentingVC) {
        presentingVC = getTopViewController();
    }
    if (!presentingVC) return;

    // 1. Try native YTMActionSheetController
    Class actionSheetClass = %c(YTMActionSheetController);
    Class actionClass = %c(YTActionSheetAction);
    if (actionSheetClass && actionClass &&
        [actionSheetClass respondsToSelector:@selector(musicActionSheetController)] &&
        [actionClass respondsToSelector:@selector(actionWithTitle:iconImage:style:handler:)]) {
        @try {
            YTMActionSheetController *sheetController = [actionSheetClass musicActionSheetController];
            if (sheetController) {
                if ([sheetController respondsToSelector:@selector(setSourceView:)]) {
                    sheetController.sourceView = sourceView;
                }
                if ([sheetController respondsToSelector:@selector(addHeaderWithTitle:subtitle:)]) {
                    [sheetController addHeaderWithTitle:LOC(@"SELECT_ACTION") subtitle:nil];
                }
                [sheetController addAction:[actionClass actionWithTitle:LOC(@"DOWNLOAD_AUDIO") iconImage:getAudioIcon() style:0 handler:^{
                    if (onAudio) onAudio();
                }]];
                [sheetController addAction:[actionClass actionWithTitle:LOC(@"DOWNLOAD_COVER") iconImage:getCoverIcon() style:0 handler:^{
                    if (onCover) onCover();
                }]];
                if ([sheetController respondsToSelector:@selector(presentFromViewController:animated:completion:)]) {
                    [sheetController presentFromViewController:presentingVC animated:YES completion:nil];
                    return;
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[YTMusicUltimate] YTMActionSheetController exception: %@", e);
        }
    }

    // 2. Fallback to standard UIAlertController
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:LOC(@"SELECT_ACTION") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alertController addAction:[UIAlertAction actionWithTitle:LOC(@"DOWNLOAD_AUDIO") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (onAudio) onAudio();
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:LOC(@"DOWNLOAD_COVER") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        if (onCover) onCover();
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:LOC(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];

    if (alertController.popoverPresentationController) {
        alertController.popoverPresentationController.sourceView = sourceView ?: presentingVC.view;
        alertController.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : presentingVC.view.bounds;
    }

    UIViewController *targetVC = presentingVC;
    while (targetVC.presentedViewController && !targetVC.presentedViewController.isBeingDismissed) {
        targetVC = targetVC.presentedViewController;
    }
    [targetVC presentViewController:alertController animated:YES completion:nil];
}

%hook ELMTouchCommandPropertiesHandler
- (void)handleTap {

    if (class_getInstanceVariable([self class], "_controller") == NULL) {
        return %orig;
    }

    if (class_getInstanceVariable([self class], "_tapRecognizer") == NULL) {
        return %orig;
    }

    ELMNodeController *node = [self valueForKey:@"_controller"];
    UIGestureRecognizer *tapRecognizer = [self valueForKey:@"_tapRecognizer"];

    NSString *key = node ? node.key : nil;
    if (!isDownloadNodeKey(key)) {
        return %orig;
    }

    UIView *tapView = tapRecognizer.view;
    YTPlayerViewController *playerVC = getActivePlayerViewController(tapView);
    YTPlayerResponse *playerResponse = playerVC ? playerVC.playerResponse : nil;

    if (playerResponse) {
        BOOL audioEnabled = YTMU(@"downloadAudio");
        BOOL coverEnabled = YTMU(@"downloadCoverImage");

        if ((audioEnabled && coverEnabled) || (!audioEnabled && !coverEnabled)) {
            UIViewController *presentingVC = (UIViewController *)tapView._viewControllerForAncestor ?: getTopViewController();
            presentDownloadSheet(presentingVC, tapView, ^{
                [self downloadAudio:playerVC];
            }, ^{
                [self downloadCoverImage:playerVC];
            });
        } else if (audioEnabled) {
            [self downloadAudio:playerVC];
        } else if (coverEnabled) {
            [self downloadCoverImage:playerVC];
        }
    } else {
        if ([%c(YTAlertView) respondsToSelector:@selector(infoDialog)]) {
            @try {
                YTAlertView *alertView = [%c(YTAlertView) infoDialog];
                alertView.title = LOC(@"DONT_RUSH");
                alertView.subtitle = LOC(@"DONT_RUSH_DESC");
                [alertView show];
                return;
            } @catch (NSException *e) {}
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"DONT_RUSH") message:LOC(@"DONT_RUSH_DESC") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [getTopViewController() presentViewController:alert animated:YES completion:nil];
    }
}

%new
- (void)downloadAudio:(YTPlayerViewController *)playerVC {
    if (!playerVC || !playerVC.playerResponse) return;
    YTPlayerResponse *playerResponse = playerVC.playerResponse;

    NSString *rawTitle = playerResponse.playerData.videoDetails.title ?: @"Unknown Title";
    NSString *rawAuthor = playerResponse.playerData.videoDetails.author ?: @"Unknown Artist";
    NSString *title = [rawTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *author = [rawAuthor stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *urlStr = playerResponse.playerData.streamingData.hlsManifestURL;

    if (!urlStr || urlStr.length == 0) {
        if ([%c(YTAlertView) respondsToSelector:@selector(infoDialog)]) {
            @try {
                YTAlertView *alertView = [%c(YTAlertView) infoDialog];
                alertView.title = LOC(@"OOPS");
                alertView.subtitle = LOC(@"LINK_NOT_FOUND");
                [alertView show];
                return;
            } @catch (NSException *e) {}
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"OOPS") message:LOC(@"LINK_NOT_FOUND") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [getTopViewController() presentViewController:alert animated:YES completion:nil];
        return;
    }

    MBProgressHUD *prepHUD = [MBProgressHUD showHUDAddedTo:[UIApplication sharedApplication].keyWindow animated:YES];
    prepHUD.mode = MBProgressHUDModeIndeterminate;
    prepHUD.label.text = LOC(@"DOWNLOADING");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *extractedURL = [self getURLFromManifest:[NSURL URLWithString:urlStr]];

        dispatch_async(dispatch_get_main_queue(), ^{
            [prepHUD hideAnimated:YES];

            if (extractedURL.length > 0) {
                FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
                ffmpeg.tempName = playerVC.contentVideoID ?: [NSString stringWithFormat:@"%lu", (unsigned long)[[NSDate date] timeIntervalSince1970]];
                ffmpeg.mediaName = [NSString stringWithFormat:@"%@ - %@", author, title];
                ffmpeg.duration = round(playerVC.currentVideoTotalMediaTime);
                [ffmpeg downloadAudio:extractedURL];

                // Download cover artwork to YTMusicUltimate directory
                NSMutableArray *thumbnailsArray = playerResponse.playerData.videoDetails.thumbnail.thumbnailsArray;
                YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];
                if (thumbnail.URL) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                        NSData *imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:thumbnail.URL]];
                        if (imageData) {
                            NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
                            NSURL *folderURL = [documentsURL URLByAppendingPathComponent:@"YTMusicUltimate"];
                            [[NSFileManager defaultManager] createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
                            NSURL *coverURL = [documentsURL URLByAppendingPathComponent:[NSString stringWithFormat:@"YTMusicUltimate/%@ - %@.png", author, title]];
                            [imageData writeToURL:coverURL atomically:YES];
                        }
                    });
                }
            } else {
                if ([%c(YTAlertView) respondsToSelector:@selector(infoDialog)]) {
                    @try {
                        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
                        alertView.title = LOC(@"OOPS");
                        alertView.subtitle = LOC(@"LINK_NOT_FOUND");
                        [alertView show];
                        return;
                    } @catch (NSException *e) {}
                }
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"OOPS") message:LOC(@"LINK_NOT_FOUND") preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [getTopViewController() presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}

%new
- (NSString *)getURLFromManifest:(NSURL *)manifest {
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

%new
- (void)downloadCoverImage:(YTPlayerViewController *)playerVC {
    if (!playerVC || !playerVC.playerResponse) return;
    YTPlayerResponse *playerResponse = playerVC.playerResponse;

    NSMutableArray *thumbnailsArray = playerResponse.playerData.videoDetails.thumbnail.thumbnailsArray;
    YTIThumbnailDetails_Thumbnail *thumbnail = [thumbnailsArray lastObject];
    if (!thumbnail || !thumbnail.URL) return;

    NSString *thumbnailURL = thumbnail.URL;
    if (thumbnail.width > 0) {
        thumbnailURL = [thumbnail.URL stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"w%u-h%u-", thumbnail.width, thumbnail.width] withString:@"w2048-h2048-"];
    }

    FFMpegDownloader *ffmpeg = [[FFMpegDownloader alloc] init];
    [ffmpeg downloadImage:[NSURL URLWithString:thumbnailURL]];
}
%end
