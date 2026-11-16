#!/usr/bin/env python3
"""Blood Omen 2 (PS2 북미판 SLUS-20024) 한글패치 적용기 (Python 3.8+, 추가 설치 없음)
사용: python3 patch.py "원본.iso" [--wide] [--controls]
      선택 사항을 하나도 안 주면 물어봅니다. 묻지 않고 한글패치만 적용하려면 --korean-only
결과: 같은 폴더에 "원본이름 (Korean).iso" """
import sys, os, json, zlib, struct, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
CHUNK = 1 << 20


def fail(msg, out=None):
    if out and os.path.exists(out):
        os.remove(out)
    print("\n[실패] " + msg)
    sys.exit(1)


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(CHUNK), b""):
            h.update(b)
    return h.hexdigest()


def header(path):
    with open(path, "rb") as f:
        if f.read(8) != b"BO2KOR1\0":
            fail("패치 데이터 형식이 다릅니다: " + path)
        n = struct.unpack("<I", f.read(4))[0]
        return json.loads(f.read(n).decode("utf-8")), f.tell()


class Data:
    """raw deflate 스트림에서 필요한 만큼만 읽는다"""
    def __init__(self, f):
        self.f, self.d, self.buf = f, zlib.decompressobj(-15), bytearray()

    def read(self, n):
        while len(self.buf) < n:
            raw = self.f.read(CHUNK)
            if not raw:
                break
            self.buf += self.d.decompress(raw)
        if len(self.buf) < n:
            fail("패치 데이터가 모자랍니다 (파일 손상)")
        out = bytes(self.buf[:n])
        del self.buf[:n]
        return out


def apply(orig, patch, body, out, create):
    """ops: 0 SEEK(대상 위치) 1 COPY(원본 위치, 길이) 2 DATA(길이) 3 ZERO(길이). 쓴 바이트 전체의 MD5를 돌려준다"""
    h = hashlib.md5()
    with open(patch, "rb") as p, open(orig, "rb") as src, open(out, "wb" if create else "r+b") as dst:
        p.seek(body)
        ops = zlib.decompress(p.read(struct.unpack("<I", p.read(4))[0]), -15)
        data = Data(p)
        for i in range(0, len(ops) - 12, 13):
            typ, length, arg = struct.unpack_from("<BIQ", ops, i)
            if typ == 0:
                dst.seek(arg)
                continue
            if typ == 1:
                src.seek(arg)
            while length:
                n = min(length, CHUNK)
                if typ == 3:
                    b = bytes(n)
                elif typ == 1:
                    b = src.read(n)
                    if len(b) != n:
                        fail("원본 ISO를 끝까지 읽지 못했습니다")
                else:
                    b = data.read(n)
                dst.write(b)
                if not create:
                    h.update(b)
                length -= n
    return h.hexdigest()


def yes(question):
    try:
        return input(question + " (Y/N, 기본 N) ").strip().lower().startswith("y")
    except EOFError:
        return False


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if len(args) != 1 or flags - {"--wide", "--controls", "--korean-only"}:
        fail('사용법: python3 patch.py "원본.iso" [--wide] [--controls] [--korean-only]')
    iso = os.path.abspath(args[0])
    base = os.path.join(HERE, "bo2_kor.bin")
    if not os.path.isfile(base):
        fail("bo2_kor.bin 이 patch.py 와 같은 폴더에 없습니다.")
    if not os.path.isfile(iso):
        fail("원본 ISO 파일을 찾을 수 없습니다: " + iso)
    h, body = header(base)
    print("Blood Omen 2 한글패치 v%s  -  by Yonggary6425" % h["version"])
    print("원본:", iso, "\n")
    wide, controls = "--wide" in flags, "--controls" in flags
    if not flags:
        print("한글패치는 항상 적용됩니다. 아래 두 가지는 원하는 것만 고르세요.\n")
        print("[선택 1] 16:9 와이드 화면 - 시야를 좌우로 넓혀 16:9로 그립니다. (에뮬레이터·TV를 16:9로 맞춰야 합니다)")
        wide = yes("  적용할까요?")
        print("[선택 2] 조작 체계 변경 - 왼쪽 스틱: 앞뒤 이동 + 좌우 게걸음 / 오른쪽 스틱: 시점 회전")
        controls = yes("  적용할까요?")
        print()
    extras = []
    if wide:
        extras.append(("16:9 와이드 화면", "bo2_opt_wide.bin"))
    if controls:
        extras.append(("조작 체계 변경", "bo2_opt_controls.bin"))
    if os.path.isfile(os.path.join(HERE, "bo2_kor_movies.bin")):
        extras.append(("동영상 자막", "bo2_kor_movies.bin"))
    for _, name in extras:
        if not os.path.isfile(os.path.join(HERE, name)):
            fail(name + " 이 patch.py 와 같은 폴더에 없습니다.")
    size = os.path.getsize(iso)
    if size != h["origSize"]:
        fail("원본 ISO 크기가 다릅니다. (필요: %d 바이트, 지금: %d 바이트)\n  북미판 SLUS-20024 원본 ISO인지, 이미 패치한 파일이 아닌지 확인해 주세요." % (h["origSize"], size))
    print("원본 확인 중...")
    if md5(iso) != h["origMd5"]:
        fail("원본 ISO 내용이 제작에 쓴 원본과 다릅니다. (필요 MD5: %s)" % h["origMd5"])
    out = os.path.splitext(iso)[0] + " (Korean).iso"
    print("한글판 만드는 중... (1~2분 걸립니다)")
    apply(iso, base, body, out, True)
    print("결과 확인 중...")
    if md5(out) != h["targetMd5"]:
        fail("결과 파일 검사값이 다릅니다. 파일을 지웠습니다. 다시 시도해 주세요.", out)
    applied = ["한글패치"]
    for label, name in extras:
        eh, ebody = header(os.path.join(HERE, name))
        if eh["version"] != h["version"]:
            fail("%s 이 이 버전(v%s)의 패치와 맞지 않습니다." % (name, h["version"]), out)
        print(label + " 적용 중...")
        if apply(iso, os.path.join(HERE, name), ebody, out, False) != eh["payloadMd5"]:
            fail(label + " 적용 검사값이 다릅니다. 결과 파일을 지웠습니다.", out)
        applied.append(label)
    print("\n완료! (%s)\n만든 파일: %s\nMD5: %s" % (" + ".join(applied), out, md5(out)))


if __name__ == "__main__":
    main()
