#!/usr/bin/env python3
"""Blood Omen 2 (PS2 북미판 SLUS-20024) 한글패치 적용기 (Python 3.8+, 추가 설치 없음)
사용: python3 patch.py "원본.iso"   ->  같은 폴더에 "원본이름 (Korean).iso" 생성"""
import sys, os, json, zlib, struct, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
CHUNK = 1 << 20


def fail(msg):
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
    """ops: 0 SEEK(대상 위치) 1 COPY(원본 위치, 길이) 2 DATA(길이) 3 ZERO(길이)"""
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
                    dst.write(bytes(n))
                elif typ == 1:
                    b = src.read(n)
                    if len(b) != n:
                        fail("원본 ISO를 끝까지 읽지 못했습니다")
                    dst.write(b)
                else:
                    dst.write(data.read(n))
                length -= n


def main():
    if len(sys.argv) != 2:
        fail('사용법: python3 patch.py "원본.iso"')
    iso = os.path.abspath(sys.argv[1])
    core, movies = os.path.join(HERE, "bo2_kor.bin"), os.path.join(HERE, "bo2_kor_movies.bin")
    if not os.path.isfile(core):
        fail("bo2_kor.bin 이 patch.py 와 같은 폴더에 없습니다.")
    if not os.path.isfile(iso):
        fail("원본 ISO 파일을 찾을 수 없습니다: " + iso)
    h, body = header(core)
    print("Blood Omen 2 한글패치 v%s  -  by Yonggary6425" % h["version"])
    print("원본:", iso)
    size = os.path.getsize(iso)
    if size != h["origSize"]:
        fail("원본 ISO 크기가 다릅니다. (필요: %d 바이트, 지금: %d 바이트)\n  북미판 SLUS-20024 원본 ISO인지, 이미 패치한 파일이 아닌지 확인해 주세요." % (h["origSize"], size))
    print("원본 확인 중...")
    if md5(iso) != h["origMd5"]:
        fail("원본 ISO 내용이 제작에 쓴 원본과 다릅니다. (필요 MD5: %s)" % h["origMd5"])
    out = os.path.splitext(iso)[0] + " (Korean).iso"
    print("한글판 만드는 중... (몇 분 걸릴 수 있습니다)")
    apply(iso, core, body, out, True)
    expect, label = h["targetMd5"], "한글패치"
    if os.path.isfile(movies):
        mh, mbody = header(movies)
        if mh["baseMd5"] != h["targetMd5"]:
            fail("bo2_kor_movies.bin 이 이 버전의 패치와 맞지 않습니다.")
        print("동영상 자막 적용 중...")
        apply(iso, movies, mbody, out, False)
        expect, label = mh["targetMd5"], "한글패치 + 동영상 자막"
    print("결과 확인 중...")
    got = md5(out)
    if got != expect:
        os.remove(out)
        fail("결과 파일 검사값이 다릅니다. 파일을 지웠습니다. 다시 시도해 주세요.")
    print("\n완료! (%s)\n만든 파일: %s\nMD5: %s" % (label, out, got))


if __name__ == "__main__":
    main()
