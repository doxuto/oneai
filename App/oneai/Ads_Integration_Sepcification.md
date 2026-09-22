# 📢 Ads Integration Specification – One AI App (Master Version - Final)

---
*Tài liệu này là phiên bản tổng hợp cuối cùng, mô tả chi tiết chiến lược, vị trí, quy tắc, trải nghiệm người dùng và cấu hình kỹ thuật cho việc tích hợp quảng cáo trong ứng dụng One AI.*
---

## MỤC LỤC CÁC VỊ TRÍ QUẢNG CÁO

A. Open App Ad
B. Interstitial Ad – Từ Home sang Summary (Trước khi xem chi tiết)
C. Interstitial Ad – Sau khi xử lý âm thanh
D. Interstitial Ad – Sau khi Chia sẻ tệp
E. Interstitial Ad – Từ Settings về Home
F. Interstitial Ad – Từ Summary về Home
G. Rewarded Ad – Nhận thêm credit
H. Banner Ads – Trong các tab nội dung

---
## PHÂN TÍCH CHI TIẾT CÁC TRƯỜNG HỢP SỬ DỤNG (USE CASES)

### 1. 🔹 Use Case: Mở ứng dụng sau một thời gian dài (Vị trí A)

* **Mục đích:** Tạo doanh thu từ những phiên làm việc mới của người dùng.
* **Luồng Người dùng:** Khi người dùng mở ứng dụng sau khi đã không sử dụng một thời gian dài, họ sẽ thấy một quảng cáo toàn màn hình. Quảng cáo có thể được bỏ qua sau vài giây và sau đó người dùng sẽ vào màn hình Home.
* **Quy tắc & Điều kiện (Áp dụng Remote Config):**
    * Tính năng này được bật/tắt bởi **`ad_open_app_enabled`**.
    * Chỉ xuất hiện nếu người dùng đã rời ứng dụng một khoảng thời gian tối thiểu, định nghĩa bởi **`ad_open_app_background_threshold_minutes`** (mặc định: 30 phút).
    * Thời gian chờ tải quảng cáo tối đa được kiểm soát bởi **`ad_load_timeout_seconds`** (mặc định: 5 giây).
* **Lý giải & Tuân thủ Chính sách:**
    * Quy tắc 30 phút nhằm tuân thủ hướng dẫn của AdMob về việc **không hiển thị quảng cáo App Open trong mỗi lần mở ứng dụng**, tránh gây phiền nhiễu cho người dùng khi họ chỉ chuyển app nhanh.
* **Phân tích Corner Case & Hướng xử lý:**
  | Tình huống (Scenario) | Hành vi mong muốn của Ứng dụng | Lý do (Rationale) |
  | :--- | :--- | :--- |
  | **Không có kết nối Internet** khi mở ứng dụng. | Ứng dụng sẽ bỏ qua hoàn toàn luồng quảng cáo và điều hướng người dùng thẳng vào màn hình Home ngay lập tức. | Khởi động ứng dụng là ưu tiên số một. Không bao giờ được phép chặn người dùng vào app chỉ vì không tải được quảng cáo. |
  | **Mạng chậm, tải quảng cáo quá thời gian**. | Sau khoảng thời gian chờ (mặc định 5 giây), ứng dụng sẽ tự động hủy yêu cầu tải quảng cáo và tiếp tục vào màn hình Home. | Tôn trọng thời gian của người dùng. Họ không cần phải chờ đợi một thành phần không thiết yếu như quảng cáo. |
  | **AdMob không có quảng cáo để hiển thị** (No Fill). | Đây được coi là một trường hợp tải lỗi. Ứng dụng sẽ nhận được phản hồi và ngay lập tức đưa người dùng vào màn hình Home. | Đảm bảo luồng hoạt động mượt mà, không bị "đứng hình" ở màn hình chờ. |

### 2. 🔹 Use Case: Các hành động chuyển tiếp trong ứng dụng (Vị trí B, C, D, E, F)

