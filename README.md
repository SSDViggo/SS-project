# 2026-06-12
# 專案架構說明

整理目前 `lib/` 內各模組的狀態

## 目前App實際運作的流程（main.dart 啟動）

```
main.dart
  └─ PhotoAssistantScreen（首頁）
       └─ pages/camera_scene.dart（FullScreenCameraScreen，相機主畫面）
            ├─ tools/object_detector_service.dart   ML Kit 物件偵測
            ├─ tools/camera_settings_service.dart   套用AI建議的曝光/閃光燈設定
            ├─ tools/composition_overlay_manager.dart / rule_of_thirds_grid.dart  構圖網格
            ├─ tools/ai_guidance_overlay.dart        AI建議位置的視覺提示
            ├─ tools/gemini_composition_service.dart Gemini構圖建議（API呼叫+JSON解析）
            ├─ providers/camera_provider.dart        全域共享的「已拍照片清單」
            ├─ screens/library_screen.dart           顯示已拍攝的照片（圖庫）
            └─ screens/edit_screen.dart              根據AI以及使用者調整顯示預覽圖片
```

**已實作的功能**
- 即時相機預覽（後置/前置切換）
- 即時物件偵測 + AI構圖建議 overlay
- 拍照並存入「圖庫」（LibraryScreen）
- Gemini AI構圖分析（含曝光/閃光燈建議）
- 閃光燈開關、翻轉鏡頭
- 內建測試圖片（`test_images/food1.jpg`），無相機/模擬器相機異常時可用來測試ML Kit
- 修改圖片功能

**已知限制**
- `screens/library_screen.dart` 顯示的照片清單存在 `CameraProvider`（記憶體中），
  App重啟後會清空，尚未做持久化儲存
- 部分Android模擬器的「Emulated」前置鏡頭 + nv21格式可能無法正常顯示畫面，
  這是模擬器環境限制，非程式邏輯問題

---

## 尚未整合進主流程的模組

以下模組程式碼存在，但 `main.dart` 目前沒有任何路徑會進入它們。
保留是因為它們是完整或部分完成的功能，未來整合App導航時可以直接使用。

### Todo清單模組（MVVM + Firebase）

```
services/navigation.dart
views/
view_models/
models/
utils/categories.dart
```

### 獨立畫面（UI已完成，但功能多為空殼）

```
screens/home_screen.dart    首頁UI（與main.dart的PhotoAssistantScreen是兩套不同設計）
screens/camera_screen.dart  另一套相機畫面UI（與pages/camera_scene.dart重複）
```
---

TODO: 修正取得建議後顯示建議的方法