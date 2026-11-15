-- ============================================================
-- ONTAP3D — MIGRATION: LƯU KẾT QUẢ HỌC SINH + GIẢI THÍCH
-- File: migration-ket-qua-giai-thich.sql
-- ============================================================
-- CÁCH DÙNG (thầy chỉ làm 1 lần):
--   1. Mở Supabase Dashboard → SQL Editor → New query.
--   2. Dán TOÀN BỘ file này vào rồi bấm Run.
--   3. Chạy xong: game lưu được điểm, trang /ket-qua.html xem được kết quả.
-- File này chạy được nhiều lần (idempotent): chạy lại lần 2 không lỗi,
-- không mất dữ liệu cũ.
--
-- NỘI DUNG:
--   (a) Bảng ket_qua_ontap3d — lưu 1 dòng cho mỗi lượt chơi hoàn thành
--       (và 1 dòng cho mỗi nhà, nếu game gửi), kèm điểm hộp quà may mắn.
--   (b) RLS — học sinh (anon) chỉ được GỬI, không được XEM; chỉ quản trị
--       mới xem được.
--   (c) RPC luu_ket_qua — game gọi để lưu 1 lượt chơi (kèm diem_hop_qua).
--   (d) RPC xem_ket_qua — trang /ket-qua.html gọi để xem kết quả + thống kê.
--   (e) Thêm cột giai_thich (câu hỏi) và chi_dan (nhà).
--   (f) Thêm cột hinh_anh, loai, dap_an (câu hỏi) — hỗ trợ 4 dạng câu
--       hỏi (choice, truefalse, reorder, fillblank) + hình ảnh trong câu.
--   (g) Nới ràng buộc cũ của chon (đúng 3 → 2–4 phần tử, cho phép NULL)
--       và dung (bỏ NOT NULL, 0–2, cho phép NULL) + check nhất quán
--       theo dạng (cau_hoi_loai_check). Chạy lại không lỗi.
--   (h) Cập nhật lay_bai — trả thêm loai + dapAn + hinhAnh cho mỗi câu
--       (cùng giaiThich + chiDan), giữ nguyên mọi trường cũ, vẫn hỗ
--       trợ 1–10 câu/nhà như DB live hiện tại.
--   (i) Cập nhật luu_bai — 6 nhà, mỗi nhà 1–10 câu, mức độ lấy từ JSON,
--       lưu chiDan + giaiThich + thongTin + video + loai/dapAn/hinhAnh,
--       validate theo từng dạng câu hỏi, vẫn chỉ quản trị.
--   (j) Nới ràng buộc cau_hoi.thu_tu từ 1..3 lên 1..10 (an toàn, chạy
--       lại không lỗi, DB nào đã nới rồi thì bỏ qua).
-- ============================================================

-- ---------- (a) Bảng lưu kết quả ----------
create table if not exists public.ket_qua_ontap3d (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  ho_ten text not null,
  lop text not null,
  loai text not null default 'hoan_thanh'
    check (loai in ('nha', 'hoan_thanh')),
  nha_so int check (nha_so is null or (nha_so between 1 and 6)),
  diem int not null default 0,
  -- Tổng điểm hộp quà may mắn tích lũy trong lượt chơi đó (có thể âm nếu
  -- mở phải hộp trừ 1 điểm; việc giữ tổng điểm game >= 0 là logic phía app).
  diem_hop_qua int not null default 0,
  tong_cau int not null default 0,
  dung_lan_dau int not null default 0,
  so_cau_sai int not null default 0,
  thoi_gian_giay int not null default 0,
  -- Mảng câu sai: [{nha, cau, hoi, dapAnDung, daChon}]
  cau_sai jsonb not null default '[]'::jsonb,
  -- Mã phiên chơi, để gom các dòng cùng 1 lượt chơi (1 dòng hoan_thanh
  -- + các dòng nha của cùng lượt).
  phien text not null,
  tao_luc timestamptz not null default now()
);
-- Phòng khi bảng đã tồn tại từ trước mà chưa có cột điểm hộp quà:
alter table public.ket_qua_ontap3d
  add column if not exists diem_hop_qua int not null default 0;

