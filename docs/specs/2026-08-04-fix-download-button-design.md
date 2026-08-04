# Spec: Sửa lỗi nút Download Music không hoạt động trong YTMusicUltimate

- **Ngày tạo**: 2026-08-04
- **Mục tiêu**: Khắc phục sự cố nút download music trên giao diện YTMusic không có phản ứng khi bấm vào.

---

## 1. Nguyên nhân Sự cố (Problem Diagnosis)

Khi bấm vào nút download trên giao diện phát nhạc (Now Playing), hệ thống hoàn toàn không có phản ứng (không mở ActionSheet, không tải file, không báo lỗi). Qua kiểm tra [Downloading.x](file:///Users/bez/Workspace/repos/bez/YTMusicUltimate/Source/Downloading.x), các nguyên nhân chính bao gồm:
1. **Khóa phần tử (`node.key`) bị thay đổi**: YTMusic bản mới không còn dùng key cố định `"music_download_badge_1"`.
2. **ViewController Hierarchy bị lệch**: Việc kiểm tra `isKindOfClass:[YTMNowPlayingViewController class]` trực tiếp trên `view._viewControllerForAncestor` bị thất bại khi cấu trúc view container thay đổi.
3. **Cấu hình `NSUserDefaults` bị bỏ qua âm thầm**: Nếu cả `downloadAudio` và `downloadCoverImage` đều chưa được bật (hoặc bằng `NO`), logic trong `handleTap` chặn sự kiện nhưng không trình bày `YTMActionSheetController` và không chuyển giao cho `%orig`.

---

## 2. Giải pháp Thiết kế (Design Solution)

### A. Mở rộng Nhận diện Element Node (`node.key`)
- Thêm kiểm tra linh hoạt với nhiều mẫu key khả thi cho nút download:
  - `music_download_badge_1`
  - `music_download_badge`
  - `download_badge`
  - Hoặc kiểm tra `node.key` chứa chuỗi `"download"`.

### B. Helper Tìm kiếm ViewController (`YTMNowPlayingViewController`)
- Xây dựng helper tìm kiếm `YTMNowPlayingViewController` lùi lên trên sơ đồ cây phân cấp (`parentViewController` / `nextResponder`), thay vì chỉ phụ thuộc vào `_viewControllerForAncestor` tức thời.

### C. Cập nhật Logic Xử lý Cài đặt & ActionSheet
- Cập nhật logic điều kiện trong `handleTap`:
  ```objc
  BOOL audioEnabled = YTMU(@"downloadAudio");
  BOOL coverEnabled = YTMU(@"downloadCoverImage");

  // Nếu cả 2 cùng bật HOẶC cả 2 cùng chưa bật (mặc định) -> Hiển thị ActionSheet cho người dùng chọn
  if ((audioEnabled && coverEnabled) || (!audioEnabled && !coverEnabled)) {
      [sheetController presentFromViewController:playingVC animated:YES completion:nil];
  } else if (audioEnabled) {
      [self downloadAudio:playerVC];
  } else if (coverEnabled) {
      [self downloadCoverImage:playerVC];
  }
  ```

---

## 3. Các Tệp Ảnh Hưởng (Affected Files)

- [Downloading.x](file:///Users/bez/Workspace/repos/bez/YTMusicUltimate/Source/Downloading.x): Cập nhật hook `ELMTouchCommandPropertiesHandler`, logic `handleTap`, bổ sung helper tìm ViewController.

---

## 4. Kế hoạch Kiểm thử (Verification Plan)

1. **Build Tweak**: Kiểm tra biên dịch thành công bằng `make clean package`.
2. **Kiểm tra tương tác**:
   - Bấm nút download khi cài đặt ở trạng thái mặc định -> Đảm bảo hiển thị ActionSheet chọn "Tải Audio" / "Tải Ảnh bìa".
   - Bấm nút download khi chỉ bật "Tải Audio" trong Settings -> Đảm bảo tự động thực hiện tải audio.
   - Bấm nút download khi chỉ bật "Tải Ảnh bìa" trong Settings -> Đảm bảo tự động thực hiện tải ảnh bìa.
