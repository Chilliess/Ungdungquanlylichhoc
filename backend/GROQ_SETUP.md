# Trợ lý tư vấn bằng Groq Free Plan

Trợ lý và chức năng nhập ảnh/PDF thời khóa biểu đều dùng Groq. Dù model ID
`openai/gpt-oss-120b` có chữ `openai`, key cần tạo trên Groq, không phải OpenAI.
Không cần credit OpenAI/Gemini. File SQL chính vẫn là
`../supabase_database.sql`; thay nhà cung cấp không thay schema hay quota 30
lượt/người/ngày.

## 1. Kiểm tra tài khoản miễn phí trước

1. Đăng ký/đăng nhập https://console.groq.com/.
2. Kiểm tra tài khoản ở Free Plan; chưa nâng cấp Developer nếu muốn thử miễn phí.
3. Vào API Keys: https://console.groq.com/keys, chọn Create API Key, đặt tên và
   sao chép key. Không gửi key vào chat hay lưu trong Flutter/SQL/Git.
4. Mở Limits của tài khoản để kiểm tra model `openai/gpt-oss-120b` có quyền dùng.
   Hạn mức thực tế phụ thuộc model và tổ chức; xem Limits trong tài khoản thay
   vì dựa vào một con số cố định trong tài liệu dự án.
5. Từ terminal tại thư mục gốc, chạy trước khi đặt key lên Supabase:

```powershell
.\backend\check-groq.ps1 -FromClipboard
```

Chờ lời nhắc, sang Groq sao chép key đầy đủ, quay lại terminal và chỉ nhấn Enter,
không dán key vào ô lời nhắc. Công cụ không in/lưu key. Nó gửi một câu thử ngắn,
tốn một lượt Groq, không trừ quota app. HTTP 200 chỉ xác nhận yêu cầu trực tiếp
được chấp nhận từ máy này, chưa chứng minh cấu hình Supabase hoặc chất lượng câu trả lời.
Nếu bị từ chối, gửi HTTP và thông báo đã che key; chưa cấu hình tiếp Supabase.
Nếu bạn dán key trực tiếp vào ô ẩn ở chế độ FromClipboard, công cụ cũng nhận
giá trị đó. Nếu ô ẩn chỉ nhận một ký tự thì dùng clipboard. Công cụ phát hiện
trường hợp copy nhầm dòng lệnh và báo riêng lỗi khoảng trắng bên trong key;
không tự xóa khoảng trắng để biến một nội dung không phải key thành yêu cầu API.

## 2. Secrets và triển khai

Supabase Dashboard → đúng project của app → Edge Functions → Secrets:

| Name | Value |
| --- | --- |
| GROQ_API_KEY | Key từ Groq |
| GROQ_MODEL | openai/gpt-oss-120b |
| GROQ_VISION_MODEL | qwen/qwen3.8-27b (tùy chọn; mặc định dùng giá trị này) |

Có thể đổi model thành `openai/gpt-oss-20b` nếu tài khoản cho dùng; backend giới
hạn vào hai model GPT-OSS này cho câu trả lời văn bản. Vision cần model Groq có
hỗ trợ ảnh; kiểm tra quyền và hạn mức của model trong tài khoản. Tra cứu web đã
bị bỏ. Các secret Gemini/OpenAI cũ không còn được các chức năng AI đọc; thu hồi
key từng bị lộ.

Mở Edge Functions → study-assistant → Code, thay toàn bộ index.ts bằng file
`functions/study-assistant/index.ts` rồi Deploy. Cấu hình gateway của dự án dùng
Verify JWT tắt; trong mã vẫn bắt buộc Bearer token, auth.getUser() và account_is_active().

Hoặc với Node.js đã cài, từ thư mục gốc:

```powershell
npx supabase login
.\backend\deploy.ps1 -ProjectRef MA_PROJECT_CUA_BAN -Functions study-assistant,import-timetable
```

Thay MA_PROJECT_CUA_BAN bằng project ref trong URL Dashboard. Rebuild/chạy lại
Flutter để thông báo đồng ý ghi đúng Groq, đọc thông báo trước khi gửi dữ liệu.
`import-timetable` dùng cùng key và model vision; PDF được kết xuất trên thiết bị
thành tối đa 15 ảnh, gửi tối đa 3 ảnh mỗi yêu cầu Groq.

## 3. Tư vấn và thu thập thông tin

