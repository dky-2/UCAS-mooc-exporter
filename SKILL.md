---
name: ucas-mooc-exporter
description: Batch-export one assignment's student submission attachments from a UCAS Online (国科大在线 / 超星泛雅) teacher course, then re-format and save the files locally. Use when the user asks to collect, download, or organize students' submitted homework files (作业附件) from 我教的课 or a mooc.mooc.ucas.edu.cn course page.
metadata:
  short-description: Export UCAS course assignment submissions
---

# 国科大在线 · 作业附件批量导出

## 目标

用户在「我教的课」里指定一次作业后，把该次作业全部学生提交的附件导出到本地，
按用户要求的格式、命名和路径落盘，并核对文件数与页面上的「已交」人数一致。

## 先确定这四个参数

| 参数 | 用户未指定时的默认值 |
|---|---|
| 作业 | 没有默认值，必须问清（第 N 次作业，或作业列表里的标题） |
| 附件格式 | 只保留 PDF（`.pdf`） |
| 命名形式 | `<姓名>-<学号>` |
| 保存路径 | 桌面（`[Environment]::GetFolderPath('Desktop')`） |

缺省时直接用默认值，并把实际取值写在最终答复里，不要为了确认默认值而中断。
只保留 PDF 时若某位学生交的是其他格式，在结果里点出来，让用户决定是否补导。

命名默认不带作业标识，多次作业导出到同一目录会互相覆盖。若用户要给多次作业共用一个目录，
建议改用 `{name}-{sid}-{label}` 之类的模板，并在答复里说明。

## 工作流

1. 定位作业：打开课程首页 →「作业」→ 在列表里找到目标作业，记下 `div.work<workid>` 的
   `<workid>`，以及该作业的「已交」人数（作为最终核对基准）。
2. 打开批阅页：直接跳转 `.../work/mark?...&id=<workid>...`，比在 iframe 里点「批阅」稳。
3. 触发批量导出：批阅页「更多 → 导出作业附件 → 导出提交附件 → 确定」。
4. 等打包：回课程首页打开「下载中心」，轮询到该条目状态变为「导出成功」。
5. 取直链：从无障碍树读取该条目 `<a>` 的 Value（`https://d.mooc.ucas.edu.cn/workzip/....zip?...`），现取现用。
6. 下载并整理：在终端把 zip 下载到目标路径，然后运行

   ```powershell
   ./scripts/collect-attachments.ps1 -ZipPath <zip> -OutDir <目标目录> -Label <第N次作业> `
     -Extension .pdf -NameTemplate '{name}-{sid}'
   ```

   脚本会展开两级压缩包、按格式筛选、按模板重命名、清理中间文件并打印校验信息。
7. 校验并汇报：目标目录里匹配格式的文件数应等于「已交」人数（未交学生不会出现在导出里）。
   汇报时列出文件数与命名规则；有缺格式、重名、异常学号等情况要点明。

## 不可违背的站点事实

以下几条最容易让人白跑，细节见 [references/platform-notes.md](references/platform-notes.md)。

- 导出不是浏览器下载：产物在课程首页右上角「下载中心」（`div.downloadcenter`）里排队生成。
- 下载中心里的 CDN 直链带一次性 `_enc` / `_t` 令牌，每次渲染都变，过期即失败；必须每次重新打开下载中心读取。
- 导出弹窗是页面中长期存在、平时 `display:none` 的隐藏层（`div#downWorkAttachment`）。
  判断开合要看 `getComputedStyle(el).display`，不要用「元素是否存在」。
- `window.checkPacking` 在 Playwright 的隔离求值上下文里不可见，不要调用它；
  直接点击 `#downWorkAttachment .confirmDown` 即可触发。
- 学生目录名是 `<学号>-<姓名>`；学号可能是工号形式（如 `2026E8004584031`），按第一个 `-` 切分。
- 终端联网、写入桌面或其他盘通常需要申请授权（`require_escalated`）；只读浏览不需要。

## 登录与会话

课程站点必须登录才能进入教师视角。自动化浏览器与用户本地浏览器不共享登录态：

1. 若跳转 `passport.mooc.ucas.edu.cn/login`，把浏览器窗口显示给用户，并调用 `markHandoff()` 保住标签页。
2. 请用户在该窗口完成登录（账号密码或扫码），不要代为输入凭据。
3. 用户回复后再继续；以页面标题变成课程名、导航出现「课程门户 / 作业」为已登录标志。

若目标机的浏览器面已经连着用户本机浏览器（`cua.listBrowsers()` 里有非 `iab` 项），
可以直接用已登录的浏览器，跳过这一步。

## 参考

- 站点 URL 模板、DOM 标识、浏览器操作片段、故障对照表：[references/platform-notes.md](references/platform-notes.md)
- 整理脚本用法与参数：[scripts/collect-attachments.ps1](scripts/collect-attachments.ps1)
