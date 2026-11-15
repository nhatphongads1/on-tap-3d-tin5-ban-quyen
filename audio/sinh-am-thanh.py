#!/usr/bin/env python3
"""Sinh file MP3 giong doc that (Edge-TTS, vi-VN-HoaiMyNeural) cho app ontap3d.

Cach chay:
    python3 sinh-am-thanh.py            # sinh file nao con thieu/loi
    python3 sinh-am-thanh.py --force    # sinh lai toan bo

Yeu cau:
    pip3 install --break-system-packages edge-tts websockets
    ffmpeg + ffprobe co san trong PATH

Luu y ky thuat (15/11/2026):
    - edge-tts goc KHONG chay duoc tren VM nay: aiohttp tu choi handshake
      vi proxy egress tra ve header "Connection: upgrade, close" thay vi
      "upgrade" dung (aiohttp doi khop chinh xac). Script nay dung lai
      giao thuc + token DRM cua edge-tts nhung truyen qua thu vien
      `websockets` (chap nhan header Connection dang danh sach).
    - Ket noi phai di qua proxy egress (bien moi truong https_proxy).
    - Output goc cua Edge la mp3 mono 24kHz 48kbit; script van chay qua
      ffmpeg -ac 1 -b:a 48k de chuan hoa, roi xoa ban tam.
"""
import argparse
import asyncio
import json
import os
import re
import subprocess
import sys
import time
from xml.sax.saxutils import escape

import websockets
from edge_tts.communicate import (
    connect_id,
    date_to_string,
    get_headers_and_data,
    mkssml,
    ssml_headers_plus_data,
)
from edge_tts.constants import SEC_MS_GEC_VERSION, WSS_HEADERS, WSS_URL
from edge_tts.data_classes import TTSConfig
from edge_tts.drm import DRM

VOICE = "vi-VN-HoaiMyNeural"
ROOT = os.path.dirname(os.path.abspath(__file__))          # .../ontap3d-source/audio
SRC = os.path.dirname(ROOT)                                # .../ontap3d-source
MAX_RETRIES = 3
SLEEP_BETWEEN_CALLS = 1.0                                  # giay
MIN_DURATION = 0.5                                         # giay


# ------------------------------------------------------------------ TTS core
async def synth_once(text: str, out_path: str) -> int:
    """Mot lan goi Edge-TTS qua websocket. Tra ve so byte am thanh."""
    tc = TTSConfig(voice=VOICE, rate="+0%", volume="+0%", pitch="+0Hz",
                   boundary="SentenceBoundary")
    url = (f"{WSS_URL}&ConnectionId={connect_id()}"
           f"&Sec-MS-GEC={DRM.generate_sec_ms_gec()}"
           f"&Sec-MS-GEC-Version={SEC_MS_GEC_VERSION}")
    # websockets tu them Sec-WebSocket-*; truyen trung se bi server tra 400.
    headers = {k: v for k, v in DRM.headers_with_muid(WSS_HEADERS).items()
               if not k.lower().startswith("sec-websocket")}
    audio = bytearray()
    async with websockets.connect(
        url, additional_headers=headers,
        proxy=os.environ.get("https_proxy") or os.environ.get("HTTPS_PROXY"),
        max_size=None, open_timeout=30,
    ) as ws:
        await ws.send(
            f"X-Timestamp:{date_to_string()}\r\n"
            "Content-Type:application/json; charset=utf-8\r\n"
            "Path:speech.config\r\n\r\n"
            '{"context":{"synthesis":{"audio":{"metadataoptions":'
            '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
            '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n'
        )
        await ws.send(ssml_headers_plus_data(
            connect_id(), date_to_string(), mkssml(tc, escape(text))))
        async for msg in ws:
            if isinstance(msg, str):
                data = msg.encode("utf-8")
                params, _ = get_headers_and_data(data, data.find(b"\r\n\r\n"))
                if params.get(b"Path") == b"turn.end":
                    break
            else:
                if len(msg) < 2:
                    continue
                hl = int.from_bytes(msg[:2], "big")
                params, data = get_headers_and_data(msg, hl)
                if params.get(b"Path") == b"audio" and data:
                    audio.extend(data)
    if not audio:
        raise RuntimeError("khong nhan duoc am thanh tu Edge-TTS")
    with open(out_path, "wb") as f:
        f.write(audio)
    return len(audio)