* **Mục đích:** Tạo doanh thu tại các điểm dừng và chuyển tiếp tự nhiên trong hành trình của người dùng.
* **Luồng Người dùng:** Sau khi hoàn thành một tác vụ (ví dụ: chọn một bản ghi từ Home để xem chi tiết), một quảng cáo xen kẽ toàn màn hình có thể xuất hiện. Sau khi đóng quảng cáo, người dùng sẽ tiếp tục luồng của mình.
* **Quy tắc & Điều kiện (Áp dụng Remote Config):**
    * Toàn bộ các vị trí quảng cáo xen kẽ được bật/tắt chung bởi cờ **`ad_interstitial_enabled`**.
    * **Quy tắc tần suất toàn cục:** Một quảng cáo xen kẽ sẽ không hiển thị nếu một quảng cáo toàn màn hình khác (kể cả Open App Ad hoặc Rewarded Ad) vừa xuất hiện trong vòng **`ad_fullscreen_global_freq_seconds`** (mặc định: 120 giây).
* **Lý giải & Tuân thủ Chính sách:**
    * Các vị trí này được chọn vì chúng là **"Điểm chuyển tiếp tự nhiên" (Natural Transition Point)**, tuân thủ chính sách của AdMob.
    * Quy tắc tần suất toàn cục giúp ngăn chặn "Ad Stacking" và tuân thủ chính sách về **"Quảng cáo lặp lại hoặc gây rối" (Repetitive or Disruptive Ads)**.
* **Trường hợp đặc biệt (Vị trí F - Từ Summary về Home):**
    * Quảng cáo này sẽ bị **bỏ qua** nếu đây là lần đầu người dùng thực hiện hành động này, để ưu tiên hiển thị **popup mời đánh giá ứng dụng**.
* **Phân tích Corner Case & Hướng xử lý:**
  | Tình huống (Scenario) | Hành vi mong muốn của Ứng dụng | Lý do (Rationale) |
  | :--- | :--- | :--- |
  | **Không có Internet/Mạng chậm/No Fill** khi kích hoạt quảng cáo. | Quảng cáo sẽ không được hiển thị. Ứng dụng sẽ **ngay lập tức** thực hiện hành động tiếp theo (ví dụ: điều hướng đến màn hình Summary). | Luồng tác vụ của người dùng là ưu tiên. Quảng cáo là một thành phần phụ, nếu nó thất bại, hành động chính của người dùng phải được hoàn thành mà không bị gián đoạn. |
  | Người dùng **nhấn Back hoặc điều hướng đi nơi khác** trong khi quảng cáo đang tải. | Yêu cầu tải quảng cáo phải được hủy ngay lập tức. | Ngăn chặn việc quảng cáo hiển thị "lạc lõng" hoặc không đúng ngữ cảnh sau khi người dùng đã chuyển sang một màn hình khác. |

### 3. 🔹 Use Case: Hết credit và cần xử lý tệp (Vị trí G)

* **Mục đích:** Giữ chân người dùng miễn phí bằng cách cung cấp lựa chọn để nhận thêm tài nguyên.
* **Luồng Người dùng:**
    1.  Khi người dùng hết credit, nút "Transcribe & Summary" sẽ chuyển thành "Watch Ad to Transcribe".
    2.  Người dùng chủ động nhấn vào nút này.
    3.  Một quảng cáo video toàn màn hình sẽ phát. Người dùng phải xem hết video.
    4.  Sau khi xem xong, một thông báo `"✅ You received 1 free credit!"` xuất hiện, và quá trình xử lý tệp của họ tự động bắt đầu.
* **Quy tắc & Điều kiện (Áp dụng Remote Config):**
    * Tính năng này được bật/tắt bởi **`ad_rewarded_enabled`**.
    * Mỗi người dùng chỉ có thể xem tối đa **`ad_rewarded_daily_limit`** lần mỗi ngày. Nếu giá trị này là **0**, người dùng có thể xem không giới hạn.
    * Nếu người dùng đóng quảng cáo sớm, họ sẽ nhận được thông báo `"⚠️ Ad not completed. No credit awarded."`
* **Lý giải & Tuân thủ Chính sách:**
    * Mô hình này tuân thủ chính sách **"opt-in"** của AdMob cho quảng cáo có thưởng. Việc kiểm soát giới hạn hàng ngày bằng Remote Config cho phép chúng ta điều chỉnh nền kinh tế trong ứng dụng một cách linh hoạt.
