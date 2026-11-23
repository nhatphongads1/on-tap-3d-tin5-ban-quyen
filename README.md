# Ôn tập 3D – Tin học (tiểu học)

Trò chơi ôn tập dạng khuôn viên 3D chạy trên trình duyệt: 6 ngôi nhà, mỗi nhà
1–10 câu hỏi theo mức Biết – Hiểu – Vận dụng. Trả lời đúng hết mới được sang
nhà tiếp theo. Có pháo hoa, điểm số, màn hình vinh danh, hướng dẫn cách chơi,
giọng đọc thật (file MP3, giọng vi-VN-HoaiMyNeural) và chim/cún trong khuôn viên.

- Mở bằng Chrome hoặc Edge, cần có Internet.
- Máy tính: W A S D hoặc bấm vào mặt đất; kéo chuột để xoay. Điện thoại: chạm và kéo.
- Bài mặc định: Tin 5 – Bản quyền nội dung thông tin (18 câu). Bài khác mở bằng
  `?bai=<slug>` (vd `?bai=tin4-bai-5-6`, `?bai=tin5-bai-6`).

Làm bởi thầy Phong cùng Claude (AI). Giáo viên duyệt từng câu hỏi trước khi dùng.
Câu hỏi bám theo nội dung bài học, chỉ dùng cho mục đích giảng dạy.

## Tính năng (bản nâng cấp 15/11/2026)

- **Lưu kết quả học sinh:** trước khi chơi, HS điền họ tên + lớp (có nút "Để sau"
  để chơi không lưu). Khi xong từng nhà và khi xong game, kết quả lưu lên
  Supabase (bảng `ket_qua_ontap3d`) qua RPC `luu_ket_qua`. Xem kết quả tại
  trang `/ket-qua.html` (chỉ quản trị): lọc theo bài + lớp, bảng điểm, câu sai
  nhiều nhất, xuất Excel (CSV UTF-8 có BOM). Cần chạy file
  `supabase/migration-ket-qua-giai-thich.sql` 1 lần trong Supabase SQL Editor
  (xem hướng dẫn trong đầu file); nếu chưa chạy, game vẫn chơi bình thường,
  chỉ không lưu được kết quả.
- **Giải thích + ôn câu sai:** sau mỗi câu trả lời đúng, game hiện giải thích
  ngắn; cuối game có màn "Xem lại câu sai" (câu sai + đáp án đúng + giải thích)
  và nút "Làm lại câu sai" để gỡ nửa điểm mỗi câu.
- **4 dạng câu hỏi:** trắc nghiệm (3 lựa chọn), Đúng/Sai, kéo thả sắp xếp thứ tự
  (có nút ▲▼ cho cảm ứng), điền từ (chấp nhận đáp án không dấu). Tất cả đều
  gắn mức Biết/Hiểu/Vận dụng và tính điểm như cũ (10/15/20, sai rồi đúng =
  nửa điểm). Câu hỏi có thể kèm hình (`hinh/...`, bấm vào để phóng to).
- **Bảng nhiệm vụ từng phòng:** tới gần nhà (hoặc bấm vào nhà) hiện bảng nhiệm
  vụ (tên phòng, nhiệm vụ, số câu hỏi); làm xong mới qua phòng sau.
- **Hộp quà may mắn:** xong mỗi phòng, HS chọn 1 trong 3 hộp quà: điểm thưởng
  ngẫu nhiên 1–10 (có thể có 1 hộp trừ 1 điểm); phòng làm tốt thì hộp dễ ra
  điểm cao hơn. Tổng điểm không xuống dưới 0. Điểm hộp quà ghi riêng trong
  kết quả (`diemHopQua`).
- **Nhắc nhở + khen:** sai 3 lần liên tiếp trong 1 phòng → "Kiến thức của em
  chưa tốt, cần đọc bài thêm nhé!"; đúng 3 câu liên tiếp → "Xuất sắc, em nắm
  kiến thức rất tốt!" + pháo hoa. (Lưu ý: với câu trắc nghiệm/Đúng-Sai, đáp án
  sai bị khóa sau khi chọn nên chuỗi sai 3 lần chỉ xảy ra ở câu sắp xếp/điền từ.)
- **Giọng đọc thật (Edge-TTS):** file MP3 trong `audio/<slug>/` (giọng
  vi-VN-HoaiMyNeural), sinh bằng `audio/sinh-am-thanh.py`. App ưu tiên phát
  MP3, thiếu file thì dùng giọng Web Speech, thiếu cả giọng Việt thì hiện ghi
  chú rõ ràng (nút đọc không tự biến mất).