def synth_with_retry(text: str, tmp_path: str) -> bool:
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            asyncio.run(synth_once(text, tmp_path))
            return True
        except Exception as e:  # noqa: BLE001 - retry moi loi tam thoi
            print(f"    [thu {attempt}/{MAX_RETRIES}] loi: {e}", flush=True)
            if attempt < MAX_RETRIES:
                time.sleep(2 * attempt)
    return False


# ------------------------------------------------------------------ ffmpeg
def convert_mono_48k(src_path: str, dst_path: str) -> bool:
    """Chuyen ve mono 48k, xoa file goc. Tra ve True neu OK."""
    tmp = dst_path + ".tmp.mp3"
    r = subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", src_path,
         "-ac", "1", "-b:a", "48k", tmp],
        capture_output=True, text=True)
    if r.returncode != 0:
        print(f"    ffmpeg loi: {r.stderr.strip()}", flush=True)
        return False
    os.replace(tmp, dst_path)
    os.remove(src_path)
    return True


def probe_duration(path: str):
    """Tra ve thoi luong (giay) hoac None neu file loi."""
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return float(r.stdout.strip())
    except ValueError:
        return None


def file_ok(path: str) -> bool:
    d = probe_duration(path)
    return d is not None and d > MIN_DURATION


# ------------------------------------------------------------------ nguon text
def norm_sentence(s: str) -> str:
    """Bo khoang trang/dau cham thua o cuoi, them 1 dau cham."""
    return re.sub(r"\s+", " ", s).strip().rstrip(".") + "."


def load_gsteps():
    html = open(os.path.join(SRC, "index.html"), encoding="utf-8").read()
    m = re.search(r"const GSTEPS=(\[.*?\]);", html, re.S)
    if not m:
        raise RuntimeError("khong tim thay const GSTEPS trong index.html")
    return json.loads(m.group(1))


def load_cau_hoi_js():
    js = open(os.path.join(SRC, "cau-hoi.js"), encoding="utf-8").read()
    return json.loads(js[js.index("{"):js.rindex("}") + 1], strict=False)


def question_text(cau: dict) -> str:
    chon = cau["chon"]
    return (f"Câu hỏi. {norm_sentence(cau['hoi'])} "
            f"A. {norm_sentence(chon[0])} "
            f"B. {norm_sentence(chon[1])} "
            f"C. {norm_sentence(chon[2])}")


def question_text_bai6(cau: dict) -> str:
    """Text doc cho Bai 6 (4 dang) — giong qText() trong game."""
    loai = cau.get("loai", "choice")
    hoi = norm_sentence(cau["hoi"])
    if loai == "truefalse":
        return f"Câu hỏi. {hoi} Đúng hay Sai?"
    if loai in ("reorder", "fillblank"):
        if loai == "fillblank":
            hoi = hoi.replace("___", "chỗ trống")
        return f"Câu hỏi. {hoi}"
    chon = cau["chon"]
    return (f"Câu hỏi. {hoi} "
            f"A. {norm_sentence(chon[0])} "
            f"B. {norm_sentence(chon[1])} "
            f"C. {norm_sentence(chon[2])}")


