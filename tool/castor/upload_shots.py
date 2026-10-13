#!/usr/bin/env python3
"""화면 캡처 PNG 폴더 → Castor 썸네일.

  python3 tool/castor/upload_shots.py build/castor_shots [--dry-run]

PNG 파일 이름이 곧 Castor 화면 ID 다(예: store.detail.png).
1) 관리자 토큰으로 Castor `player` 문서를 읽는다.
2) 바뀐 PNG 만 presign(upload_type=castor)으로 S3 castor/ 에 올린다(내용 해시가 같으면 건너뜀).
3) player 문서의 thumbs[화면 ID] 를 새 주소로 바꾸고 thumbs_meta 에 해시 · 커밋 · 시각을 남긴다.
   처음 한 번은 손으로 찍은 옛 썸네일을 thumbs_manual 에 보관한다.
4) base_updated_at 으로 저장 — 그사이 누가 고쳤으면(409) 다시 읽어 합친다.

환경 변수
  CASTOR_ADMIN_TOKEN  (필수) 세틀라이트 관리자 로그인 access 토큰(Bearer). 30일마다 만료.
  CASTOR_API_URL      (선택) 백엔드 주소. 기본값은 앱 ApiClient.baseUrl 과 같은 주소.
  CASTOR_SOURCE       (선택) thumbs_meta 에 남길 출처(예: 커밋 SHA · 버전)

외부 패키지 없이 표준 라이브러리만 쓴다.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_API = "https://deliberate-lenette-coggiri-5ee7b85e.koyeb.app"
DOC_PATH = "/api/dashboard/admin/castor/player/"
PRESIGN_PATH = "/api/dashboard/images/presign/"


class ApiError(Exception):
    def __init__(self, status, body):
        super().__init__(f"HTTP {status}: {body[:300]}")
        self.status = status
        self.body = body


def call(method, url, token=None, payload=None, raw=None, content_type="application/json"):
    headers = {"Accept": "application/json"}
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    elif raw is not None:
        data = raw
        headers["Content-Type"] = content_type
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read().decode("utf-8", "replace")
            return json.loads(body) if body.strip().startswith(("{", "[")) else body
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, e.read().decode("utf-8", "replace")) from None


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def load_shots(folder):
    shots = {}
    for name in sorted(os.listdir(folder)):
        if name.endswith(".png"):
            shots[name[:-4]] = os.path.join(folder, name)
    return shots


def upload_png(api, token, screen_id, path):
    pr = call("POST", api + PRESIGN_PATH, token, {
        "filename": f"{screen_id}.png", "content_type": "image/png", "upload_type": "castor",
    })
    with open(path, "rb") as f:
        call("PUT", pr["upload_url"], raw=f.read(), content_type="image/png")
    return pr["public_url"]


def merge(data, uploads, source, now):
    data = dict(data or {})
    thumbs = dict(data.get("thumbs") or {})
    meta = dict(data.get("thumbs_meta") or {})
    if "thumbs_manual" not in data:
        # 자동 캡처로 처음 덮기 전에, 손으로 찍은 옛 썸네일을 한 번만 보관한다.
        data["thumbs_manual"] = dict(thumbs)
    for sid, (url, digest) in uploads.items():
        thumbs[sid] = url
        meta[sid] = {"sha256": digest, "source": source, "at": now, "auto": True}
    data["thumbs"] = thumbs
    data["thumbs_meta"] = meta
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", help="PNG 폴더(파일 이름 = 화면 ID)")
    ap.add_argument("--dry-run", action="store_true", help="올리지 않고 무엇이 바뀌는지만 출력")
    args = ap.parse_args()

    shots = load_shots(args.folder)
    if not shots:
        sys.exit(f"PNG 가 없습니다: {args.folder}")

    token = os.environ.get("CASTOR_ADMIN_TOKEN", "").strip()
    api = os.environ.get("CASTOR_API_URL", DEFAULT_API).rstrip("/")
    source = os.environ.get("CASTOR_SOURCE", "local")
    if not token:
        if args.dry_run:
            print(f"[dry-run] 토큰 없음 — PNG {len(shots)}장: {', '.join(shots)}")
            return
        sys.exit("CASTOR_ADMIN_TOKEN 이 없습니다(세틀라이트 관리자 access 토큰).")

    try:
        doc = call("GET", api + DOC_PATH, token)
    except ApiError as e:
        if e.status in (401, 403):
            sys.exit(f"토큰이 거절됐습니다({e.status}) — 만료(30일)됐거나 관리자 토큰이 아닙니다. 새로 받아 CASTOR_ADMIN_TOKEN 을 갱신하세요.")
        raise
    data = doc.get("data") or {}
    meta = data.get("thumbs_meta") or {}
    thumbs = data.get("thumbs") or {}

    todo = {}
    for sid, path in shots.items():
        digest = sha256(path)
        if thumbs.get(sid) and (meta.get(sid) or {}).get("sha256") == digest:
            continue
        todo[sid] = (path, digest)
    print(f"PNG {len(shots)}장 중 바뀐 것 {len(todo)}장")
    if args.dry_run or not todo:
        for sid in todo:
            print("  ·", sid)
        return

    uploads = {}
    for sid, (path, digest) in todo.items():
        uploads[sid] = (upload_png(api, token, sid, path), digest)
        print("  ↑", sid)

    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    for attempt in range(3):
        body = {"data": merge(data, uploads, source, now), "base_updated_at": doc.get("updated_at")}
        try:
            call("PUT", api + DOC_PATH, token, body)
            print(f"player.thumbs 갱신 완료({len(uploads)}장)")
            return
        except ApiError as e:
            if e.status != 409 or attempt == 2:
                raise
            # 그사이 누가 player 문서를 고쳤다 — 새로 읽어 우리 썸네일만 다시 얹는다.
            doc = call("GET", api + DOC_PATH, token)
            data = doc.get("data") or {}


if __name__ == "__main__":
    main()