* **Phân tích Corner Case & Hướng xử lý:**
  | Tình huống (Scenario) | Hành vi mong muốn của Ứng dụng | Lý do (Rationale) |
  | :--- | :--- | :--- |
  | **Không có kết nối Internet** trước khi nhấn nút. | Nút "Watch Ad to Transcribe" sẽ bị vô hiệu hóa (hiển thị màu xám). Nếu người dùng nhấn vào, một thông báo ngắn (toast) sẽ hiện ra: `"📡 Please connect to the internet..."` | Cung cấp phản hồi rõ ràng cho người dùng về lý do họ không thể thực hiện hành động, tránh gây nhầm lẫn. |
  | **AdMob không có quảng cáo để hiển thị** (No Fill) khi nhấn nút. | Hiển thị thông báo: `"⚠️ No rewarded ads available at the moment. Please try again later."` Nút vẫn hoạt động để người dùng có thể thử lại sau đó. | Quản lý kỳ vọng của người dùng và khuyến khích họ thử lại, thay vì nghĩ rằng tính năng bị lỗi. |
  | **Mất mạng sau khi xem hết quảng cáo**, trước khi gọi API cộng thưởng. | Ứng dụng sẽ hiển thị thông báo tích cực: `“✅ Ad completed! We will add your credit soon…”` | **Không bao giờ trừng phạt người dùng vì lỗi kỹ thuật.** Hệ thống phải lưu lại trạng thái "chờ cộng thưởng" và tự động đồng bộ với máy chủ ở lần có kết nối tiếp theo để đảm bảo quyền lợi của họ. |

### 4. 🔹 Use Case: Hiển thị Banner quảng cáo (Vị trí H)

* **Mục đích:** Tạo doanh thu một cách liên tục mà ít gây gián đoạn nhất cho người dùng khi họ đang xem nội dung.
* **Luồng Người dùng:** Khi người dùng truy cập các màn hình có nội dung dài như Summary, Transcript, hay Chat, một banner quảng cáo nhỏ sẽ xuất hiện ở đầu hoặc cuối màn hình và giữ nguyên ở đó khi người dùng cuộn. Banner này sẽ tự động được thay thế bằng một quảng cáo mới sau một khoảng thời gian.
* **Quy tắc & Điều kiện:**
    * **Tự động làm mới:** Tần suất làm mới được cấu hình **trực tiếp trên giao diện AdMob** (ví dụ: 60 giây). SDK của AdMob sẽ tự động xử lý việc này.
* **Lý giải & Tuân thủ Chính sách:**
    * Đây là phương pháp chuẩn và đơn giản nhất, được AdMob khuyến nghị. Nó đảm bảo banner luôn mới mẻ để tăng cơ hội hiển thị và doanh thu mà không cần can thiệp từ code ứng dụng.

---
## QUY TẮC CHUNG VÀ XỬ LÝ XUNG ĐỘT

* **(QUAN TRỌNG) Quy tắc Vàng - Chống Chồng chéo:**
    * Hệ thống **BẮT BUỘC** phải duy trì một biến trạng thái toàn cục (ví dụ: `isFullScreenAdShowing`) để theo dõi việc một quảng cáo toàn màn hình (Open App, Interstitial, Rewarded) có đang hiển thị hay không.
    * Bất kỳ luồng logic nào chuẩn bị hiển thị một quảng cáo mới đều phải kiểm tra biến này trước tiên. Nếu nó đang là `true`, luồng hiển thị quảng cáo mới phải được **hủy bỏ ngay lập tức**.
    * **Lý do:** Đây là lớp bảo vệ cuối cùng và quan trọng nhất để chống lại mọi trường hợp lỗi hoặc logic xung đột có thể gây ra việc hai quảng cáo hiển thị cùng lúc, đảm bảo tuân thủ tuyệt đối chính sách "Ad Stacking".

* **(MỚI) Quy tắc Tải trước (Preload) và Vòng đời Quảng cáo:**
    * **Yêu cầu Preload:** Tất cả các quảng cáo toàn màn hình (Open App, Interstitial, Rewarded) **BẮT BUỘC** phải được tải trước (preload) trong nền trước khi đến điểm kích hoạt để đảm bảo hiển thị tức thì.
    * **Thời gian Hết hạn:** Một đối tượng quảng cáo đã được tải thành công sẽ **tự động hết hạn sau 1 giờ**. Cố gắng hiển thị một quảng cáo đã hết hạn sẽ thất bại.
    * **Quản lý Vòng đời (Best Practice):** Để tránh lỗi hết hạn và quản lý bộ nhớ hiệu quả, vòng đời của đối tượng quảng cáo phải được **gắn liền với vòng đời của màn hình** nơi nó được sử dụng.
        * **Khi vào màn hình:** Bắt đầu tải trước quảng cáo.
        * **Khi rời màn hình (dispose):** Hủy (dispose) đối tượng quảng cáo đã tải, bất kể nó đã được hiển thị hay chưa.