def build_jobs():
    """Tra ve list (duong dan tuong doi tu audio/, text doc)."""
    jobs = []
    # 1. Huong dan 5 buoc
    for i, s in enumerate(load_gsteps(), 1):
        text = f"Bước {i}. {norm_sentence(s['t'])} {norm_sentence(s['x'])}"
        jobs.append((f"chung/hd{i}.mp3", text))
    # 2. Phan hoi
    jobs.append(("chung/dung.mp3", "Chính xác!"))
    jobs.append(("chung/sai.mp3", "Chưa đúng, thử lại nhé."))
    for n in range(1, 7):
        jobs.append((f"chung/nha{n}.mp3",
                     f"Chính xác! Em đã hoàn thành nhà số {n}."))
    # 3. Vinh danh
    jobs.append(("chung/vinhdanh.mp3",
                 "Chúc mừng em! Em đã hoàn thành cả sáu nhà."))
    # 4. Tin 5 Ban quyen: 6 nha x 3 cau
    d5 = load_cau_hoi_js()
    for hi, nha in enumerate(d5["nha"], 1):
        for ci, cau in enumerate(nha["cau"], 1):
            jobs.append((f"tin5-ban-quyen/nha{hi}_cau{ci}.mp3",
                         question_text(cau)))
    # 5. Tin 4 Bai 5-6: 6 nha x 5 cau
    with open(os.path.join(SRC, "noi-dung", "tin4-bai-5-6.json"),
              encoding="utf-8") as f:
        d4 = json.load(f)
    for hi, nha in enumerate(d4["nha"], 1):
        for ci, cau in enumerate(nha["cau"], 1):
            jobs.append((f"tin4-bai-5-6/nha{hi}_cau{ci}.mp3",
                         question_text(cau)))
    # 6. Tin 5 Bai 6: 6 nha x 5 cau (tron 4 dang)
    with open(os.path.join(SRC, "noi-dung", "tin5-bai-6.json"),
              encoding="utf-8") as f:
        d6 = json.load(f)
    for hi, nha in enumerate(d6["nha"], 1):
        for ci, cau in enumerate(nha["cau"], 1):
            jobs.append((f"tin5-bai-6/nha{hi}_cau{ci}.mp3",
                         question_text_bai6(cau)))
    return jobs


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true",
                    help="sinh lai toan bo, ke ca file da co")
    args = ap.parse_args()

    jobs = build_jobs()
    print(f"Tong {len(jobs)} file can sinh, giong {VOICE}")
    tmpdir = os.path.join(ROOT, ".tmp")
    os.makedirs(tmpdir, exist_ok=True)
    failed, skipped = [], 0
    total_dur = 0.0

    for idx, (rel, text) in enumerate(jobs, 1):
        dst = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not args.force and os.path.exists(dst) and file_ok(dst):
            skipped += 1
            total_dur += probe_duration(dst)
            print(f"[{idx}/{len(jobs)}] BO QUA (da co): {rel}", flush=True)
            continue
        print(f"[{idx}/{len(jobs)}] {rel} ({len(text)} ky tu)",
              flush=True)
        tmp = os.path.join(tmpdir, f"tmp_{idx}.mp3")
        ok = synth_with_retry(text, tmp)
        if ok:
            ok = convert_mono_48k(tmp, dst)
        if ok:
            d = probe_duration(dst)
            if d is None or d <= MIN_DURATION:
                print(f"    LOI: file khong co tieng (duration={d})",
                      flush=True)
                ok = False
            else:
                total_dur += d
                print(f"    OK: {d:.1f}s, "
                      f"{os.path.getsize(dst) // 1024} KB", flush=True)
        if not ok:
            failed.append(rel)
        if idx < len(jobs):
            time.sleep(SLEEP_BETWEEN_CALLS)

    # Don tmp
    for f in os.listdir(tmpdir):
        os.remove(os.path.join(tmpdir, f))
    os.rmdir(tmpdir)

    total_bytes = 0
    n_files = 0
    for dirpath, _, files in os.walk(ROOT):
        for f in files:
            if f.endswith(".mp3"):
                total_bytes += os.path.getsize(os.path.join(dirpath, f))
                n_files += 1
    print("\n===== TONG KET =====")
    print(f"File MP3: {n_files} | Bo qua: {skipped} | Loi: {len(failed)}")
    print(f"Tong thoi luong: {total_dur:.0f}s")
    print(f"Tong dung luong audio/: {total_bytes / 1024 / 1024:.2f} MB")
    if failed:
        print("File loi/thieu:")
        for f in failed:
            print(f"  - {f}")
    else:
        print("Khong co file loi.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
