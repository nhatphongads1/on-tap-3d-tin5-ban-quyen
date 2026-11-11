
-- ===== ONTAP3D: bảng dữ liệu bài ôn tập =====
create table if not exists public.bai (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,60}$'),
  ten_tro_choi text not null,
  phu_de text not null,
  phong_giua text not null default 'Phòng trung tâm',
  xuat_ban boolean not null default true,
  cap_nhat timestamptz not null default now()
);
create table if not exists public.nha (
  id uuid primary key default gen_random_uuid(),
  bai_id uuid not null references public.bai(id) on delete cascade,
  thu_tu int not null check (thu_tu between 1 and 6),
  ten text not null,
  mau text not null default '#1f6fe0' check (mau ~ '^#[0-9a-fA-F]{6}$'),
  goc int not null default 0,
  thong_tin text,
  video_url text check (video_url is null or video_url ~* '^https://'),
  video_tieu_de text,
  unique (bai_id, thu_tu)
);
create table if not exists public.cau_hoi (
  id uuid primary key default gen_random_uuid(),
  nha_id uuid not null references public.nha(id) on delete cascade,
  thu_tu int not null check (thu_tu between 1 and 3),
  muc text not null check (muc in ('BIẾT','HIỂU','VẬN DỤNG')),
  hoi text not null,
  chon jsonb not null check (jsonb_typeof(chon) = 'array' and jsonb_array_length(chon) = 3),
  dung int not null check (dung between 0 and 2),
  goi_y text,
  video_url text check (video_url is null or video_url ~* '^https://'),
  video_tieu_de text,
  unique (nha_id, thu_tu)
);
create table if not exists public.quan_tri (email text primary key);

alter table public.bai enable row level security;
alter table public.nha enable row level security;
alter table public.cau_hoi enable row level security;
alter table public.quan_tri enable row level security;

create or replace function public.la_quan_tri() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.quan_tri where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
revoke all on function public.la_quan_tri() from public;
grant execute on function public.la_quan_tri() to anon, authenticated;

drop policy if exists bai_doc on public.bai;
create policy bai_doc on public.bai for select to anon, authenticated using (xuat_ban or public.la_quan_tri());
drop policy if exists nha_doc on public.nha;
create policy nha_doc on public.nha for select to anon, authenticated
  using (exists (select 1 from public.bai b where b.id = nha.bai_id and (b.xuat_ban or public.la_quan_tri())));
drop policy if exists cau_doc on public.cau_hoi;
create policy cau_doc on public.cau_hoi for select to anon, authenticated
  using (exists (select 1 from public.nha n join public.bai b on b.id = n.bai_id where n.id = cau_hoi.nha_id and (b.xuat_ban or public.la_quan_tri())));

revoke all on public.bai, public.nha, public.cau_hoi, public.quan_tri from anon, authenticated;
grant select on public.bai, public.nha, public.cau_hoi to anon, authenticated;

-- Lấy một bài (dạng JSON cho trò chơi và trang admin)
create or replace function public.lay_bai(p_slug text) returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'slug', b.slug, 'xuatBan', b.xuat_ban,
    'tenTroChoi', b.ten_tro_choi, 'phuDe', b.phu_de, 'phongGiua', b.phong_giua,
    'nha', coalesce((select jsonb_agg(jsonb_build_object(
        'ten', n.ten, 'mau', n.mau, 'goc', n.goc,
        'thongTin', n.thong_tin, 'videoUrl', n.video_url, 'videoTieuDe', n.video_tieu_de,
        'cau', coalesce((select jsonb_agg(jsonb_build_object(
            'muc', c.muc, 'hoi', c.hoi, 'chon', c.chon, 'dung', c.dung, 'goiy', c.goi_y,
            'videoUrl', c.video_url, 'videoTieuDe', c.video_tieu_de) order by c.thu_tu)
          from public.cau_hoi c where c.nha_id = n.id), '[]'::jsonb)
      ) order by n.thu_tu) from public.nha n where n.bai_id = b.id), '[]'::jsonb))
  from public.bai b where b.slug = p_slug and (b.xuat_ban or public.la_quan_tri());