Tư vấn thông thường không bật công cụ ngoài, dùng model trong hạn mức Free Plan.
Trợ lý được chỉ dẫn hỏi khi thiếu dữ kiện, phân biệt suy luận/đề xuất, không bịa
nguồn hoặc quy định và không bảo đảm trả lời chính xác tuyệt đối. Khi người dùng
bật "Lịch của tôi" và hỏi về lịch, Edge Function chỉ đọc các mục liên quan thuộc
tài khoản đã xác thực qua RLS rồi gửi phần đó cho Groq. AI chỉ chuẩn bị đề xuất tạo/xóa lịch; người dùng phải bấm Áp dụng, rồi RPC
kiểm tra quyền sở hữu trước khi ghi dữ liệu. Lịch lặp được kiểm tra theo ngày diễn ra thực tế; ngữ cảnh gồm
buổi tiếp theo trong 90 ngày tới và lịch thi sắp tới trong cùng khoảng thời gian.
Người dùng có thể tắt tùy chọn này bất cứ lúc nào.

Tra cứu web đã được bỏ khỏi giao diện. Backend cũng chặn yêu cầu tra cứu từ
bản app cũ, kể cả khi secret `GROQ_ENABLE_SEARCH` trước đây vẫn còn. Chat không
kết nối Exa hay công cụ browser search. AI vẫn tư vấn và thao tác lịch theo yêu
cầu, nhận ảnh và đọc dữ liệu cá nhân khi người dùng bật Lịch cá nhân.

## 4. Xử lý lỗi

### Thao tác lịch và ảnh trong chat

Trợ lý nhận danh sách tối đa 50 môn trong tài khoản (bao gồm môn chưa có buổi
học), các lần học/thi thuộc ngày hoặc tuần đang hỏi, và tối đa 30 lần diễn ra
kế tiếp trong 90 ngày. Mỗi phần có phạm vi và cờ bị giới hạn riêng; không được
kết luận ngày trống từ danh sách lần học kế tiếp. Lịch lặp được mở thành lần
diễn ra thực tế trong khoảng đang hỏi. Không truy cập dữ liệu này khi tắt
**Lịch cá nhân**.

Với chat dài, ngoài các lượt gần nhất, app gửi bổ sung lời nhắn cũ của chính
người dùng (tối đa 40 mục / 8.000 ký tự JSON), không lấy câu trả lời cũ của AI
làm dữ kiện. Đây vẫn là ngữ cảnh có giới hạn, không phải bộ nhớ vô hạn. Lịch sử giữa
thiết bị được đồng bộ riêng qua Supabase theo WORKSPACE_SYNC.md. Yêu cầu mới nhất được ưu tiên khi thay đổi kế hoạch.

Khi được nhờ lập kế hoạch, AI được hướng dẫn đề xuất môn có thật và cách chia
giờ, ghi rõ giả định để người dùng kiểm tra, không hỏi lại dữ kiện đã có.
Giờ 24:00 và buổi qua nửa đêm hiện chưa được lưu; có thể đề xuất kết thúc phiên
học lúc 23:45 và dành 15 phút cuối nghỉ, nhưng phải nói rõ cách phân bổ này.

Chat có thể đọc lịch của tài khoản khi bật **Lịch của tôi**. Khi yêu cầu tạo/xóa,
AI trả danh sách đề xuất; người dùng kiểm tra và bấm **Áp dụng** từng mục.
Xóa lịch lặp sẽ ghi rõ là xóa toàn bộ chuỗi. Tạo mới hiện là từng buổi cụ thể,
tối đa 20 mục/lần; thiếu ngày, giờ hoặc phòng thì trợ lý phải hỏi lại.