create index if not exists ket_qua_slug_lop_idx on public.ket_qua_ontap3d (slug, lop);
create index if not exists ket_qua_phien_idx on public.ket_qua_ontap3d (phien);
create index if not exists ket_qua_tao_luc_idx on public.ket_qua_ontap3d (tao_luc desc);

-- ---------- (b) RLS: học sinh chỉ gửi, quản trị mới xem ----------
alter table public.ket_qua_ontap3d enable row level security;

drop policy if exists ket_qua_gui on public.ket_qua_ontap3d;
create policy ket_qua_gui on public.ket_qua_ontap3d
  for insert to anon, authenticated with check (true);

drop policy if exists ket_qua_xem on public.ket_qua_ontap3d;
create policy ket_qua_xem on public.ket_qua_ontap3d
  for select to authenticated using (public.la_quan_tri());
-- Không có policy UPDATE/DELETE: mặc định cấm sửa, cấm xoá.

revoke all on public.ket_qua_ontap3d from anon, authenticated;
grant insert on public.ket_qua_ontap3d to anon, authenticated;
grant select on public.ket_qua_ontap3d to authenticated;

-- ---------- (c) RPC luu_ket_qua: game gọi để lưu 1 lượt chơi ----------
-- SECURITY INVOKER: chạy với quyền của người gọi (anon), nên vẫn chịu RLS
-- ở trên (anon được INSERT). Học sinh không đăng nhập vẫn gửi được.
create or replace function public.luu_ket_qua(
  p_slug text,
  p_ho_ten text,
  p_lop text,
  p_loai text,
  p_nha_so int,
  p_diem int,
  p_tong_cau int,
  p_dung_lan_dau int,
  p_so_cau_sai int,
  p_thoi_gian_giay int,
  p_cau_sai jsonb,
  p_phien text,
  p_diem_hop_qua int default 0
) returns uuid
language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
  if p_slug is null or btrim(p_slug) = '' then raise exception 'Thiếu mã bài'; end if;
  if p_ho_ten is null or char_length(btrim(p_ho_ten)) < 1 or char_length(btrim(p_ho_ten)) > 50 then
    raise exception 'Họ tên phải từ 1 đến 50 ký tự';
  end if;
  if p_lop is null or p_lop !~ '^[45]/([1-9]|1[0-5])$' then
    raise exception 'Lớp không đúng dạng (ví dụ 4/3, 5/1)';
  end if;
  if p_loai not in ('nha', 'hoan_thanh') then raise exception 'Loại kết quả không hợp lệ'; end if;
  if p_loai = 'nha' and (p_nha_so is null or p_nha_so < 1 or p_nha_so > 6) then
    raise exception 'Kết quả theo nhà cần số nhà từ 1 đến 6';
  end if;
  if p_phien is null or btrim(p_phien) = '' then raise exception 'Thiếu mã phiên chơi'; end if;
  insert into public.ket_qua_ontap3d
    (slug, ho_ten, lop, loai, nha_so, diem, diem_hop_qua, tong_cau, dung_lan_dau,
     so_cau_sai, thoi_gian_giay, cau_sai, phien)
  values
    (btrim(p_slug), btrim(p_ho_ten), p_lop, p_loai, p_nha_so,
     coalesce(p_diem, 0), coalesce(p_diem_hop_qua, 0), coalesce(p_tong_cau, 0),
     coalesce(p_dung_lan_dau, 0), coalesce(p_so_cau_sai, 0),
     coalesce(p_thoi_gian_giay, 0), coalesce(p_cau_sai, '[]'::jsonb), btrim(p_phien))
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.luu_ket_qua(text, text, text, text, int, int, int, int, int, int, jsonb, text, int) from public;
grant execute on function public.luu_ket_qua(text, text, text, text, int, int, int, int, int, int, jsonb, text, int) to anon, authenticated;