* **Tần suất Toàn cục:**
    * Một "thời gian nghỉ" tối thiểu là **`ad_fullscreen_global_freq_seconds`** được áp dụng sau khi một quảng cáo toàn màn hình kết thúc.
    * **Quy tắc:**
        1.  **`Interstitial Ad -> Rewarded Ad`**: Cần áp dụng "thời gian nghỉ".
        2.  **`Rewarded Ad -> Interstitial Ad`**: Cần áp dụng "thời gian nghỉ".
        3.  **`Rewarded Ad -> Rewarded Ad`**: **KHÔNG CẦN** áp dụng "thời gian nghỉ".
    * **Lý do:** Quy tắc này được thiết kế để ngăn chặn các quảng cáo **bị động** (Interstitial/Open App) xuất hiện dồn dập, nhưng vẫn cho phép người dùng **chủ động** xem nhiều quảng cáo có thưởng liên tiếp nếu họ muốn.

* **Xung đột Rate Popup vs. Interstitial:** Popup mời đánh giá ứng dụng luôn được **ƯU TIÊN** hơn quảng cáo Interstitial tại cùng một điểm kích hoạt.
* **Người dùng Premium:** Sẽ không thấy bất kỳ quảng cáo nào.

---
## 🚫 CÁC LUỒNG BỊ CẤM VÀ PHÂN TÍCH VI PHẠM

Mục này làm rõ các kịch bản hiển thị quảng cáo **KHÔNG ĐƯỢC PHÉP** triển khai để tránh vi phạm chính sách.

### **Luồng bị cấm 1: Interstitial ngay sau Rewarded Ad**
* **Kịch bản:** User xem Rewarded Ad -> Xử lý xong -> User nhấn "Xem kết quả" -> **Hiển thị Interstitial Ad**...
* **Tại sao vi phạm:** Phá vỡ kỳ vọng của người dùng sau khi nhận thưởng, vi phạm chính sách về **"Quảng cáo gây rối" (Disruptive Ads)**.

### **Luồng bị cấm 2: Interstitial ngay sau Open App Ad**
* **Kịch bản:** User mở app -> **Hiển thị Open App Ad** -> Tắt ad -> User nhấn vào item -> **Hiển thị Interstitial Ad**.
* **Tại sao vi phạm:** Gây ra "Ad Stacking" (xếp chồng quảng cáo), tạo trải nghiệm người dùng tồi tệ, vi phạm nghiêm trọng chính sách về **"Quảng cáo gây rối"**.

**Giải pháp cho cả hai luồng bị cấm:** Quy tắc **Tần suất Toàn cục** (`ad_fullscreen_global_freq_seconds`) phải được áp dụng một cách nghiêm ngặt.

---
## ⚙️ CẤU HÌNH TỪ XA (REMOTE CONFIG)

