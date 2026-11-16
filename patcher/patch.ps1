# Blood Omen 2 (PS2 북미판 SLUS-20024) 한글패치 적용기 - Windows PowerShell 기본 기능만 사용
# 사용: 원본 ISO를 "패치하기.bat" 위에 끌어다 놓기  /  powershell -File patch.ps1 "원본.iso"
param([Parameter(Mandatory = $true)][string]$Iso)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Add-Type -TypeDefinition @'
using System; using System.IO; using System.IO.Compression; using System.Security.Cryptography; using System.Text;
public static class Bo2Patch {
  public static string Header(string patch, out long bodyOffset) {
    using (FileStream f = File.OpenRead(patch)) using (BinaryReader r = new BinaryReader(f)) {
      string magic = Encoding.ASCII.GetString(r.ReadBytes(8));
      if (magic != "BO2KOR1\0") throw new Exception("패치 데이터 형식이 다릅니다: " + patch);
      int n = r.ReadInt32(); string json = Encoding.UTF8.GetString(r.ReadBytes(n)); bodyOffset = f.Position; return json;
    }
  }
  public static string Md5(string file) {
    using (FileStream f = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20)) using (MD5 m = MD5.Create()) {
      return BitConverter.ToString(m.ComputeHash(f)).Replace("-", "").ToLowerInvariant();
    }
  }
  // ops: 0 SEEK(target offset) 1 COPY(original offset, length) 2 DATA(length) 3 ZERO(length)
  public static void Apply(string orig, string patch, long bodyOffset, string output, bool create, long targetSize) {
    byte[] ops;
    using (FileStream p = File.OpenRead(patch)) {
      p.Position = bodyOffset; byte[] b4 = new byte[4]; p.Read(b4, 0, 4); int opsLen = BitConverter.ToInt32(b4, 0);
      byte[] z = new byte[opsLen]; int got = 0; while (got < opsLen) got += p.Read(z, got, opsLen - got);
      using (MemoryStream ms = new MemoryStream(z)) using (DeflateStream d = new DeflateStream(ms, CompressionMode.Decompress)) using (MemoryStream o = new MemoryStream()) { d.CopyTo(o); ops = o.ToArray(); }
      using (DeflateStream data = new DeflateStream(p, CompressionMode.Decompress))
      using (FileStream src = new FileStream(orig, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20))
      using (FileStream dst = new FileStream(output, create ? FileMode.Create : FileMode.Open, FileAccess.Write, FileShare.None, 1 << 20)) {
        byte[] buf = new byte[1 << 20]; byte[] zero = new byte[1 << 20];
        for (int i = 0; i + 13 <= ops.Length; i += 13) {
          int type = ops[i]; long len = BitConverter.ToUInt32(ops, i + 1); long arg = BitConverter.ToInt64(ops, i + 5);
          if (type == 0) { dst.Position = arg; continue; }
          if (type == 1) src.Position = arg;
          while (len > 0) {
            int n = (int)Math.Min(len, buf.Length);
            if (type == 3) dst.Write(zero, 0, n);
            else {
              Stream s = type == 1 ? (Stream)src : data; int have = 0;
              while (have < n) { int r = s.Read(buf, have, n - have); if (r <= 0) throw new Exception("데이터가 모자랍니다 (원본 ISO 또는 패치 파일 손상)"); have += r; }
              dst.Write(buf, 0, n);
            }
            len -= n;
          }
        }
        if (create && dst.Length != targetSize) throw new Exception("결과 크기가 다릅니다");
      }
    }
  }
}
'@

function Fail($msg) { Write-Host ""; Write-Host "[실패] $msg" -ForegroundColor Red; exit 1 }

$core = Join-Path $here 'bo2_kor.bin'
$movies = Join-Path $here 'bo2_kor_movies.bin'
if (-not (Test-Path -LiteralPath $core)) { Fail "bo2_kor.bin 이 patch.ps1 과 같은 폴더에 없습니다." }
if (-not (Test-Path -LiteralPath $Iso -PathType Leaf)) { Fail "원본 ISO 파일을 찾을 수 없습니다: $Iso" }
$Iso = (Resolve-Path -LiteralPath $Iso).Path

$off = 0L
$h = [Bo2Patch]::Header($core, [ref]$off) | ConvertFrom-Json
Write-Host "Blood Omen 2 한글패치 v$($h.version)  -  by Yonggary6425"
Write-Host "원본: $Iso"

$size = (Get-Item -LiteralPath $Iso).Length
if ($size -ne [long]$h.origSize) { Fail "원본 ISO 크기가 다릅니다. (필요: $($h.origSize) 바이트, 지금: $size 바이트)`n  북미판 SLUS-20024 원본 ISO인지, 이미 패치한 파일이 아닌지 확인해 주세요." }
Write-Host "원본 확인 중..."
if ([Bo2Patch]::Md5($Iso) -ne $h.origMd5) { Fail "원본 ISO 내용이 제작에 쓴 원본과 다릅니다. (필요 MD5: $($h.origMd5))" }

$out = Join-Path (Split-Path -Parent $Iso) (([IO.Path]::GetFileNameWithoutExtension($Iso)) + ' (Korean).iso')
$need = [long]$h.targetSize
$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($out).Substring(0, 1)) -ErrorAction SilentlyContinue
if ($drive -and $drive.Free -lt $need) { Fail "디스크 공간이 모자랍니다. (필요: $([math]::Round($need / 1GB, 1)) GB)" }

Write-Host "한글판 만드는 중... (몇 분 걸릴 수 있습니다)"
[Bo2Patch]::Apply($Iso, $core, $off, $out, $true, $need)
$expect = $h.targetMd5; $label = '한글패치'
if (Test-Path -LiteralPath $movies) {
  $moff = 0L
  $mh = [Bo2Patch]::Header($movies, [ref]$moff) | ConvertFrom-Json
  if ($mh.baseMd5 -ne $h.targetMd5) { Fail "bo2_kor_movies.bin 이 이 버전의 패치와 맞지 않습니다." }
  Write-Host "동영상 자막 적용 중..."
  [Bo2Patch]::Apply($Iso, $movies, $moff, $out, $false, $need)
  $expect = $mh.targetMd5; $label = '한글패치 + 동영상 자막'
}
Write-Host "결과 확인 중..."
$got = [Bo2Patch]::Md5($out)
if ($got -ne $expect) { Remove-Item -LiteralPath $out -Force; Fail "결과 파일 검사값이 다릅니다. 파일을 지웠습니다. 다시 시도해 주세요." }
Write-Host ""
Write-Host "완료! ($label)" -ForegroundColor Green
Write-Host "만든 파일: $out"
Write-Host "MD5: $got"
