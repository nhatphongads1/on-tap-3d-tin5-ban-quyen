# Ôn tập 3D – Tin học 5: Bản quyền nội dung thông tin

Trò chơi ôn tập dạng khuôn viên 3D chạy trên trình duyệt: 6 ngôi nhà, mỗi nhà 3 câu hỏi theo mức Biết – Hiểu – Vận dụng (18 câu). Trả lời đúng hết mới được sang nhà tiếp theo. Có pháo hoa, điểm số, màn hình vinh danh, hướng dẫn cách chơi và hỗ trợ giọng đọc tiếng Việt (tuỳ thiết bị).

- Mở bằng Chrome hoặc Edge, cần có Internet.
- Máy tính: W A S D hoặc bấm vào mặt đất; kéo chuột để xoay. Điện thoại: chạm và kéo.
- Không đăng nhập, không thu thập thông tin học sinh; điểm không được lưu.

Làm bởi thầy Phong cùng Claude (AI). Giáo viên duyệt từng câu hỏi trước khi dùng. Câu hỏi bám theo nội dung bài học, chỉ dùng cho mục đích giảng dạy.

## Trang soạn câu hỏi

`/admin` cho phép sửa 6 nhà × 3 câu (Biết – Hiểu – Vận dụng), kiểm tra đủ nội dung, chơi thử bản nháp rồi tải tệp `cau-hoi.js`. Thay tệp `cau-hoi.js` trong kho này, trang chơi tự cập nhật. Trang `/admin` không có mật khẩu và không lưu gì trên máy chủ; bản nháp chỉ lưu trên trình duyệt của người soạn.

## Dữ liệu trên Supabase

Nội dung bài (6 nhà × 3 câu, thông tin, link video) lưu trong Supabase; trò chơi đọc qua hàm `lay_bai` bằng khoá công khai, nếu lỗi thì dùng `cau-hoi.js`. Chỉ tài khoản có email trong bảng `quan_tri` mới lưu được (qua `/admin`). Cấu trúc bảng và quyền: `supabase/schema.sql`. Không có khoá bí mật nào nằm trong kho này.
