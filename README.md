✨ 目前開發成果 (Current Achievements)
1. 雲端與邊緣協同架構 (Cloud-Edge Hybrid AI)
邊緣端 (Edge): 採用 Google ML Kit 進行每秒 60 幀的高速物理物件追蹤，確保畫面不卡頓且無需消耗大量 API 成本。

雲端 (Cloud): 串接 Gemini 2.5 Flash Lite API，進行專家級的影像構圖推理與調色參數計算。

2. 防彈級主體追蹤演算法 (Robust Object Tracking)
精準座標映射: 徹底解決了 Android/iOS 不同相機感光元件角度 (Sensor Orientation) 導致的座標錯亂與鏡像問題。

中心點鎖定演算法 (Centroid Tracking): 捨棄不可靠的預設 trackingId，改採歐幾里得距離計算，優先鎖定「距離畫面正中心最近」的實體物件，並實現死咬不放的追蹤效果。

3. Freeze & Guide 遊戲化拍攝工作流 (Gamified Workflow)
分析凍結 (Freeze): 按下 AI 分析按鈕瞬間，主動暫停相機預覽並重置鎖定目標，提供沉浸式的 Loading 等待體驗。

魔法時刻 (The Magic Moment): AI 計算完成後，畫面同時呈現「主體目前位置（黃圈）」與「最佳構圖位置（藍圈）」，並停留 2.5 秒讓使用者吸收決策。

動態對齊引導 (Interactive Guidance): 恢復相機預覽後，藍圈固定於最佳位置，黃圈跟隨現實物體移動。當兩者精準重疊時（距離小於容錯門檻），觸發箭頭消失與「綠色加粗完美構圖」的解鎖特效。

4. 相機狀態機與 UI 控制 (State Machine & UI)
實作 live, analyzing, magicMoment, guiding 四大狀態機，精準控制各階段的 UI 變化與相機生命週期。

支援手動中斷/重置流程，以及流暢的即時追蹤開關 (Toggle)。

📝 未來待辦事項 (TODO List)
【模組一】構圖法知識庫 (Composition Library)
[ ] UI 切版實作: 建立分類 Tab (Food, Portrait 等) 與下方 GridView 卡片列表。

[ ] 內容彙整: 蒐集 6-8 種經典構圖法（如三分法、S曲線、引導線）之無版權示意圖，並撰寫簡要中文說明。

[ ] 導覽串接: 確保能從主畫面順暢導航至此教育模組。

【模組二】歷史相簿與雲端儲存 (Gallery & Cloud Storage)
[ ] Firebase 基礎建設: 專案掛載 cloud_firestore 與 firebase_storage。

[ ] 資料拋轉與上傳: 在相機頁面按下快門時，將「高畫質原圖」上傳至 Storage，並將對應的「AI 決策 JSON 參數」存入 Firestore。

[ ] 相簿 UI: 實作九宮格相簿介面，並從 Firestore 動態載入歷史圖片。

【模組三】後期影像編輯器 (Photo Editor)
[ ] 編輯器 UI 切版: 包含單張圖片顯示、Before/After 預覽切換按鈕，以及「套用 AI 建議」的大按鈕。

[ ] 影像處理套件整合: 導入適當的 Flutter 濾鏡/色彩矩陣套件（如 photofilters）。

[ ] AI 參數一鍵套用: 讀取拍攝時傳遞過來的 Gemini JSON 參數（如亮度、飽和度、對比），並轉換為視覺濾鏡數值渲染於原圖上。

[ ] 手動微調機制: 實作下方 Slider 拉桿，與影像濾鏡參數進行雙向綁定。

[ ] 儲存功能: 允許使用者儲存編輯後的最終成果至雲端。