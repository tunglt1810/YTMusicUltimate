# Kế hoạch Thực thi: Sửa lỗi nút Download trong Menu "..." và Crash trên Playback Controller

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Khắc phục lỗi nút download mở từ menu "..." không có tác dụng và lỗi crash khi bấm nút download trên playback controller.

**Architecture:** Cập nhật [Source/Downloading.x](file:///Users/bez/Workspace/repos/bez/YTMusicUltimate/Source/Downloading.x) để theo dõi và tìm kiếm `YTPlayerViewController` linh hoạt, lấy icon an toàn không gây crash selector, hiển thị action sheet với fallback an toàn `UIAlertController`, và trích xuất manifest URL bất đồng bộ.

**Tech Stack:** Objective-C, Logos / Theos (%hook, %c), UIKit.

---

## Global Constraints
- Tất cả các lệnh shell phải bắt đầu bằng một khoảng trắng (` `).
- Tuân thủ cấu trúc thư mục quy định (`docs/specs`, `docs/plans`, `.tmp`).

---

### Task 1: Cập nhật toàn diện Source/Downloading.x

**Files:**
- Modify: `Source/Downloading.x`

**Interfaces:**
- Consumes: `YTPlayerViewController`, `YTMWatchViewController`, `YTMNowPlayingViewController`, `ELMTouchCommandPropertiesHandler`, `FFMpegDownloader`
- Produces: Safe download handler for both playback bar and "..." menu without crashes or unrecognized selectors.

- [ ] **Step 1: Viết mã nguồn hoàn chỉnh cho Downloading.x**
  - Khai báo static weak pointers theo dõi `YTPlayerViewController` và `YTMWatchViewController`.
  - Tạo hàm helper `getActivePlayerViewController(UIView *fromView)`.
  - Tạo hàm helper `getAudioIcon()` và `getCoverIcon()` an toàn với `respondsToSelector:`, `YTAssetLoader`, và SF Symbols.
  - Tạo hàm helper `presentDownloadSheet(...)` hỗ trợ cả `YTMActionSheetController` và `UIAlertController` fallback.
  - Xử lý trích xuất manifest bất đồng bộ kèm HUD hiển thị và bảo vệ dữ liệu metadata (`title`, `author`).
  - Xử lý tải ảnh bìa `downloadCoverImage` an toàn.

- [ ] **Step 2: Kiểm tra cú pháp và định dạng file**
  - Kiểm tra diff của `Source/Downloading.x` để đảm bảo không còn selector thiếu an toàn hay logic chặn cứng `YTMNowPlayingViewController`.

- [ ] **Step 3: Commit thay đổi vào git**
  - Chạy lệnh git commit với message chuẩn hóa.