-- ---------- (d) RPC xem_ket_qua: trang thầy xem kết quả + thống kê ----------
-- Chỉ quản trị (raise exception nếu không phải). Trả 1 object JSON:
--   { ketQua: [dòng hoan_thanh, mới nhất trước, tối đa 500],
--     tongLuot, diemTrungBinh,
--     cauSaiNhieuNhat: top 5 {slug, nha, cau, hoi, tenNha, soLan} }
-- p_slug / p_lop để null = không lọc theo tiêu chí đó.
create or replace function public.xem_ket_qua(p_slug text default null, p_lop text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.la_quan_tri() then raise exception 'Không có quyền quản trị'; end if;
  return (
    with loc as (
      select * from public.ket_qua_ontap3d
      where loai = 'hoan_thanh'
        and (p_slug is null or slug = p_slug)
        and (p_lop is null or lop = p_lop)
    ),
    ds as (
      select * from loc order by tao_luc desc limit 500
    ),
    sai as (
      select l.slug as slug, (e ->> 'nha') as nha, (e ->> 'cau') as cau,
             (e ->> 'hoi') as hoi, count(*) as so_lan
      from loc l, jsonb_array_elements(l.cau_sai) as e
      group by l.slug, e ->> 'nha', e ->> 'cau', e ->> 'hoi'
      order by count(*) desc
      limit 5
    )
    select jsonb_build_object(
      'ketQua', coalesce((select jsonb_agg(jsonb_build_object(
          'id', d.id, 'slug', d.slug, 'hoTen', d.ho_ten, 'lop', d.lop,
          'diem', d.diem, 'diemHopQua', d.diem_hop_qua,
          'tongCau', d.tong_cau, 'dungLanDau', d.dung_lan_dau,
          'soCauSai', d.so_cau_sai, 'thoiGianGiay', d.thoi_gian_giay,
          'cauSai', d.cau_sai, 'phien', d.phien, 'taoLuc', d.tao_luc)
        order by d.tao_luc desc) from ds d), '[]'::jsonb),
      'tongLuot', (select count(*) from loc),
      'diemTrungBinh', coalesce((select round(avg(diem)::numeric, 1) from loc), 0),
      'cauSaiNhieuNhat', coalesce((select jsonb_agg(jsonb_build_object(
          'slug', s.slug, 'nha', s.nha, 'cau', s.cau, 'hoi', s.hoi,
          'tenNha', case
            when s.nha ~ '^[0-9]+$' then coalesce(
              (select n.ten from public.nha n join public.bai b on b.id = n.bai_id
               where b.slug = s.slug and n.thu_tu = s.nha::int),
              'Nhà ' || s.nha)
            else s.nha end,
          'soLan', s.so_lan) order by s.so_lan desc) from sai s), '[]'::jsonb)
    )
  );
end $$;
revoke all on function public.xem_ket_qua(text, text) from public, anon;
grant execute on function public.xem_ket_qua(text, text) to authenticated;

-- ---------- (e) Thêm cột giải thích + chỉ dẫn ----------
alter table public.cau_hoi add column if not exists giai_thich text;
alter table public.nha add column if not exists chi_dan text;

-- ---------- (f) Thêm cột hình ảnh + dạng câu hỏi ----------
-- hinh_anh: đường dẫn ảnh tương đối (vd 'hinh/bai6/hinh31-nhom-font.png')
--   hoặc URL https; NULL khi câu không có hình.
-- loai: 1 trong 4 dạng — choice (trắc nghiệm), truefalse (đúng/sai),
--   reorder (kéo thả sắp xếp), fillblank (điền từ). Dữ liệu cũ toàn
--   dạng choice nên mặc định 'choice' cho các dòng đã có.
-- dap_an: đáp án của 3 dạng mới — truefalse: true/false; reorder: mảng
--   thứ tự đúng; fillblank: {"chinh": "...", "phu": [...]}. Dạng choice
--   vẫn dùng chon + dung như cũ, dap_an để NULL.
alter table public.cau_hoi add column if not exists hinh_anh text;
alter table public.cau_hoi add column if not exists loai text not null default 'choice'
  check (loai in ('choice', 'truefalse', 'reorder', 'fillblank'));
alter table public.cau_hoi add column if not exists dap_an jsonb;

-- ---------- (g) Nới ràng buộc cũ của chon / dung + check theo dạng ----------
-- Chạy lại lần 2 không lỗi: khối DO bỏ mọi check cũ còn nhắc tới chon
-- hoặc dung (kể cả check mới do lần chạy trước thêm — phần dưới sẽ thêm
-- lại), rồi thêm lại check mới; dung DROP NOT NULL khi đã bỏ rồi cũng
-- không lỗi. Dữ liệu cũ toàn dạng choice có chon (mảng 3) + dung (0–2)
-- nên vẫn đạt mọi check mới.
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.cau_hoi'::regclass
      and contype = 'c'
      and (pg_get_constraintdef(oid) ilike '%chon%'
           or pg_get_constraintdef(oid) ilike '%dung%')
  loop
    execute format('alter table public.cau_hoi drop constraint %I', r.conname);
  end loop;
end $$;
-- chon: cho phép NULL (dạng truefalse/fillblank không dùng), còn có thì
-- là mảng 2–4 phần tử (nới từ ép đúng 3 như trước).
alter table public.cau_hoi
  add constraint cau_hoi_chon_2_4
  check (chon is null or (jsonb_typeof(chon) = 'array' and jsonb_array_length(chon) between 2 and 4));
-- dung: bỏ NOT NULL (3 dạng mới không dùng dung); còn có thì phải 0–2.
alter table public.cau_hoi alter column dung drop not null;
alter table public.cau_hoi
  add constraint cau_hoi_dung_0_2
  check (dung is null or dung between 0 and 2);
-- Nhất quán theo dạng: choice cần đủ chon + dung; truefalse cần dap_an
-- boolean; reorder cần dap_an mảng 2–4; fillblank cần dap_an object có
-- trường 'chinh'.
alter table public.cau_hoi drop constraint if exists cau_hoi_loai_check;
alter table public.cau_hoi
  add constraint cau_hoi_loai_check check (
    (loai = 'choice' and chon is not null and dung is not null)
    or (loai = 'truefalse' and jsonb_typeof(dap_an) = 'boolean')
    or (loai = 'reorder' and jsonb_typeof(dap_an) = 'array' and jsonb_array_length(dap_an) between 2 and 4)
    or (loai = 'fillblank' and jsonb_typeof(dap_an) = 'object' and dap_an ? 'chinh')
  );

-- ---------- (h) Cập nhật lay_bai: thêm loai + dapAn + hinhAnh ----------
-- Giữ nguyên signature lay_bai(p_slug text) và mọi trường cũ; chỉ thêm
-- 'loai', 'dapAn', 'hinhAnh' cho mỗi câu (cùng 'giaiThich' và 'chiDan'
-- đã có). Không ép số câu/nhà (DB live đã có 6 nhà × 5 câu, hàm này trả
-- đúng những gì có trong DB).
create or replace function public.lay_bai(p_slug text) returns jsonb
language sql stable security invoker set search_path = public as $$
  select jsonb_build_object(
    'slug', b.slug, 'xuatBan', b.xuat_ban,
    'tenTroChoi', b.ten_tro_choi, 'phuDe', b.phu_de, 'phongGiua', b.phong_giua,
    'nha', coalesce((select jsonb_agg(jsonb_build_object(
        'ten', n.ten, 'mau', n.mau, 'goc', n.goc,
        'chiDan', n.chi_dan,
        'thongTin', n.thong_tin, 'videoUrl', n.video_url, 'videoTieuDe', n.video_tieu_de,
        'cau', coalesce((select jsonb_agg(jsonb_build_object(
            'muc', c.muc, 'hoi', c.hoi, 'chon', c.chon, 'dung', c.dung, 'goiy', c.goi_y,
            'giaiThich', c.giai_thich,
            'loai', c.loai, 'dapAn', c.dap_an, 'hinhAnh', c.hinh_anh,
            'videoUrl', c.video_url, 'videoTieuDe', c.video_tieu_de) order by c.thu_tu)
          from public.cau_hoi c where c.nha_id = n.id), '[]'::jsonb)
      ) order by n.thu_tu) from public.nha n where n.bai_id = b.id), '[]'::jsonb))
  from public.bai b where b.slug = p_slug and (b.xuat_ban or public.la_quan_tri());
$$;
grant execute on function public.lay_bai(text) to anon, authenticated;

-- ---------- (i) Cập nhật luu_bai: 6 nhà × 1–10 câu, 4 dạng câu hỏi ----------
-- Giữ nguyên signature luu_bai(p_slug text, p_data jsonb, p_xuat_ban boolean).
-- Khác bản cũ: mỗi nhà 1–10 câu (không ép đúng 3), mức độ lấy từ JSON
-- (không ép theo vị trí câu), lưu thêm chiDan + giaiThich + loai/dapAn/
-- hinhAnh (chấp nhận cả 2 tên trường JSON 'hinh' và 'hinhAnh'), chon/dung
-- cho phép NULL, validate riêng theo từng dạng câu hỏi. Vẫn chỉ quản trị.
create or replace function public.luu_bai(p_slug text, p_data jsonb, p_xuat_ban boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_bai uuid; v_nha uuid; n jsonb; c jsonb; i int; j int; v_so_cau int; v_muc text;
  v_loai text; v_dap_an jsonb; v_hinh text;
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
    if jsonb_typeof(n -> 'cau') <> 'array' then raise exception 'Nhà % thiếu danh sách câu hỏi', i + 1; end if;
    v_so_cau := jsonb_array_length(n -> 'cau');
    if v_so_cau < 1 or v_so_cau > 10 then raise exception 'Nhà % cần từ 1 đến 10 câu (đang có % câu)', i + 1, v_so_cau; end if;
    insert into public.nha (bai_id, thu_tu, ten, mau, goc, chi_dan, thong_tin, video_url, video_tieu_de)
    values (v_bai, i + 1, n ->> 'ten', coalesce(nullif(n ->> 'mau', ''), '#1f6fe0'), coalesce((n ->> 'goc')::int, 0),
            nullif(n ->> 'chiDan', ''), nullif(n ->> 'thongTin', ''), nullif(n ->> 'videoUrl', ''), nullif(n ->> 'videoTieuDe', ''))
    returning id into v_nha;
    for j in 0..(v_so_cau - 1) loop
      c := (n -> 'cau') -> j;
      v_muc := c ->> 'muc';
      if v_muc is null or v_muc not in ('BIẾT', 'HIỂU', 'VẬN DỤNG') then
        raise exception 'Nhà %, câu %: mức độ phải là BIẾT, HIỂU hoặc VẬN DỤNG', i + 1, j + 1;
      end if;
      -- Dạng câu hỏi: mặc định 'choice' khi JSON không ghi loai.
      v_loai := coalesce(nullif(c ->> 'loai', ''), 'choice');
      if v_loai not in ('choice', 'truefalse', 'reorder', 'fillblank') then
        raise exception 'Nhà %, câu %: dạng câu hỏi phải là choice, truefalse, reorder hoặc fillblank', i + 1, j + 1;
      end if;
      v_dap_an := c -> 'dapAn';
      v_hinh := coalesce(nullif(c ->> 'hinh', ''), nullif(c ->> 'hinhAnh', ''));
      -- Validate riêng theo từng dạng (thông báo tiếng Việt rõ ràng).
      if v_loai = 'choice' then
        if jsonb_typeof(c -> 'chon') <> 'array' or jsonb_array_length(c -> 'chon') <> 3 then
          raise exception 'Nhà %, câu %: câu trắc nghiệm cần đúng 3 lựa chọn', i + 1, j + 1;
        end if;
        if (c ->> 'dung') is null or (c ->> 'dung') !~ '^[0-2]$' then
          raise exception 'Nhà %, câu %: đáp án đúng phải là 0, 1 hoặc 2', i + 1, j + 1;
        end if;
      elsif v_loai = 'truefalse' then
        if jsonb_typeof(v_dap_an) <> 'boolean' then
          raise exception 'Nhà %, câu %: câu đúng/sai cần đáp án true hoặc false', i + 1, j + 1;
        end if;
      elsif v_loai = 'reorder' then
        if jsonb_typeof(v_dap_an) <> 'array' or jsonb_array_length(v_dap_an) < 2 or jsonb_array_length(v_dap_an) > 4 then
          raise exception 'Nhà %, câu %: câu sắp xếp cần đáp án là mảng từ 2 đến 4 phần tử', i + 1, j + 1;
        end if;
      elsif v_loai = 'fillblank' then
        if jsonb_typeof(v_dap_an) <> 'object' or not (v_dap_an ? 'chinh') then
          raise exception 'Nhà %, câu %: câu điền từ cần đáp án có trường "chinh"', i + 1, j + 1;
        end if;
      end if;
      insert into public.cau_hoi (nha_id, thu_tu, muc, hoi, chon, dung, goi_y, giai_thich, video_url, video_tieu_de, loai, dap_an, hinh_anh)
      values (v_nha, j + 1, v_muc, c ->> 'hoi', c -> 'chon',
              case when (c ->> 'dung') ~ '^[0-2]$' then (c ->> 'dung')::int end,
              nullif(c ->> 'goiy', ''), nullif(c ->> 'giaiThich', ''),
              nullif(c ->> 'videoUrl', ''), nullif(c ->> 'videoTieuDe', ''),
              v_loai, v_dap_an, v_hinh);
    end loop;
  end loop;
  return public.lay_bai(p_slug);
end $$;
revoke all on function public.luu_bai(text, jsonb, boolean) from public, anon;
grant execute on function public.luu_bai(text, jsonb, boolean) to authenticated;

-- ---------- (j) Nới ràng buộc cau_hoi.thu_tu: 1..3 → 1..10 ----------
-- Tìm ràng buộc kiểm tra theo ĐỊNH NGHĨA (không theo tên, vì tên có thể
-- khác nhau tùy DB): bỏ ràng buộc cũ nào còn chặn quá 3 câu, rồi thêm
-- ràng buộc 1..10 nếu chưa có. Chạy lại lần 2 không lỗi; DB live nào
-- đã nới rồi thì khối này không làm gì cả.
do $$
declare
  r record;
  v_da_noi boolean := false;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.cau_hoi'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%thu_tu%'
      and pg_get_constraintdef(oid) not ilike '%between 1 and 10%'
      and pg_get_constraintdef(oid) not ilike '%<= 10%'
  loop
    execute format('alter table public.cau_hoi drop constraint %I', r.conname);
  end loop;
  select exists (
    select 1 from pg_constraint
    where conrelid = 'public.cau_hoi'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%thu_tu%'
      and (pg_get_constraintdef(oid) ilike '%between 1 and 10%'
           or pg_get_constraintdef(oid) ilike '%<= 10%')
  ) into v_da_noi;
  if not v_da_noi then
    alter table public.cau_hoi
      add constraint cau_hoi_thu_tu_1_10 check (thu_tu between 1 and 10);
  end if;
end $$;

-- ============================================================
-- KIỂM TRA NHANH (3 câu dưới chạy kèm khi Run, chỉ đọc, không sửa gì):
-- ============================================================
-- 1. Đếm số dòng kết quả đã lưu (mới dán xong thì = 0, bình thường).
select count(*) as so_dong_ket_qua from public.ket_qua_ontap3d;
-- 2. Xem lay_bai đã trả thêm giaiThich chưa (NULL là bình thường: giải thích
-- chỉ có sau khi nạp lại nội dung có trường giaiThich qua trang /admin
-- hoặc RPC luu_bai; quan trọng là câu này CHẠY ĐƯỢC, không báo lỗi cột).
select lay_bai('tin5-ban-quyen') -> 'nha' -> 0 -> 'cau' -> 0 ->> 'giaiThich' as giai_thich_cau_dau_tien;
-- 3. Xem các cột mới của bảng cau_hoi (phải liệt kê đủ 4 dòng:
-- hinh_anh, loai, dap_an, giai_thich).
select column_name from information_schema.columns
where table_name = 'cau_hoi' and column_name in ('hinh_anh', 'loai', 'dap_an', 'giai_thich')
order by column_name;