$$;
grant execute on function public.lay_bai(text) to anon, authenticated;

-- Danh sách bài (cho admin)
create or replace function public.danh_sach_bai() returns jsonb
language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'ten', ten_tro_choi, 'phuDe', phu_de, 'xuatBan', xuat_ban) order by cap_nhat desc), '[]'::jsonb)
  from public.bai where xuat_ban or public.la_quan_tri();
$$;
grant execute on function public.danh_sach_bai() to anon, authenticated;

-- Lưu cả bài một lần (chỉ quản trị): thay toàn bộ 6 nhà x 3 câu
create or replace function public.luu_bai(p_slug text, p_data jsonb, p_xuat_ban boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_bai uuid; v_nha uuid; n jsonb; c jsonb; i int; j int;
begin
  if not public.la_quan_tri() then raise exception 'Không có quyền quản trị'; end if;
  if jsonb_typeof(p_data -> 'nha') <> 'array' or jsonb_array_length(p_data -> 'nha') <> 6 then raise exception 'Cần đúng 6 nhà'; end if;
  insert into public.bai (slug, ten_tro_choi, phu_de, phong_giua, xuat_ban, cap_nhat)
  values (p_slug, p_data ->> 'tenTroChoi', p_data ->> 'phuDe', coalesce(nullif(p_data ->> 'phongGiua', ''), 'Phòng trung tâm'), p_xuat_ban, now())
  on conflict (slug) do update set ten_tro_choi = excluded.ten_tro_choi, phu_de = excluded.phu_de,
    phong_giua = excluded.phong_giua, xuat_ban = excluded.xuat_ban, cap_nhat = now()
  returning id into v_bai;
  delete from public.nha where bai_id = v_bai;
  for i in 0..5 loop
    n := (p_data -> 'nha') -> i;
    if jsonb_typeof(n -> 'cau') <> 'array' or jsonb_array_length(n -> 'cau') <> 3 then raise exception 'Nhà % cần đúng 3 câu', i + 1; end if;
    insert into public.nha (bai_id, thu_tu, ten, mau, goc, thong_tin, video_url, video_tieu_de)
    values (v_bai, i + 1, n ->> 'ten', coalesce(nullif(n ->> 'mau', ''), '#1f6fe0'), coalesce((n ->> 'goc')::int, 0),
            nullif(n ->> 'thongTin', ''), nullif(n ->> 'videoUrl', ''), nullif(n ->> 'videoTieuDe', ''))
    returning id into v_nha;
    for j in 0..2 loop
      c := (n -> 'cau') -> j;
      insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y, video_url, video_tieu_de)
      values (v_nha, j + 1, (array['BIẾT','HIỂU','VẬN DỤNG'])[j + 1], c ->> 'hoi', c -> 'chon', (c ->> 'dung')::int,
              nullif(c ->> 'goiy', ''), nullif(c ->> 'videoUrl', ''), nullif(c ->> 'videoTieuDe', ''));
    end loop;
  end loop;
  return public.lay_bai(p_slug);
end $$;
revoke all on function public.luu_bai(text, jsonb, boolean) from public, anon;
grant execute on function public.luu_bai(text, jsonb, boolean) to authenticated;

