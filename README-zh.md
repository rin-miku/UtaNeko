<h1 align="center"><img src="assets/icon/icon-utaneko-1024.png" width="96" alt="UtaNeko" valign="middle"> UtaNeko · 歌喵</h1>
<p align="center"><a href="README.md">English</a> · <a href="README-zh.md">简体中文</a></p>
<p align="center"><sub>给日语歌的汉字标上假名并进行释义的跨平台播放器</sub></p>

UtaNeko 是一个用 Flutter 编写的播放器，给学习练习日语歌曲的小伙伴使用，提供注音和释义功能。粘贴音乐平台的链接或歌曲 ID 即可开始播放。歌词跟着音乐走，假名标在汉字上方。

词典只在需要时下载，并且只留在本机。词典或分词失败时，歌词仍显示原文，播放不受影响。

当前在 **Windows** 和 **Android** 上使用。登录凭证只保存在本机。

## Screenshot
<table>
  <tr>
    <td><img src="./screenshot/home.png" width="200"></td>
    <td><img src="./screenshot//dict.png" width="200"></td>
    <td><img src="./screenshot/settings0.png" width="200"></td>
    <td><img src="./screenshot/settings1.png" width="200"></td>
  </tr>
</table>

## 功能介绍

### 播放与歌词

- 粘贴音乐平台分享链接或歌曲 ID，音频从 CDN 直接播放。
- 当前句高亮。点某一句可跳转，翻译可以单独开关。
- 在 128K、192K、320K 和无损之间切换时，播放进度保持不变。
- 最近 10 首记在本机历史里，可从历史列表再次播放。
- 可用二维码登录，也可以从浏览器粘贴 Cookie。凭证只存在本机，用来请求可播放地址。没有对应账号时，部分歌曲仍是试听。

### 汉字注音

- 读音来自 kuromoji 与 IPADIC。第一次需要注音时，从 jsDelivr 下载词典到应用目录。
- 假名以振假名的形式画在汉字上方。分词结果按曲目缓存为 JSON。
- 下载或分词失败时会提示原因，歌词回退为原文。

### 划词查义

- 长按一句歌词，再选中词语，查询本机日中词典（JMdict，经由 Tomoshi）。
- 词典在第一次查词时从 GitHub 下载。可以在设置里删除，下次查词时会重新获取。

### 下载

- 把当前曲目保存为裸音频、旁路 `.lrc` 和封面，也可以把注音导出为 HTML。
- 默认目录是 `Downloads/UtaNeko`（没有下载目录时落到应用文档目录）。Windows 上可以另选文件夹。

### Windows 桌面

- Mini 模式是一个置顶小窗，只显示当前一句、注音和翻译。窗口离开任务栏；点托盘图标，或双击 Mini 窗口，即可回到主界面。鼠标悬停在 Mini 窗口上滚动滚轮，可切换上一句 / 下一句歌词。
- 老板键把窗口藏进托盘，播放不中断，再按一次即可唤回。
- 全局快捷键在其他应用处于前台时仍然生效。默认：Ctrl+↑ / Ctrl+↓ 切换歌词句，Ctrl+← / Ctrl+→ 隐藏和显示窗口，Ctrl+P 播放或暂停，Ctrl+M 切换 Mini。每一项都可以在设置里改。

### 外观

- 亮色、暗色，或跟随系统。歌词、注音和翻译共用一个字号滑条。

## 平台

| 平台 | 当前包含 |
| --- | --- |
| Windows | 播放、注音、查词、下载、Mini、托盘、全局快捷键、自绘标题栏 |
| Android | 播放、注音、查词、下载、历史和设置 |


## 说明

鸣谢：灵感与参考自 [utasensei](https://github.com/yichenbert/utasensei)。

UtaNeko 仅供个人学习。请支持正版，不要用于绕过付费内容或商业用途。查词词典来自 JMdict（EDRDG）与 Tomoshi（Y1Z），许可为 CC BY-SA 4.0。


