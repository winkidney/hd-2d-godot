# 完整往返录像

69.460 秒、1920×1080 原始编码录像无损保存为三段二进制文件：

- `route.mp4.part-001`
- `route.mp4.part-002`
- `route.mp4.part-003`

原文件大小 125323505 字节，超过 GitHub 普通 Git 单文件限制，因此分块存储。没有重新编码、压缩画面或修改帧时间。完整文件和每段的 SHA256 记录在上一级 `archive-manifest.json` 的 `render/route.mp4` 项。

在工程根目录运行：

```sh
python3 tools/ancient_canal/restore_layout_media.py
```

工具先验证分块，再合并为本目录下的 `route.mp4`，最后核对完整录像的原始摘要。已存在的完整文件必须与该摘要一致。恢复出的文件不纳入 Git；分块和来源记录随项目保存。

可使用 `python3 tools/ancient_canal/archive_layout.py --verify-only` 直接从分块验证整个归档，无需先恢复视频。逐帧时间与包数量仍由 `route-timing.json` 保留，路线图见 `route-contact.png`。
