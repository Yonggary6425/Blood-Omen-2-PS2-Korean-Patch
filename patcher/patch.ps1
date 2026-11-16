# Blood Omen 2 (PS2 북미판 SLUS-20024) 한글패치 적용기 - Windows PowerShell 기본 기능만 사용
# 사용: 원본 ISO를 "패치하기.bat" 위에 끌어다 놓기
#       powershell -File patch.ps1 "원본.iso" [-Wide] [-Controls]     (-Ask 를 붙이면 선택 패치를 물어봅니다)
param([Parameter(Mandatory = $true)][string]$Iso, [switch]$Wide, [switch]$Controls, [switch]$Ask)
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
  static string Hex(byte[] h) { return BitConverter.ToString(h).Replace("-", "").ToLowerInvariant(); }
  public static string Md5(string file) {
    using (FileStream f = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20)) using (MD5 m = MD5.Create()) { return Hex(m.ComputeHash(f)); }
  }
  // ops: 0 SEEK(target offset) 1 COPY(original offset, length) 2 DATA(length) 3 ZERO(length)
  // returns the MD5 of every byte written, in order
  public static string Apply(string orig, string patch, long bodyOffset, string output, bool create, long targetSize) {
    byte[] ops;
    using (MD5 sum = MD5.Create())
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
            if (type == 3) { dst.Write(zero, 0, n); if (!create) sum.TransformBlock(zero, 0, n, null, 0); }
            else {
              Stream s = type == 1 ? (Stream)src : data; int have = 0;
              while (have < n) { int r = s.Read(buf, have, n - have); if (r <= 0) throw new Exception("데이터가 모자랍니다 (원본 ISO 또는 패치 파일 손상)"); have += r; }
              dst.Write(buf, 0, n); if (!create) sum.TransformBlock(buf, 0, n, null, 0);
            }
            len -= n;
          }
        }
        if (create && dst.Length != targetSize) throw new Exception("결과 크기가 다릅니다");
      }
      sum.TransformFinalBlock(new byte[0], 0, 0); return Hex(sum.Hash);
    }
  }
}
'@

function Fail($msg) { Write-Host ""; Write-Host "[실패] $msg" -ForegroundColor Red; exit 1 }
function Yes($question) { $a = Read-Host "$question (Y/N, 기본 N)"; return ($a -match '^\s*[yYㅛ]') }

$base = Join-Path $here 'bo2_kor.bin'
if (-not (Test-Path -LiteralPath $base)) { Fail "bo2_kor.bin 이 patch.ps1 과 같은 폴더에 없습니다." }
if (-not (Test-Path -LiteralPath $Iso -PathType Leaf)) { Fail "원본 ISO 파일을 찾을 수 없습니다: $Iso" }
$Iso = (Resolve-Path -LiteralPath $Iso).Path

$off = 0L
$h = [Bo2Patch]::Header($base, [ref]$off) | ConvertFrom-Json
Write-Host "Blood Omen 2 한글패치 v$($h.version)  -  by Yonggary6425"
Write-Host "원본: $Iso"
Write-Host ""

if ($Ask) {
  Write-Host "한글패치는 항상 적용됩니다. 아래 두 가지는 원하는 것만 고르세요."
  Write-Host ""
  Write-Host "[선택 1] 16:9 와이드 화면 - 시야를 좌우로 넓혀 16:9로 그립니다. (에뮬레이터·TV를 16:9로 맞춰야 합니다)"
  $Wide = Yes "  적용할까요?"
  Write-Host "[선택 2] 조작 체계 변경 - 왼쪽 스틱: 앞뒤 이동 + 좌우 게걸음 / 오른쪽 스틱: 시점 회전"
  $Controls = Yes "  적용할까요?"
  Write-Host ""
}
# 선택 패치 목록: 이름, 파일, 켰는지
$extras = @()
if ($Wide) { $extras += , @('16:9 와이드 화면', 'bo2_opt_wide.bin') }
if ($Controls) { $extras += , @('조작 체계 변경', 'bo2_opt_controls.bin') }
if (Test-Path -LiteralPath (Join-Path $here 'bo2_kor_movies.bin')) { $extras += , @('동영상 자막', 'bo2_kor_movies.bin') }
foreach ($e in $extras) { if (-not (Test-Path -LiteralPath (Join-Path $here $e[1]))) { Fail "$($e[1]) 이 patch.ps1 과 같은 폴더에 없습니다." } }

$size = (Get-Item -LiteralPath $Iso).Length
if ($size -ne [long]$h.origSize) { Fail "원본 ISO 크기가 다릅니다. (필요: $($h.origSize) 바이트, 지금: $size 바이트)`n  북미판 SLUS-20024 원본 ISO인지, 이미 패치한 파일이 아닌지 확인해 주세요." }
Write-Host "원본 확인 중..."
if ([Bo2Patch]::Md5($Iso) -ne $h.origMd5) { Fail "원본 ISO 내용이 제작에 쓴 원본과 다릅니다. (필요 MD5: $($h.origMd5))" }

$out = Join-Path (Split-Path -Parent $Iso) (([IO.Path]::GetFileNameWithoutExtension($Iso)) + ' (Korean).iso')
$need = [long]$h.targetSize
$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($out).Substring(0, 1)) -ErrorAction SilentlyContinue
if ($drive -and $drive.Free -lt $need) { Fail "디스크 공간이 모자랍니다. (필요: $([math]::Round($need / 1GB, 1)) GB)" }

Write-Host "한글판 만드는 중... (1~2분 걸립니다)"
[void][Bo2Patch]::Apply($Iso, $base, $off, $out, $true, $need)
Write-Host "결과 확인 중..."
if ([Bo2Patch]::Md5($out) -ne $h.targetMd5) { Remove-Item -LiteralPath $out -Force; Fail "결과 파일 검사값이 다릅니다. 파일을 지웠습니다. 다시 시도해 주세요." }

$applied = @('한글패치')
foreach ($e in $extras) {
  $file = Join-Path $here $e[1]; $eoff = 0L
  $eh = [Bo2Patch]::Header($file, [ref]$eoff) | ConvertFrom-Json
  if ($eh.version -ne $h.version) { Remove-Item -LiteralPath $out -Force; Fail "$($e[1]) 이 이 버전(v$($h.version))의 패치와 맞지 않습니다." }
  Write-Host "$($e[0]) 적용 중..."
  $sum = [Bo2Patch]::Apply($Iso, $file, $eoff, $out, $false, $need)
  if ($sum -ne $eh.payloadMd5) { Remove-Item -LiteralPath $out -Force; Fail "$($e[0]) 적용 검사값이 다릅니다. 결과 파일을 지웠습니다." }
  $applied += $e[0]
}
Write-Host ""
Write-Host "완료! ($($applied -join ' + '))" -ForegroundColor Green
Write-Host "만든 파일: $out"
Write-Host "MD5: $([Bo2Patch]::Md5($out))"