- **Hình ảnh v2:** nhảy dù mở màn (có nút Bỏ qua), bảng tên từng nhà trong 3D,
  thú cưng đi theo, 4 chim bay lượn + 3 cún con đi dạo (bấm vào cún thì cún
  nhảy vui + sủa bằng âm thanh tổng hợp), chủ đề Tết (đèn lồng, mai đào) và
  Halloween (bí ngô, dơi) chọn từ nút Mùa. Nút "Thú cưng & chim" bật/tắt chung.
- **Mobile + máy yếu:** nút bấm ≥ 44px trên màn hình nhỏ; chế độ "Máy yếu" tự
  hạ chất lượng 3D (giảm pixelRatio, tắt bóng, ẩn chim/cún, giảm pháo hoa) khi
  FPS thấp; tôn trọng `prefers-reduced-motion` (tắt pháo hoa/nhảy dù/chim/cún).

## Trang soạn câu hỏi

`/admin` cho phép sửa 6 nhà × 1–10 câu (Biết – Hiểu – Vận dụng, đủ 4 dạng câu
hỏi, kèm giải thích + hình ảnh + chỉ dẫn tới nhà kế tiếp), kiểm tra đủ nội dung,
chơi thử bản nháp rồi lưu lên Supabase. Chỉ tài khoản có email trong bảng
`quan_tri` mới lưu được. Trang `/admin` không lưu gì trên máy chủ ngoài
Supabase; bản nháp chỉ lưu trên trình duyệt của người soạn.

## Dữ liệu trên Supabase

Nội dung bài lưu trong Supabase; trò chơi đọc qua hàm `lay_bai` bằng khoá công
khai, nếu lỗi thì dùng `cau-hoi.js`. Chỉ tài khoản có email trong bảng
`quan_tri` mới lưu được (qua `/admin` hoặc RPC `luu_bai`). Cấu trúc bảng và
quyền gốc: `supabase/schema.sql` (bản cũ: 3 câu/nhà); các thay đổi mới nhất
(kết quả HS, giải thích, 4 dạng câu hỏi, hình ảnh, 1–10 câu/nhà): chạy
`supabase/migration-ket-qua-giai-thich.sql`. Không có khoá bí mật nào nằm trong
kho này.

## Nâng cấp 23/11/2026 — Khu học tập (theo mô hình "Thế giới thứ 2")

- **Khu học tập:** nhà chờ 3D ở phía đông khuôn viên (gần văn phòng), có màn
  hình lớn. Bấm vào nhà / nhãn "Khu học tập" / mục "Khu học tập" trong menu
  "Vào nhà ▾" để mở panel xem video bài học ngay trong game. Video lấy từ
  trường mới `videoHoc` + `videoHocTieuDe` trong dữ liệu bài (gắn qua
  `/admin`, mục "Bài ôn tập"); nếu bài chưa có video chung, panel liệt kê
  video của từng nhà; nếu không có video nào thì hiện ghi chú. Không cần
  đổi RPC — trường mới ở cấp bài, tương thích dữ liệu cũ.
- **Bản đồ nhỏ:** thêm marker tím (chấm + tam giác play) cho Khu học tập.
- **Nhãn tên:** nút "Để sau" ở form vào chơi giờ cũng tạo nhãn tên trên đầu
  nhân vật (trước đây chỉ có khi gõ tên rồi bấm "Vào chơi").
- **Mùa Tuyết:** thêm vòng nguyệt quế Giáng sinh ở cửa văn phòng, màn hình
  Khu học tập và cửa 6 nhà (hiện cùng cây thông + người tuyết khi bật
  Mùa: Tuyết).

## Nội dung bài mới (chưa nạp — chờ duyệt)

- Tin 5 Bài 6 "Định dạng kí tự và bố trí hình ảnh trong văn bản"
  (`noi-dung/tin5-bai-6.json`, 30 câu: 10 Biết / 10 Hiểu / 10 Vận dụng, trộn
  4 dạng; nguồn từng câu: `noi-dung/tin5-bai-6-nguon.txt`; hình cắt từ SGK:
  `hinh/bai6/`). Chơi thử bản nháp: nạp JSON vào localStorage `ontap3d_nhap`
  rồi mở `?thu=1`.
- Giải thích cho 2 bài cũ: `noi-dung/tin5-ban-quyen-giai-thich.json` (18 câu),
  `noi-dung/tin4-bai-5-6-giai-thich.json` (30 câu) — nạp lại qua `/admin` sau
  khi chạy migration.
