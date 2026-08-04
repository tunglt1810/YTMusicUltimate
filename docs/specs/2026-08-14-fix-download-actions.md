# Spec: Sửa lỗi nút Download trong Menu "..." và Crash trên Playback Controller

- **Ngày tạo**: 2026-08-14
- **Mục tiêu**: 
  1. Khắc phục lỗi nút download mở từ menu "..." không có phản ứng / không hoạt động.
  2. Khắc phục lỗi crash ứng dụng khi bấm vào nút download trên playback controller (thanh điều khiển phát nhạc).

---

## 1. Nguyên nhân sự cố (Root Cause Analysis)

### Sự cố 1: Nút Download trong menu "..." không có tác dụng
- Trong `Source/Downloading.x`, hook `ELMTouchCommandPropertiesHandler handleTap` kiểm tra điều kiện cứng:
  ```objc
  if (![tapRecognizer.view._viewControllerForAncestor isKindOfClass:%c(YTMNowPlayingViewController)]) {
      return %orig;
  }
  ```
- Khi mở menu "..." (More Options), YouTube Music hiển thị một ActionSheet / BottomSheet modal (view controller là `YTActionSheetViewController`, `GOOBottomSheetController`, v.v.). View của phần tử Download nằm trong cây phân cấp của Sheet Controller, khiến `_viewControllerForAncestor` KHÔNG phải là `YTMNowPlayingViewController`.
- Kết quả là lệnh chạm bị bỏ qua và rơi vào `%orig` (tính năng offline mặc định cần tài khoản YouTube Premium server-side, dẫn đến việc không có phản ứng nào xảy ra).

### Sự cố 2: Nút Download trên Playback Controller bị Crash
- Khi bấm nút Download trên thanh điều khiển phát nhạc (Now Playing):
  - Code gọi `[%c(YTUIResources) outlineImageWithColor:[UIColor whiteColor]]` và `[%c(YTUIResources) audioOutline]`. Trong các phiên bản YouTube Music mới, class `YTUIResources` không có selector `outlineImageWithColor:` (hoặc `audioOutline`), dẫn đến ngoại lệ `NSInvalidArgumentException: unrecognized selector sent to class YTUIResources` làm ứng dụng crash ngay lập tức.
  - Việc khởi tạo và gọi `[%c(YTMActionSheetController) musicActionSheetController]` thiếu `respondsToSelector:` và try-catch, không có fallback an toàn sang `UIAlertController`.
  - Việc trích xuất manifest URL chạy đồng bộ trên main thread có thể gây block giao diện.

---

## 2. Giải pháp kỹ thuật (Design Solution)

### A. Quản lý và Tìm kiếm Controller Linh hoạt (`getActivePlayerViewController`)
- Hook `YTPlayerViewController` và `YTMWatchViewController` để lưu weak reference đến view controller đang phát nhạc (`gActivePlayerViewController`, `gActiveWatchViewController`).
- Xây dựng hàm `getActivePlayerViewController(UIView *fromView)`:
  1. Duyệt responder chain từ `fromView` (hỗ trợ cả view trong modal / sheet thông qua `presentingViewController`).
  2. Fallback sang `gActiveWatchViewController.playerViewController` hoặc `gActivePlayerViewController`.
  3. Fallback tìm kiếm trong cây phân cấp của `keyWindow.rootViewController`.

### B. Nhận diện Nút Download Toàn diện (`isDownloadNodeKey`)
- Hỗ trợ đầy đủ các key Element UI cho Download/Offline cả ở Playback Bar lẫn trong Menu "...":
  - `music_download_badge`
  - `music_download_badge_1`
  - `download_badge`
  - `download_action`
  - `offline_action`
  - `menu_item_download`
  - Hoặc key chứa chuỗi `"download"` / `"offline"`.

### C. Lấy Icon An toàn Tuyệt đối (`getAudioIcon`, `getCoverIcon`)
- Kiểm tra `respondsToSelector:` trước khi gọi bất kỳ method nào trên `YTUIResources`.
- Fallback sang `YTAssetLoader` (`yt_outline_audio_24pt`, `youtube_outline/image_24pt`).
- Fallback tiếp sang SF Symbols (`music.note`, `photo`).

### D. Trình bày Menu Tải An toàn & Crash-Proof (`presentDownloadSheet`)
- Kiểm tra `YTMActionSheetController` và `YTActionSheetAction` với `@try/@catch` và `respondsToSelector:`.
- Fallback tự động sang `UIAlertController` chuẩn của UIKit nếu `YTMActionSheetController` không khả dụng.
- Tự động tìm top view controller hợp lệ và cấu hình `popoverPresentationController` cho iPad.

### E. Tải Manifest Bất đồng bộ (Async Download Extraction)
- Đưa logic trích xuất manifest URL sang background queue (`dispatch_async`) kèm hiển thị HUD trạng thái "DOWNLOADING", sau đó cập nhật UI và khởi động `FFMpegDownloader`.
- Bổ sung giá trị mặc định cho `title`, `author`, `tempName` để tránh lỗi dữ liệu rỗng.

---

## 3. Các tệp tin bị ảnh hưởng (Affected Files)

- [Source/Downloading.x](file:///Users/bez/Workspace/repos/bez/YTMusicUltimate/Source/Downloading.x): Cập nhật toàn bộ logic hook `ELMTouchCommandPropertiesHandler`, tracking controller, safe icons, safe sheet presentation, async manifest extraction.
