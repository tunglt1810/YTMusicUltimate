# Kế hoạch thực thi Sửa lỗi nút Download Music không hoạt động

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Khắc phục lỗi nút download music trên giao diện YTMusic không phản ứng khi bấm vào.

**Architecture:** Mở rộng nhận diện `node.key` của Element UI trong Logos/Theos hook (`Downloading.x`), bổ sung helper tìm kiếm `YTMNowPlayingViewController` trong responder hierarchy, và cập nhật fallback điều kiện hiển thị ActionSheet khi chưa chọn cài đặt mặc định.

**Tech Stack:** Objective-C, Logos / Theos tweak (%hook, %c), iOS SDK.

## Global Constraints
- Tất cả các lệnh shell phải bắt đầu bằng dấu cách (space character).
- Giữ nguyên cấu trúc codebase hiện tại, chỉ thay đổi trong [Source/Downloading.x](file:///Users/bez/Workspace/repos/bez/YTMusicUltimate/Source/Downloading.x).

---

### Task 1: Cập nhật logic hook và helper trong Downloading.x

**Files:**
- Modify: `Source/Downloading.x:31-89`

**Interfaces:**
- Consumes: `ELMTouchCommandPropertiesHandler`, `YTMNowPlayingViewController`, `YTMActionSheetController`
- Produces: Flexibly hooked `handleTap` with proper node key pattern matching, hierarchy searching, and ActionSheet fallback.

- [ ] **Step 1: Thêm hàm helper kiểm tra key node download và helper tìm YTMNowPlayingViewController**

Cập nhật đầu file `Source/Downloading.x`:
```objc
static BOOL isDownloadNodeKey(NSString *key) {
    if (!key) return NO;
    return [key isEqualToString:@"music_download_badge_1"] ||
           [key isEqualToString:@"music_download_badge"] ||
           [key isEqualToString:@"download_badge"] ||
           [key containsString:@"download"];
}

static YTMNowPlayingViewController *findNowPlayingViewController(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:%c(YTMNowPlayingViewController)]) {
            return (YTMNowPlayingViewController *)responder;
        }
        responder = [responder nextResponder];
    }
    return nil;
}
```

- [ ] **Step 2: Cập nhật hàm handleTap trong %hook ELMTouchCommandPropertiesHandler**

Thay thế logic trong `Source/Downloading.x`:
```objc
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

    if (!isDownloadNodeKey(node.key)) {
        return %orig;
    }

    YTMNowPlayingViewController *playingVC = findNowPlayingViewController(tapRecognizer.view);
    if (!playingVC) {
        return %orig;
    }

    YTMWatchViewController *watchVC = (YTMWatchViewController *)playingVC.parentViewController;
    YTPlayerViewController *playerVC = watchVC.playerViewController;
    YTPlayerResponse *playerResponse = playerVC.playerResponse;

    if (playerResponse) {
        YTMActionSheetController *sheetController = [%c(YTMActionSheetController) musicActionSheetController];
        sheetController.sourceView = tapRecognizer.view;
        [sheetController addHeaderWithTitle:LOC(@"SELECT_ACTION") subtitle:nil];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_AUDIO") iconImage:[%c(YTUIResources) audioOutline] style:0 handler:^ {
            [self downloadAudio:playerVC];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_COVER") iconImage:[%c(YTUIResources) outlineImageWithColor:[UIColor whiteColor]] style:0 handler:^ {
            [self downloadCoverImage:playerVC];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"DOWNLOAD_PREMIUM") iconImage:[%c(YTUIResources) downloadOutline] secondaryIconImage:[%c(YTUIResources) youtubePremiumBadgeLight] accessibilityIdentifier:nil handler:^ {
            return %orig;
        }]];

        BOOL audioEnabled = YTMU(@"downloadAudio");
        BOOL coverEnabled = YTMU(@"downloadCoverImage");

        if ((audioEnabled && coverEnabled) || (!audioEnabled && !coverEnabled)) {
            [sheetController presentFromViewController:playingVC animated:YES completion:nil];
        } else if (audioEnabled) {
            [self downloadAudio:playerVC];
        } else if (coverEnabled) {
            [self downloadCoverImage:playerVC];
        }
    } else {
        YTAlertView *alertView = [%c(YTAlertView) infoDialog];
        alertView.title = LOC(@"DONT_RUSH");
        alertView.subtitle = LOC(@"DONT_RUSH_DESC");
        [alertView show];
    }
}
```

- [ ] **Step 3: Biên dịch dự án bằng make để xác nhận không có lỗi cú pháp / build error**

Run: ` make` (với khoảng trắng ở đầu dòng theo quy tắc shell)
Expected: Biên dịch thành công tạo file dylib/deb package mà không có lỗi compilation.

- [ ] **Step 4: Commit thay đổi**

Run: ` git add Source/Downloading.x docs/plans/2026-08-04-fix-download-button-plan.md`
Run: ` git commit -m "fix: improve download button node matching and settings fallback"`