Ảnh PNG/JPEG/WebP tối đa 3 MB: chọn từ nút ảnh hoặc dán Ctrl+V trên trình duyệt.
Ảnh chỉ gửi trong lượt hiện tại, không ghi vào lịch sử chat; không bật tra cứu
web cùng lượt ảnh. Dán ảnh clipboard hiện dành cho web; ứng dụng native chọn
ảnh từ bộ chọn tệp. Vision dùng `GROQ_VISION_MODEL`, mặc định `qwen/qwen3.8-27b`;
tài khoản Groq cần có quyền/hạn mức model này. Tham khảo
[Groq Vision](https://console.groq.com/docs/vision).

Nhập thời khóa biểu nhận PNG/JPEG hoặc PDF tối đa 5 MB và 15 trang. PDF được
kết xuất thành JPEG trên thiết bị trước khi gửi; các trang được chia thành
các yêu cầu Groq, tối đa 3 ảnh mỗi yêu cầu. Mỗi tệp nhập tiêu thụ một lượt
quota của ứng dụng; Groq có hạn mức riêng. Hàm `import-timetable` dùng cùng
`GROQ_API_KEY` và `GROQ_VISION_MODEL`, không cần secret OpenAI. Mỗi tệp trả tối
đa 50 buổi để người dùng kiểm tra trước khi lưu.

Áp dụng khối **AI_CALENDAR_ACTIONS** ở cuối `supabase_database.sql` rồi deploy
`study-assistant` và Flutter Web. RPC mới chạy theo quyền tài khoản (RLS),
ghi biên nhận cùng giao dịch để thử lại không tạo/xóa trùng. Không dùng service
role để ghi lịch. Kiểm tra DB bằng `backend/tests/assistant_calendar_db_test.ps1`
(tạo dữ liệu giả và luôn ROLLBACK).

Lựa chọn "Đồng ý và bắt đầu" được lưu theo tài khoản trong Supabase Auth
user metadata (`study_assistant_consent_version`, `study_assistant_consent_at`),
kèm bản lưu cục bộ theo user ID. Tải lại trang hoặc đăng nhập trên trình duyệt
khác sẽ đọc lại lựa chọn từ tài khoản. Chấp thuận đã lưu cục bộ từ bản cũ được
đồng bộ khi có mạng. Đây chỉ là tùy chọn người dùng, không dùng để cấp quyền RLS.
Thay đổi này không cần sửa SQL hay triển khai Edge Function; cần build và cập
nhật bản Flutter Web lên Cloudflare. Xóa dữ liệu trình duyệt trước khi bản cũ
được đồng bộ có thể khiến tài khoản phải xác nhận thêm một lần.

| Thông báo | Cần kiểm tra |
| --- | --- |
| Assistant not configured | Hai secrets, tên model và project Supabase |
| Groq key rejected | Key bị thu hồi, sai hoặc tài khoản chưa được cấp quyền |
| Groq model unavailable | Tên model và quyền của tổ chức |
| Groq rate limit reached | Limits, độ dài hội thoại, chờ theo hạn mức; không gửi liên tục |
| Groq request rejected | Định dạng, tham số, model và quyền API của tài khoản |
| Web search unavailable | Bản cũ yêu cầu tra cứu web; cập nhật app, chức năng này đã bị bỏ |
| Daily limit reached | 30 lượt/ngày của app, đổi ngày lúc 07:00 Việt Nam |
| Groq response unavailable | Nội dung bị chặn hoặc bị cắt; thử câu hỏi ngắn hơn |

Logs có `groq_request_failed` và provider_http_status. Không log key, dữ liệu
hội thoại hay phản hồi lỗi thô từ nhà cung cấp. Quota app được lấy trước khi gọi
Groq; lỗi nhà cung cấp vẫn tính lượt. Cần bảng assistant_daily_usage và các RPC
consume_assistant_request/account_is_active trong SQL chính.

## Kiểm thử cục bộ

Chatbox lưu hội thoại theo tài khoản và đồng bộ qua Supabase, có bản lưu trên thiết bị. Mỗi lần gửi,
app chọn các lượt trao đổi gần nhất (tối đa 12 tin, nằm trong giới hạn JSON của
máy chủ), bắt đầu từ câu hỏi của người dùng. Hội thoại quá dài không được gửi
toàn bộ; hãy nhắc lại chi tiết quan trọng nếu AI cần. Có thể tìm lịch sử theo
tiêu đề hoặc nội dung, mở lại để hỏi tiếp và sao chép câu trả lời. Cờ tra cứu web trong lịch sử cũ không còn được sử dụng.

Sau khi cập nhật chỉ dẫn trả lời trong `functions/study-assistant/index.ts`,
triển khai lại hàm `study-assistant` bằng hướng dẫn triển khai của backend.
Tra cứu web đã bị chặn trong mã; không cần đặt GROQ_ENABLE_SEARCH hoặc key Exa.

```powershell
node --test backend/tests/study_assistant_groq.test.mjs backend/tests/import_timetable_groq.test.mjs
.\backend\tests\check_groq_parser_test.ps1
flutter test test/assistant_overlay_test.dart test/services/assistant_error_test.dart
```

Các kiểm thử trên dùng dữ liệu giả, không gọi Groq thật. Kiểm tra trực tiếp ở
mục 1 cần key của người vận hành; không gửi key vào log hoặc Git.

Tài liệu chính thức:
- https://console.groq.com/docs/models
- https://console.groq.com/docs/rate-limits
- https://console.groq.com/docs/your-data