| Tham số                                 | Mô tả                                                               | Giá trị mặc định (An toàn)                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| :-------------------------------------- | :------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Bật/Tắt Chung** |                                                                     |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `ad_open_app_enabled`                   | Bật/tắt quảng cáo khi mở ứng dụng.                                   | `true`                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `ad_interstitial_enabled`               | Bật/tắt tất cả quảng cáo xen kẽ.                                     | `true`                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `ad_rewarded_enabled`                   | Cho phép hiển thị rewarded ads.                                     | `true`                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `ad_banner_enabled`                     | Cho phép hiển thị banner ads.                                       | `true`                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **Unit IDs** |                                                                     |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `ad_unit_open_app`                      | Unit ID: Open App                                                   | `""`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ad_unit_interstitial_pre_summary`      | Unit ID: Interstitial - Từ Home sang Summary                        | `""`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ad_unit_interstitial_post_proc`        | Unit ID: Interstitial - Sau xử lý                                   | `""`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ad_unit_interstitial_after_share`      | Unit ID: Interstitial - Sau khi Share                               | `""`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ad_unit_interstitial_settings_exit`    | Unit ID: Interstitial - Từ Settings về Home                         | `""`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ad_unit_interstitial_summary_exit`     | Unit ID: Interstitial - Từ Summary về Home                          | `""`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ad_unit_rewarded`                      | Unit ID: Rewarded                                                   | `""`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ad_unit_banner`                        | Unit ID: Banner                                                     | `""`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **Tần suất & Thời gian** |                                                                     |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `ad_load_timeout_seconds`               | Thời gian chờ tối đa (giây) khi tải quảng cáo.                       | `5`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `ad_open_app_background_threshold_minutes` | Thời gian tối thiểu (phút) app ở nền để hiển thị lại Open Ad.        | `30`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `ad_fullscreen_global_freq_seconds`     | Thời gian tối thiểu (giây) giữa hai quảng cáo toàn màn hình bất kỳ. | `120`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `ad_rewarded_daily_limit`               | Số lần xem quảng cáo nhận thưởng tối đa/ngày. (Nếu là 0, không giới hạn) | `5`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `ad_banner_refresh_rate_seconds`        | **(Tham khảo)** Tần suất làm mới (giây) được đề xuất để cài đặt trên AdMob. | `60`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **Popup Giới thiệu** |                                                                     |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `popup_intro_basic_enabled`             | Bật/tắt hiển thị popup giới thiệu gói Basic.                         | `true`                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `popup_intro_basic_frequency_hours`     | Tần suất (giờ) hiển thị lại popup. (`0` = chỉ 1 lần)                | `0`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `popup_intro_basic_text`                | Nội dung tiếng Anh trong popup.                                       | `"Welcome to the One AI Basic Plan!\nWe're happy to have you here. To get you started, here’s what our free plan includes:\n\n✅ Free Daily Credits: You receive a new set of free credits every day to transcribe and summarize your audio.\n🎧 30-Minute Limit: Each audio file can be up to 30 minutes long.\n💰 Need More? Earn extra credits anytime just by watching a short ad.\n\nTo keep our core features free, our service is supported by advertisements and our Premium members. Your understanding helps us maintain and grow the app.\nIf you'd like to enjoy an enhanced experience and support us further, please consider upgrading."` |

---
## 🪧 POPUP GIỚI THIỆU GÓI BASIC

* **Đối tượng & Điều kiện:**
    * Popup này **CHỈ** được hiển thị cho người dùng **chưa đăng ký Premium**.
    * Hệ thống phải kiểm tra trạng thái Premium của người dùng trước khi quyết định hiển thị popup.
* **Tần suất & Vị trí:** Hiển thị khi người dùng vào màn hình Home. Tần suất được kiểm soát bởi Remote Config (`popup_intro_basic_frequency_hours`).
* **Nội dung:** Lấy từ Remote Config `popup_intro_basic_text`.
* **Giao diện:**
    * Popup với tiêu đề và mô tả.
    * Hai nút: `Cancel` → Đóng popup, `Go Premium` → Điều hướng đến màn hình nâng cấp.


**Note AI: Note Taker**

|  |  |  |  |
| --- | --- | --- | --- |
| AppID | ca-app-pub-8661297299230251~8024150974 | AppID | ca-app-pub-8661297299230251~8068383004 |
| OneAI_iOS_OpenApp_Launch | ca-app-pub-8661297299230251/6876055997 | OneAI_Android_OpenApp_Launch | ca-app-pub-8661297299230251/8395686067 |
| OneAI_iOS_Interstitial_PreSummary | ca-app-pub-8661297299230251/6344237793 | OneAI_Android_Interstitial_PreSummary | ca-app-pub-8661297299230251/7082604391 |
| *~~OneAI_iOS_Interstitial_PostProcessing~~* | *~~ca-app-pub-8661297299230251/5562974327~~* | *~~OneAI_Android_Interstitial_PostProcessing~~* | *~~ca-app-pub-8661297299230251/3837493952~~* |
| OneAI_iOS_Rewarded_GetCredit | ca-app-pub-8661297299230251/2702992796 | OneAI_Android_Rewarded_GetCredit | ca-app-pub-8661297299230251/6067522730 |
| OneAI_iOS_Banner_ContentScreen | ca-app-pub-8661297299230251/7763747780 | OneAI_Android_Banner_ContentScreen | ca-app-pub-8661297299230251/4456441053 |
| OneAI_iOS_Interstitial_AfterShare | ca-app-pub-8661297299230251/4545190529 | OneAI_Android_Interstitial_AfterShare | ca-app-pub-8661297299230251/4675066936 |
| OneAI_iOS_Interstitial_SettingsExit | ca-app-pub-8661297299230251/3232108857 | OneAI_Android_Interstitial_SettingsExit | ca-app-pub-8661297299230251/3375579085 |
| OneAI_iOS_Interstitial_SummaryExit | ca-app-pub-8661297299230251/1919027186 | OneAI_Android_Interstitial_SummaryExit | ca-app-pub-8661297299230251/6834326410 |