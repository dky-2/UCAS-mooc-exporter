<#
.SYNOPSIS
  把课程平台「导出作业附件」得到的压缩包整理成按学生命名的文件。

.DESCRIPTION
  外层压缩包内是每位学生一个 <学号>-<姓名>.zip。本脚本逐层展开，按 -Extension 筛选文件，
  套用 -NameTemplate 复制到 -OutDir，清理中间文件，最后打印校验信息。

  适用于超星泛雅 / 国科大在线教师端「更多 → 导出作业附件 → 导出提交附件」产出的压缩包。

.PARAMETER ZipPath
  外层压缩包路径，例如 班级123456-第二次作业(附件).zip。

.PARAMETER OutDir
  成品目录，最终只保留筛选后的文件。目录不存在会自动创建。

.PARAMETER Label
  作业标识，用于命名模板里的 {label}，例如 第二次作业。

.PARAMETER Extension
  只保留的文件扩展名，可传多个；默认 .pdf。传 * 表示全部保留。

.PARAMETER NameTemplate
  命名模板，支持 {name} {sid} {label}；默认 {name}-{sid}。
  同一位学生有多个匹配文件时会自动追加 -1、-2 后缀。

.PARAMETER KeepArchives
  保留临时解压目录（默认清理）。

.PARAMETER RemoveSourceZip
  整理完成后删除外层压缩包（默认保留，删除属于破坏性操作）。

.EXAMPLE
  .\collect-attachments.ps1 -ZipPath 'D:\作业导出\班级123456-第二次作业(附件).zip' `
    -OutDir 'D:\作业导出' -Label '第二次作业'

.EXAMPLE
  # 只留 PDF、落到桌面、命名带作业标识，并删除外层压缩包
  .\collect-attachments.ps1 -ZipPath 'D:\dl\hw.zip' -OutDir "$([Environment]::GetFolderPath('Desktop'))" `
    -Label '第三次作业' -NameTemplate '{name}-{sid}-{label}' -RemoveSourceZip
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ZipPath,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [Parameter(Mandatory = $true)][string]$Label,
  [string[]]$Extension = @('.pdf'),
  [string]$NameTemplate = '{name}-{sid}',
  [switch]$KeepArchives,
  [switch]$RemoveSourceZip
)

$ErrorActionPreference = 'Stop'

$zip = (Resolve-Path -LiteralPath $ZipPath).Path
if (-not (Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}
$outRoot = (Resolve-Path -LiteralPath $OutDir).Path

$takeAll = $Extension -contains '*'
$extList = @($Extension | ForEach-Object { $_.ToLower() })

$work = Join-Path ([IO.Path]::GetTempPath()) ('hw_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

function Get-SafeFileName {
  param([string]$Value)
  $invalid = -join [IO.Path]::GetInvalidFileNameChars()
  return ($Value -replace ("[{0}]" -f [Regex]::Escape($invalid)), '_')
}

$exported = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList

try {
  Expand-Archive -LiteralPath $zip -DestinationPath $work -Force

  # 展开每位学生的压缩包
  $inner = @(Get-ChildItem -LiteralPath $work -Filter '*.zip' -File)
  foreach ($z in $inner) {
    $dest = Join-Path $work $z.BaseName
    if (-not (Test-Path -LiteralPath $dest)) {
      New-Item -ItemType Directory -Path $dest | Out-Null
    }
    try {
      Expand-Archive -LiteralPath $z.FullName -DestinationPath $dest -Force
    } catch {
      [void]$warnings.Add("展开失败：$($z.Name) :: $($_.Exception.Message)")
    }
  }

  $studentDirs = @(Get-ChildItem -LiteralPath $work -Directory)
  if ($studentDirs.Count -eq 0) {
    throw "压缩包内没有找到学生压缩包：$zip"
  }

  foreach ($d in $studentDirs) {
    $parts = $d.Name -split '-', 2
    $sid = $parts[0].Trim()
    $name = if ($parts.Count -gt 1 -and $parts[1].Trim()) { $parts[1].Trim() } else { $sid }

    $files = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File)
    $picked = if ($takeAll) { $files } else { @($files | Where-Object { $extList -contains $_.Extension.ToLower() }) }

    if ($picked.Count -eq 0) {
      $seen = ($files | ForEach-Object { $_.Extension } | Sort-Object -Unique) -join ','
      [void]$warnings.Add("$($d.Name)：没有匹配 $($extList -join '/') 的文件（实际提交：$seen）")
      continue
    }

    $index = 0
    foreach ($f in $picked) {
      $index++
      $base = $NameTemplate.Replace('{name}', $name).Replace('{sid}', $sid).Replace('{label}', $Label)
      $base = Get-SafeFileName $base
      if ($picked.Count -gt 1) { $base = "$base-$index" }

      $target = Join-Path $outRoot ($base + $f.Extension.ToLower())
      $n = 2
      while (Test-Path -LiteralPath $target) {
        $target = Join-Path $outRoot ("$base`_$n" + $f.Extension.ToLower())
        $n++
      }

      Copy-Item -LiteralPath $f.FullName -Destination $target -Force
      [void]$exported.Add([pscustomobject]@{
          Student = $d.Name
          Source  = $f.Name
          Target  = $target
          Bytes   = $f.Length
        })
    }
  }
}
finally {
  if ($KeepArchives) {
    Write-Output "临时解压目录保留在：$work"
  } elseif (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
  }
}

if ($RemoveSourceZip -and (Test-Path -LiteralPath $zip)) {
  Remove-Item -LiteralPath $zip -Force
  Write-Output "已删除外层压缩包：$zip"
}

$strangers = @(
  Get-ChildItem -LiteralPath $outRoot -File |
    Where-Object {
      $_.FullName -ne $zip -and
      -not $takeAll -and
      ($extList -notcontains $_.Extension.ToLower())
    }
)

Write-Output ("已导出 {0} 个文件 -> {1}" -f $exported.Count, $outRoot)
Write-Output ("目录内非目标格式文件：{0}" -f $strangers.Count)
if ($strangers.Count -gt 0) {
  Write-Warning ("以下文件不是本次目标格式，请确认是否要清理：`n" + (($strangers | ForEach-Object { '  ' + $_.Name }) -join "`n"))
}
foreach ($w in $warnings) { Write-Warning $w }

$exported | Format-Table Student, Source, Target -AutoSize
