# Kế hoạch Triển khai: Sửa lỗi nút Download trong Menu "..." và Crash trên Playback Controller

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Khắc phục lỗi nút Download trong Menu "..." không hoạt động và lỗi crash ứng dụng khi bấm nút Download trên thanh điều khiển Playback Controller.

**Architecture:** Xây dựng hệ thống Safe UI Helper (an toàn cho `MBProgressHUD` trên iOS mới), cơ chế Weak Tracking `getActivePlayerViewController`, mở rộng nhận diện Element Key trong `ELMTouchCommandPropertiesHandler` và thực hiện trích xuất stream HLS Manifest bất đồng bộ (async).

**Tech Stack:** Objective-C / Logos (`.x`, `.m`), UIKit, Theos build system, MobileFFmpeg.

## Global Constraints

- Tuân thủ cấu trúc Theos, tương thích từ iOS 13 đến iOS 18+.
- Không được dùng `[UIApplication sharedApplication].keyWindow` trực tiếp gây crash `MBProgressHUD`.
- Luôn có fallback `UIAlertController` và SF Symbols khi YouTube API/Resource bị thay đổi.
- Bắt buộc kiểm tra biên dịch thành công bằng `make clean && make`.

---

### Task 1: Nâng cấp Safe UI Infrastructure & Window Resolution trong `FFMpegDownloader.m`

**Files:**
- Modify: `Source/FFMpegDownloader.m:20-50`, `Source/FFMpegDownloader.m:140-187`

**Interfaces:**
- Produces: `getFFMpegKeyWindow(void)` -> `UIWindow *`

- [ ] **Step 1: Thêm helper `getFFMpegKeyWindow` và cập nhật các vị trí gọi `keyWindow` trong `FFMpegDownloader.m`**
Thay thế `[UIApplication sharedApplication].keyWindow` bằng helper duyệt qua `connectedScenes` tại:
  - `downloadAudio:` (dòng 23, 44)
  - `downloadImage:` (dòng 146)
  - `shareMedia:` (dòng 183)

- [ ] **Step 2: Kiểm tra biên dịch**
Run: ` make`
Expected: Biên dịch `FFMpegDownloader.m` thành công không có lỗi.

- [ ] **Step 3: Commit**
```bash
 git add Source/FFMpegDownloader.m
 git commit -m "fix: replace deprecated keyWindow with scene-aware window helper in FFMpegDownloader"
```

---

### Task 2: Triển khai Safe Helpers & Player Tracking trong `Source/Downloading.x`

**Files:**
- Modify: `Source/Downloading.x:1-80`

**Interfaces:**
- Produces:
  - `getKeyWindow(void) -> UIWindow *`
  - `getTopViewController(void) -> UIViewController *`
  - `getAudioIcon(void) -> UIImage *`
  - `getCoverIcon(void) -> UIImage *`
  - `getActivePlayerViewController(UIView *fromView) -> YTPlayerViewController *`
  - `isDownloadNodeKey(NSString *key) -> BOOL`
  - Hook `YTMWatchViewController` (`viewWillAppear:`, `loadWithPlayerResponse:`)
  - Hook `YTPlayerViewController` (`setPlayerResponse:`)

- [ ] **Step 1: Viết các hàm Helper an toàn và Weak Reference Tracking trong `Downloading.x`**
Triển khai `getKeyWindow`, `getTopViewController`, `getAudioIcon`, `getCoverIcon`, `getActivePlayerViewController`, `isDownloadNodeKey`, và hooks `YTMWatchViewController`, `YTPlayerViewController`.

- [ ] **Step 2: Kiểm tra biên dịch**
Run: ` make`
Expected: Biên dịch thành công không có lỗi cú pháp.

- [ ] **Step 3: Commit**
```bash
 git add Source/Downloading.x
 git commit -m "feat: add safe helpers and player tracking in Downloading.x"
```

---

### Task 3: Triển khai Safe Download Sheet & Hook `ELMTouchCommandPropertiesHandler` trong `Source/Downloading.x`

**Files:**
- Modify: `Source/Downloading.x:80-210`

**Interfaces:**
- Produces:
  - `presentDownloadSheet(UIViewController *presentingVC, UIView *sourceView, YTPlayerViewController *playerVC, ELMTouchCommandPropertiesHandler *handler)`
  - Hook `ELMTouchCommandPropertiesHandler handleTap`
  - `%new - (void)downloadAudio:(YTPlayerViewController *)playerVC` (Async Manifest Parsing)
  - `%new - (void)downloadCoverImage:(YTPlayerViewController *)playerVC` (Safe High-Res Cover Download)

- [ ] **Step 1: Triển khai `presentDownloadSheet` và cập nhật `handleTap`**
  - Trong `handleTap`: Kiểm tra `isDownloadNodeKey(node.key)`, lấy `getActivePlayerViewController(tapRecognizer.view)`.
  - Gọi `presentDownloadSheet` để tự động điều phối theo Cài đặt (Audio / Cover / ActionSheet).
  - Cập nhật `downloadAudio:` thực hiện trích xuất `HLS Manifest` trên background queue `dispatch_async` và khử ký tự cấm trong tên file.
  - Cập nhật `downloadCoverImage:` lấy ảnh phân giải cao `w2048-h2048-` an toàn.

- [ ] **Step 2: Kiểm tra biên dịch toàn bộ tweak**
Run: ` make clean && make`
Expected: Build hoàn tất thành công (`Tweak.dylib` được tạo).

- [ ] **Step 3: Commit**
```bash
 git add Source/Downloading.x
 git commit -m "fix: resolve download button crash and enable menu download action"
```

---

### Task 4: Kiểm tra tổng thể & Xác minh (Verification)

**Files:**
- Verify: `Source/Downloading.x`, `Source/FFMpegDownloader.m`

- [ ] **Step 1: Chạy build release của Theos**
Run: ` make clean && make FINALPACKAGE=1`
Expected: Package `.deb` hoặc dylib được build thành công không có lỗi.

- [ ] **Step 2: Kiểm tra git status & diff sạch sẽ**
Run: ` git status`
Expected: Không có uncommitted changes hay file rác.