-- ===== NẠP BÀI ĐẦU TIÊN (18 câu Tin 5 - Bản quyền) =====
do $$ declare v_bai uuid; v_nha uuid; begin
insert into public.bai (slug, ten_tro_choi, phu_de, phong_giua, xuat_ban) values ('tin5-ban-quyen', 'Ôn tập Tin 5', 'Bản quyền nội dung thông tin', 'Phòng Tin học', true) on conflict (slug) do nothing returning id into v_bai;
if v_bai is not null then
insert into public.nha (bai_id, thu_tu, ten, mau, goc) values (v_bai, 1, 'Tác giả', '#c4553b', 10) returning id into v_nha;
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 1, 'BIẾT', 'Bài thơ trong Hình 24 (SGK trang 24) là của tác giả nào?', '["Ngô Hà Trang", "Xuân Quỳnh", "Em tự viết ra"]'::jsonb, 1, 'Nhớ lại Hình 24 trong SGK trang 24.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 2, 'HIỂU', 'Vì sao phải ghi rõ tên tác giả khi dùng nội dung của họ?', '["Để bài của em dài hơn", "Để thầy cô không kiểm tra", "Vì tác giả có quyền cho phép hoặc không cho phép người khác dùng nội dung đó"]'::jsonb, 2, 'Nghĩ xem ai có quyền quyết định cho dùng nội dung.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 3, 'VẬN DỤNG', 'Em dùng một bài thơ của một nhà thơ để làm bài trình chiếu. Em nên làm gì?', '["Ghi rõ tên tác giả của bài thơ", "Xoá tên tác giả cho gọn", "Ghi tên em là tác giả"]'::jsonb, 0, 'Hãy tôn trọng người đã tạo ra bài thơ.');
insert into public.nha (bai_id, thu_tu, ten, mau, goc) values (v_bai, 2, 'Bản quyền', '#2f7a5b', 65) returning id into v_nha;
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 1, 'BIẾT', 'Bản quyền nội dung thông tin là gì?', '["Quyền sao chép bất cứ nội dung nào", "Quyền tải nội dung từ Internet", "Quyền của tác giả cho phép hoặc không cho phép người khác sử dụng nội dung"]'::jsonb, 2, 'Hãy nghĩ đến quyền của tác giả.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 2, 'HIỂU', 'Quyền tác giả là gì?', '["Quyền được công nhận là tác giả của nội dung", "Quyền chỉnh sửa nội dung của người khác", "Quyền xoá nội dung của người khác"]'::jsonb, 0, 'Nghĩ đến việc được ghi tên là người tạo ra nội dung.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 3, 'VẬN DỤNG', 'Một bạn nói: "Ảnh trên mạng cứ tải về dùng, không cần xin phép." Em thấy thế nào?', '["Đúng, vì ảnh trên mạng ai cũng dùng được", "Chưa đúng, vì ảnh có tác giả và tác giả có quyền cho phép hay không", "Đúng, vì tải về là thành của mình"]'::jsonb, 1, 'Ảnh trên mạng cũng có người tạo ra nó.');
insert into public.nha (bai_id, thu_tu, ten, mau, goc) values (v_bai, 3, 'Dạng nội dung', '#8a63c9', 120) returning id into v_nha;
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 1, 'BIẾT', 'Nội dung thông tin có thể được thể hiện dưới dạng nào?', '["Chỉ có dạng văn bản", "Văn bản, hình ảnh, âm thanh hay đa phương tiện", "Chỉ có dạng âm thanh"]'::jsonb, 1, 'Nội dung thông tin có nhiều dạng khác nhau.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 2, 'HIỂU', 'Một nội dung thông tin có bắt buộc phải gồm đủ văn bản, hình ảnh và âm thanh không?', '["Có, bắt buộc phải có đủ cả ba dạng", "Có, nhưng chỉ khi đăng lên mạng", "Không bắt buộc gồm tất cả các dạng"]'::jsonb, 2, 'Hãy nghĩ đến một bài hát chỉ có âm thanh.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 3, 'VẬN DỤNG', 'Nội dung thông tin trong tệp Em-yeu-truong-em.mp3 được thể hiện dưới dạng gì?', '["Âm thanh", "Hình ảnh", "Văn bản"]'::jsonb, 0, 'Đuôi .mp3 thường là tệp gì?');
insert into public.nha (bai_id, thu_tu, ten, mau, goc) values (v_bai, 4, 'Ghi nguồn', '#d79a2b', 175) returning id into v_nha;
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 1, 'BIẾT', 'Khi dùng thông tin từ website hoahoctro.tienphong.vn, em ghi nguồn như thế nào?', '["Nguồn: hoahoctro.tienphong.vn", "Nguồn: Internet", "Không cần ghi"]'::jsonb, 0, 'Nên ghi đúng địa chỉ trang web em lấy thông tin.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 2, 'HIỂU', 'Khi dùng một bài hát không rõ tên tác giả, em ghi nguồn như thế nào?', '["Không ghi nguồn", "Sưu tầm", "Ghi tên em là tác giả"]'::jsonb, 1, 'Em không biết tác giả nhưng không được nhận là của mình.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 3, 'VẬN DỤNG', 'Trong bài trình chiếu, các bạn dùng thông tin từ website thieunien.vn. Các bạn cần làm gì để tôn trọng bản quyền?', '["Xoá tên website cho slide gọn", "Nói là do mình tự viết", "Ghi rõ \"Nguồn: thieunien.vn\" trên slide"]'::jsonb, 2, 'Hãy nghĩ đến người đã đăng thông tin đó.');
insert into public.nha (bai_id, thu_tu, ten, mau, goc) values (v_bai, 5, 'Tôn trọng riêng tư', '#2f6fa0', 235) returning id into v_nha;
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 1, 'BIẾT', 'Sao chép tệp của bạn mà chưa được sự đồng ý có hợp lệ không?', '["Hợp lệ, vì cùng một lớp", "Không hợp lệ", "Hợp lệ nếu bạn không biết"]'::jsonb, 1, 'Tệp của bạn là của riêng bạn.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 2, 'HIỂU', 'Đọc tin nhắn trên điện thoại của người khác khi chưa được phép: vì sao em không đồng tình?', '["Vì điện thoại sẽ hết pin", "Vì tin nhắn quá dài", "Vì đó là xâm phạm quyền riêng tư của người khác"]'::jsonb, 2, 'Tin nhắn là chuyện riêng của người khác.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 3, 'VẬN DỤNG', 'Em thấy một bạn chia sẻ thông tin riêng tư của người khác khi chưa xin phép. Em nên làm gì?', '["Góp ý, nhắc nhở và nói rõ em không đồng tình", "Cùng chia sẻ cho vui", "Im lặng, coi như không biết"]'::jsonb, 0, 'Em cần thể hiện thái độ không đồng tình một cách lịch sự.');
insert into public.nha (bai_id, thu_tu, ten, mau, goc) values (v_bai, 6, 'Riêng tư với AI', '#c4553b', 280) returning id into v_nha;
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 1, 'BIẾT', 'Khi dùng các công cụ trực tuyến và AI, thông tin cá nhân của em có nguy cơ gì?', '["Có nguy cơ bị lộ", "Luôn được giữ bí mật tuyệt đối", "Tự động biến mất"]'::jsonb, 0, 'Thông tin đưa lên mạng có thể đến tay người khác.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 2, 'HIỂU', 'Vì sao cần bảo vệ ảnh khuôn mặt và họ tên thật khi dùng AI?', '["Vì máy tính sẽ chạy chậm", "Vì thông tin có thể bị lộ khi đưa lên công cụ trực tuyến", "Vì AI không biết đọc chữ"]'::jsonb, 1, 'Nghĩ xem thông tin đã đưa lên mạng còn giữ riêng được không.');
insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y) values (v_nha, 3, 'VẬN DỤNG', 'Một ứng dụng AI yêu cầu tải ảnh khuôn mặt và họ tên thật để tạo Avatar miễn phí. Em nên làm gì?', '["Tải ảnh khuôn mặt và nhập họ tên thật", "Gửi link cho nhiều bạn cùng dùng", "Từ chối, không đưa ảnh và họ tên thật"]'::jsonb, 2, 'Ảnh khuôn mặt và họ tên thật là thông tin riêng của em.');
end if; end $$;
