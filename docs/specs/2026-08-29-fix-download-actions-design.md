# Tài liệu Thiết kế: Khắc phục sự cố nút Download trong Menu "..." và Crash trên Playback Controller

- **Ngày tạo**: 2026-08-29
- **Tác giả**: Antigravity
- **Trạng thái**: Đã phê duyệt (Approved)

---

## 1. Mục tiêu (Goals)

1. **Khắc phục lỗi nút Download trong Menu "..." không có tác dụng**: Cho phép người dùng tải bài hát/ảnh bìa trực tiếp khi nhấn nút Download trong menu More Options ("...") của YouTube Music.
2. **Khắc phục lỗi Crash khi bấm nút Download trên Playback Controller**: Loại bỏ các ngoại lệ `NSInternalInconsistencyException` (do `keyWindow` nil trên iOS mới) và `NSInvalidArgumentException` (do gọi selector/class không còn tồn tại trên các bản YouTube Music mới).
3. **Đồng bộ hành vi với Cài đặt (Settings)**:
   - Nếu cả 2 tùy chọn "Tải Audio" và "Tải Ảnh bìa" cùng bật hoặc cùng tắt (mặc định): Hiển thị ActionSheet cho người dùng lựa chọn.
   - Nếu chỉ bật riêng "Tải Audio": Tự động tải Audio không cần hỏi lại.
   - Nếu chỉ bật riêng "Tải Ảnh bìa": Tự động tải Ảnh bìa không cần hỏi lại.

---

## 2. Kiến trúc & Giải pháp Kỹ thuật (Technical Design)

### 2.1. Safe UI & Anti-Crash Infrastructure (`Downloading.x`)

- **Helper `getKeyWindow()`**:
  Duyệt qua `[UIApplication sharedApplication].connectedScenes` tìm `UIWindowScene` đang hoạt động (`UISceneActivationStateForegroundActive`), lấy `isKeyWindow` hoặc window đầu tiên. Fallback sang `windows.firstObject`. Đảm bảo `MBProgressHUD` luôn có `UIView` hợp lệ để hiển thị.
  
- **Helper `getTopViewController()`**:
  Tìm ViewController trên cùng đang hiển thị từ `rootViewController` của `getKeyWindow()`, hỗ trợ `presentedViewController`, `UINavigationController`, `UITabBarController`.

- **Safe Icon Helpers (`getAudioIcon()`, `getCoverIcon()`)**:
  Kiểm tra an toàn `respondsToSelector:` trên `YTUIResources`. Nếu không có, fallback sang `YTAssetLoader` hoặc SF Symbols (`music.note`, `photo`).

### 2.2. Player Tracking & Interception (`getActivePlayerViewController`)

- **Global Tracking**:
  Hook `YTMWatchViewController` (`viewWillAppear:`, `loadWithPlayerResponse:`) và `YTPlayerViewController` (`setPlayerResponse:`) để duy trì weak reference (`gActiveWatchViewController`, `gActivePlayerViewController`).

- **Duyệt Responder Chain & Hierarchy**:
  Khi phát sinh sự kiện tap, `getActivePlayerViewController(UIView *fromView)` sẽ:
  1. Duyệt chuỗi Responder của `fromView` để tìm `YTMNowPlayingViewController` hoặc `YTMWatchViewController`.
  2. Fallback sang `gActiveWatchViewController.playerViewController` hoặc `gActivePlayerViewController`.
  3. Fallback quét cây phân cấp của `getKeyWindow().rootViewController`.

### 2.3. Hook `ELMTouchCommandPropertiesHandler`

- **Nhận diện Element Node Key**:
  Hỗ trợ danh sách key mở rộng:
  - `music_download_badge`
  - `music_download_badge_1`
  - `download_badge`
  - `download_action`
  - `offline_action`
  - `menu_item_download`
  - Chuỗi chứa `download` hoặc `offline`.

- **Xử lý sự kiện**:
  Không giới hạn cứng ở `YTMNowPlayingViewController`. Bất cứ khi nào nhận diện nút download và tìm được `activePlayerVC`, kích hoạt quy trình `presentDownloadSheet`.

### 2.4. Trình bày Menu Tải & Thực thi Tải Bất đồng bộ

- **`presentDownloadSheet`**:
  - Đọc cấu hình từ `NSUserDefaults` (`YTMUltimate`).
  - Hiển thị `YTMActionSheetController` (với try-catch) hoặc fallback sang `UIAlertControllerStyleActionSheet` (có cấu hình `popoverPresentationController` cho iPad).
  
- **`downloadAudio`**:
  - Hiển thị HUD trạng thái "Đang chuẩn bị...".
  - Trích xuất HLS Manifest URL trên background queue (`dispatch_async`) để chống khựng giao diện.
  - Chuẩn hóa tên file (loại bỏ ký tự cấm `/`, `\`, `:`).
  - Khởi động `FFMpegDownloader` tải stream `.m4a` và lưu thumbnail vào thư mục `YTMusicUltimate/`.

- **`downloadCoverImage`**:
  - Trích xuất ảnh bìa chất lượng cao (`w2048-h2048-`).
  - Tải và lưu vào Album ảnh thông qua `FFMpegDownloader`.

---

## 3. Tệp tin thay đổi (Affected Files)

- [Source/Downloading.x](file:///Users/bez/Workspace/repos/bez/YTMusicUltimate/Source/Downloading.x): Nâng cấp toàn bộ logic hooking, tracking, safe window, safe sheet, async manifest extraction.

---

## 4. Kế hoạch Kiểm thử & Xác minh (Verification Plan)

### 4.1. Kiểm tra Biên dịch (Build Verification)
- Chạy lệnh build Theos:
  ```bash
   make clean && make
  ```
  Xác nhận không có lỗi cú pháp hoặc warning nghiêm trọng.

### 4.2. Kiểm thử Chức năng (Functional Verification)
1. **Kiểm tra nút Download trên Playback Controller**:
   - Mở bài hát bất kỳ, nhấn nút Download trên thanh điều khiển phát nhạc.
   - Xác nhận không bị crash, hiển thị ActionSheet lựa chọn (Audio / Ảnh bìa).
2. **Kiểm tra nút Download trong Menu "..."**:
   - Nhấn vào menu 3 chấm trên thanh phát nhạc hoặc góc trên cùng.
   - Nhấn vào mục "Download" / "Tải xuống".
   - Xác nhận menu tải của tweak được kích hoạt thành công.
3. **Kiểm tra Tùy chọn Cài đặt**:
   - Bật chỉ "Tải Audio" trong Settings -> Bấm nút Download -> Tải audio trực tiếp.
   - Bật chỉ "Tải Ảnh bìa" trong Settings -> Bấm nút Download -> Tải ảnh bìa trực tiếp.
